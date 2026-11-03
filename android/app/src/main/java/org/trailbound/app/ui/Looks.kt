package org.trailbound.app.ui

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.provider.Settings
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
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
import kotlin.math.cos
import kotlin.math.sin

/** The palette by name, for places that need more than the Material roles (ice blue, the logo's lighter violet). */
object VeilColors {
    val violet = Color(0xFF9D8CFF)
    val green = Color(0xFF3DDC97)
    val background = Color(0xFF07070A)
    val surface = Color(0xFF101016)
    val text = Color(0xFFD8D6E0)
    val dim = Color(0xFF9A98A6)
    val muted = Color(0xFF34333F)
    val ice = Color(0xFF8FD3FF)
    val indigo = Color(0xFF4B3BD6)
}

/**
 * Two looks, same content: Terminal (flat near-black, thin rules, faint scanlines) and Glass (frosted rounded
 * panels over a drifting ASCII field and soft colour blobs, still all monospace). Switched by tapping the home
 * logo or from Account. Mirrors iPhone's `Look` in Theme.swift.
 */
enum class Look(val title: String) {
    TERMINAL("terminal"), GLASS("glass");

    val next: Look get() = if (this == TERMINAL) GLASS else TERMINAL

    companion object {
        private const val PREFS = "profile"
        private const val KEY = "look"
        fun load(ctx: Context): Look = runCatching { valueOf(ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, TERMINAL.name)!!) }.getOrDefault(TERMINAL)
        fun save(ctx: Context, look: Look) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, look.name).apply()
    }
}

val LocalLook = compositionLocalOf { Look.TERMINAL }
/** Switches to the other look (and remembers it). */
val LocalSwitchLook = compositionLocalOf<() -> Unit> { {} }

/** Holds the current look for the whole app and provides it to every screen. */
@Composable
fun LookProvider(content: @Composable () -> Unit) {
    val ctx = LocalContext.current
    var look by remember { mutableStateOf(Look.load(ctx)) }
    CompositionLocalProvider(
        LocalLook provides look,
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
        if (LocalLook.current == Look.GLASS) GlassBackdrop() else Scanlines()
    }
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
    val t by rememberInfiniteTransition(label = "drift").animateFloat(
        0f, if (still) 0f else 1f,
        infiniteRepeatable(tween(14_000, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "t",
    )
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
 * A content panel: nothing extra in Terminal (or a filled pane with a 1 dp outline when [outlined]); a frosted,
 * rounded glass panel in Glass. Mirrors iPhone's `veilPanel`.
 */
fun Modifier.veilPanel(
    outlined: Boolean = false,
    outline: Color = VeilColors.muted,
    lineWidth: Dp = 1.dp,
    padding: Dp = 12.dp,
): Modifier = composed {
    when {
        LocalLook.current == Look.GLASS -> {
            val shape = RoundedCornerShape(22.dp)
            fillMaxWidth().clip(shape)
                .background(VeilColors.surface.copy(alpha = 0.70f))
                .background(VeilColors.violet.copy(alpha = 0.06f))
                .border(lineWidth, if (outline == VeilColors.muted) Color.White.copy(alpha = 0.08f) else outline.copy(alpha = 0.7f), shape)
                .padding(padding)
        }
        outlined -> fillMaxWidth().background(VeilColors.surface).border(lineWidth, outline, RectangleShape).padding(padding)
        else -> this
    }
}

/** Phosphor glow for the numbers and signals that matter: a soft shadow in the text's own colour. */
fun TextStyle.glow(color: Color, radius: Float = 18f): TextStyle =
    copy(color = color, shadow = Shadow(color.copy(alpha = 0.55f), Offset.Zero, radius))

