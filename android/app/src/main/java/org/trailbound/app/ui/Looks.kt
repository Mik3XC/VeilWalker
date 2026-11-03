package org.trailbound.app.ui

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.sin

/**
 * The colours by role. Dark is the original near-black with a violet veil and a green signal; Light is the same
 * identity on white, with the accents deepened so text keeps at least 4.5:1 contrast. [hairline] is for panel
 * outlines only; [muted] is for de-emphasised text.
 */
data class VeilPalette(
    val violet: Color,
    val green: Color,
    val background: Color,
    val surface: Color,
    val text: Color,
    val dim: Color,
    val muted: Color,
    val hairline: Color,
    val ice: Color,
    val indigo: Color,
) {
    companion object {
        val Dark = VeilPalette(
            violet = Color(0xFF9D8CFF), green = Color(0xFF3DDC97), background = Color(0xFF07070A),
            surface = Color(0xFF101016), text = Color(0xFFD8D6E0), dim = Color(0xFF9A98A6),
            muted = Color(0xFF34333F), hairline = Color(0xFF34333F), ice = Color(0xFF8FD3FF), indigo = Color(0xFF4B3BD6),
        )
        val Light = VeilPalette(
            violet = Color(0xFF5B45D9), green = Color(0xFF0B8A57), background = Color(0xFFF5F4FA),
            surface = Color(0xFFFFFFFF), text = Color(0xFF1D1B26), dim = Color(0xFF55516A),
            muted = Color(0xFF8A869B), hairline = Color(0xFFE2DFEC), ice = Color(0xFF1B78AE), indigo = Color(0xFF4B3BD6),
        )
    }
}

val LocalPalette = staticCompositionLocalOf { VeilPalette.Dark }

/** The current look's palette by name, for places that need more than the Material roles (ice blue, hairlines). */
object VeilColors {
    val violet: Color @Composable @ReadOnlyComposable get() = LocalPalette.current.violet
    val green: Color @Composable @ReadOnlyComposable get() = LocalPalette.current.green
    val background: Color @Composable @ReadOnlyComposable get() = LocalPalette.current.background
    val surface: Color @Composable @ReadOnlyComposable get() = LocalPalette.current.surface
    val text: Color @Composable @ReadOnlyComposable get() = LocalPalette.current.text
    val dim: Color @Composable @ReadOnlyComposable get() = LocalPalette.current.dim
    val muted: Color @Composable @ReadOnlyComposable get() = LocalPalette.current.muted
    val hairline: Color @Composable @ReadOnlyComposable get() = LocalPalette.current.hairline
    val ice: Color @Composable @ReadOnlyComposable get() = LocalPalette.current.ice
    val indigo: Color @Composable @ReadOnlyComposable get() = LocalPalette.current.indigo
}

/**
 * Three looks, same content. Light (the default): white cards on a soft lavender-white, readable sans-serif text,
 * ASCII art still monospace. Dark: the original terminal (flat near-black, thin rules, faint scanlines). Dark glass:
 * frosted rounded panels over a drifting ASCII field. Tapping the home logo cycles them; Account switches too.
 */
enum class Look(val title: String, val dark: Boolean) {
    LIGHT("light", false), TERMINAL("dark", true), GLASS("dark glass", true);

    val next: Look get() = entries[(ordinal + 1) % entries.size]
    val palette: VeilPalette get() = if (dark) VeilPalette.Dark else VeilPalette.Light

    companion object {
        private const val PREFS = "profile"
        private const val KEY = "look"
        fun load(ctx: Context): Look = runCatching { valueOf(ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, LIGHT.name)!!) }.getOrDefault(LIGHT)
        fun save(ctx: Context, look: Look) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, look.name).apply()
    }
}

val LocalLook = compositionLocalOf { Look.LIGHT }
/** Switches to the other look (and remembers it). */
val LocalSwitchLook = compositionLocalOf<() -> Unit> { {} }

/** Holds the current look for the whole app and provides it to every screen. */
@Composable
fun LookProvider(content: @Composable () -> Unit) {
    val ctx = LocalContext.current
    var look by remember { mutableStateOf(Look.load(ctx)) }
    CompositionLocalProvider(
        LocalLook provides look,
        LocalPalette provides look.palette,
        LocalSwitchLook provides { look = look.next; Look.save(ctx, look) },
        content = content,
    )
}

/** True when the user has turned animations off in developer or accessibility settings. */
@Composable
fun animationsOff(): Boolean {
    val ctx = LocalContext.current
    return remember { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

/**
 * The full-screen backdrop behind every screen. Everything is drawn once and only moved with graphicsLayer: on
 * iPhone a per-frame redraw ate 85% CPU and starved taps, so nothing here redraws while it drifts.
 */
@Composable
fun VeilBackdrop() {
    Box(Modifier.fillMaxSize().background(VeilColors.background)) {
        when (LocalLook.current) {
            Look.GLASS -> GlassBackdrop()
            Look.TERMINAL -> Scanlines()
            Look.LIGHT -> LightWash()
        }
    }
}

/** Light: a soft lavender wash at the top fading into the page, drawn once. */
@Composable
private fun LightWash() {
    val violet = VeilColors.violet
    Box(
        Modifier.fillMaxSize().drawWithCache {
            val wash = Brush.verticalGradient(listOf(violet.copy(alpha = 0.10f), Color.Transparent), endY = size.height * 0.45f)
            onDrawBehind { drawRect(wash) }
        }
    )
}

@Composable
private fun Scanlines() {
    Box(
        Modifier.fillMaxSize().drawWithCache {
            val line = Color.White.copy(alpha = 0.05f)
            onDrawBehind {
                var y = 0f
                while (y < size.height) { drawRect(line, Offset(0f, y), Size(size.width, 1f)); y += 3f }
            }
        }
    )
}

@Composable
private fun GlassBackdrop() {
    val still = animationsOff()
    // The drift is slow (a few dp a second), so 20 updates a second look the same as 120 and cost a fraction of the
    // CPU (measured on an S26: 35% at the display rate). Eased back and forth over 14 s, like the iPhone.
    var t by remember { mutableFloatStateOf(0f) }
    if (!still) LaunchedEffect(Unit) {
        val start = System.currentTimeMillis()
        while (true) {
            val phase = ((System.currentTimeMillis() - start) % 28_000) / 14_000f
            val x = if (phase < 1f) phase else 2f - phase
            t = x * x * (3 - 2 * x)
            delay(50)
        }
    }
    val px = with(LocalDensity.current) { 1.dp.toPx() }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        // ASCII field, 120 dp larger than the screen so it can drift without showing an edge.
        AsciiField(
            Modifier.requiredSize(maxWidth + 120.dp, maxHeight + 120.dp)
                .graphicsLayer { translationX = (10 - 60 * t) * px; translationY = (10 - 50 * t) * px; alpha = 0.11f }
        )
        Blob(VeilColors.violet, 420.dp) { Offset(w * (0.15f + 0.20f * t), h * (0.22f + 0.16f * t)) }
        Blob(VeilColors.green, 300.dp) { Offset(w * (0.92f - 0.20f * t), h * (0.68f + 0.14f * t)) }
        Blob(VeilColors.indigo, 380.dp) { Offset(w * (0.40f + 0.22f * t), h * (1.08f - 0.08f * t)) }
    }
}

/** A soft colour blob: a radial gradient drawn once, moved by its centre each frame without a redraw. */
@Composable
private fun Blob(color: Color, size: Dp, center: () -> Offset) {
    Box(
        Modifier.requiredSize(size)
            .graphicsLayer {
                val c = center()
                translationX = c.x - size.toPx() / 2
                translationY = c.y - size.toPx() / 2
            }
            .drawWithCache {
                val brush = Brush.radialGradient(listOf(color.copy(alpha = 0.45f), color.copy(alpha = 0.18f), Color.Transparent))
                onDrawBehind { drawCircle(brush) }
            }
    )
}

/** A fixed field of ASCII characters, drawn once into the layer's cache: what the glass panels sit over. */
@Composable
private fun AsciiField(modifier: Modifier) {
    val cellPx = with(LocalDensity.current) { 14.dp.toPx() }
    val textPx = with(LocalDensity.current) { 11.dp.toPx() }
    Canvas(modifier.drawWithCache {
        val glyphs = " .:-=+*#%@"
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.rgb(0x9D, 0x8C, 0xFF); textSize = textPx; typeface = Typeface.MONOSPACE
        }
        val cols = (size.width / cellPx).toInt() + 1
        val rows = (size.height / cellPx).toInt() + 1
        onDrawBehind {
            drawIntoCanvas { canvas ->
                for (r in 0 until rows) for (c in 0 until cols) {
                    val v = sin(c * 0.35) + cos(r * 0.28) + sin((c + r) * 0.15)
                    val i = ((v + 3) / 6 * (glyphs.length - 1)).toInt().coerceIn(0, glyphs.length - 1)
                    if (i > 0) canvas.nativeCanvas.drawText(glyphs[i].toString(), c * cellPx, r * cellPx, paint)
                }
            }
        }
    }) {}
}

/**
 * A content panel. Terminal: nothing extra, or a filled pane with a 1 dp outline when [outlined]. Glass: a frosted,
 * rounded panel (mirrors iPhone's `veilPanel`). Light: a white rounded card with a hairline and a soft shadow, for
 * every panel. [outline] defaults to the look's hairline; an accent outline is kept (softened in Light).
 */
fun Modifier.veilPanel(
    outlined: Boolean = false,
    outline: Color = Color.Unspecified,
    lineWidth: Dp = 1.dp,
    padding: Dp = 12.dp,
): Modifier = composed {
    val plain = outline == Color.Unspecified
    when (LocalLook.current) {
        Look.GLASS -> {
            val shape = RoundedCornerShape(22.dp)
            fillMaxWidth().clip(shape)
                .background(VeilColors.surface.copy(alpha = 0.70f))
                .background(VeilColors.violet.copy(alpha = 0.06f))
                .border(lineWidth, if (plain) Color.White.copy(alpha = 0.08f) else outline.copy(alpha = 0.7f), shape)
                .padding(padding)
        }
        Look.LIGHT -> {
            val shape = RoundedCornerShape(16.dp)
            fillMaxWidth()
                .shadow(2.dp, shape, ambientColor = VeilColors.violet.copy(alpha = 0.25f), spotColor = VeilColors.violet.copy(alpha = 0.25f))
                .clip(shape)
                .background(VeilColors.surface)
                .border(lineWidth, if (plain) VeilColors.hairline else outline.copy(alpha = 0.55f), shape)
                .padding(padding)
        }
        Look.TERMINAL ->
            if (outlined) fillMaxWidth().background(VeilColors.surface).border(lineWidth, if (plain) VeilColors.muted else outline, RectangleShape).padding(padding)
            else this
    }
}

/**
 * Phosphor glow for the numbers and signals that matter: a soft shadow in the text's own colour. Light has no glow
 * (a halo on white just looks blurry); the colour still carries the signal.
 */
@Composable
@ReadOnlyComposable
fun TextStyle.glow(color: Color, radius: Float = 18f): TextStyle =
    if (!LocalLook.current.dark) copy(color = color)
    else copy(color = color, shadow = Shadow(color.copy(alpha = 0.55f), Offset.Zero, radius))

/**
 * Keeps a screen dark whatever the look (Wake Mode over its dark art, the terminal credits crawl). Light becomes
 * Dark; the dark looks stay as they are.
 */
@Composable
fun ForceDark(content: @Composable () -> Unit) {
    val look = LocalLook.current
    if (look.dark) return content()
    CompositionLocalProvider(LocalLook provides Look.TERMINAL, LocalPalette provides VeilPalette.Dark) {
        VeilThemeColors(dark = true) {
            Box { VeilBackdrop(); androidx.compose.material3.Surface(color = Color.Transparent, contentColor = VeilPalette.Dark.text, content = content) }
        }
    }
}

