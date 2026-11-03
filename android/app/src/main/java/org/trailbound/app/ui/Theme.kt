package org.trailbound.app.ui

import android.app.Activity
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.core.view.WindowCompat

/**
 * Dark: near-black with a violet "veil" accent and a single green signal colour, all monospace (the original look,
 * in the Dark and Dark glass looks). Light: the same roles on white with deeper accents, in a regular sans-serif for
 * easy reading; ASCII art and number columns stay monospace wherever they set it themselves.
 * No dynamic colour, on purpose: the palette is part of the identity.
 */
private val Dark = darkColorScheme(
    primary = Color(0xFF9D8CFF),
    onPrimary = Color(0xFF0B0A12),
    secondary = Color(0xFF3DDC97),
    onSecondary = Color(0xFF04140D),
    background = Color(0xFF07070A),
    onBackground = Color(0xFFD8D6E0),
    surface = Color(0xFF101016),
    onSurface = Color(0xFFD8D6E0),
    surfaceVariant = Color(0xFF17171F),
    onSurfaceVariant = Color(0xFF9A98A6),
    surfaceContainerHighest = Color(0xFF15151C),
    outline = Color(0xFF34333F),
)

private val Light = lightColorScheme(
    primary = Color(0xFF5B45D9),
    onPrimary = Color(0xFFFFFFFF),
    secondary = Color(0xFF0B8A57),
    onSecondary = Color(0xFFFFFFFF),
    background = Color(0xFFF5F4FA),
    onBackground = Color(0xFF1D1B26),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF1D1B26),
    surfaceVariant = Color(0xFFECEAF3),
    onSurfaceVariant = Color(0xFF55516A),
    surfaceContainerHighest = Color(0xFFF0EEF6),
    outline = Color(0xFF8A869B),
    outlineVariant = Color(0xFFE2DFEC),
)

private val Mono: Typography = Typography().run {
    fun androidx.compose.ui.text.TextStyle.mono() = copy(fontFamily = FontFamily.Monospace)
    copy(
        displaySmall = displaySmall.mono(), headlineMedium = headlineMedium.mono(),
        titleLarge = titleLarge.mono(), titleMedium = titleMedium.mono(), titleSmall = titleSmall.mono(),
        bodyLarge = bodyLarge.mono(), bodyMedium = bodyMedium.mono(), bodySmall = bodySmall.mono(),
        labelLarge = labelLarge.mono(), labelMedium = labelMedium.mono(), labelSmall = labelSmall.mono(),
    )
}

/** Material colours and type for a dark or light look. */
@Composable
fun VeilThemeColors(dark: Boolean, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (dark) Dark else Light, typography = if (dark) Mono else Typography(), content = content)
}

@Composable
fun VeilWalkerTheme(content: @Composable () -> Unit) {
    LookProvider {
        val dark = LocalLook.current.dark
        // Status and navigation bar icons: dark on the light look, light on the dark ones.
        val view = LocalView.current
        if (!view.isInEditMode) SideEffect {
            val bars = WindowCompat.getInsetsController((view.context as Activity).window, view)
            bars.isAppearanceLightStatusBars = !dark
            bars.isAppearanceLightNavigationBars = !dark
        }
        VeilThemeColors(dark) {
            // The look's backdrop (light wash, scanlines or the glass aurora) sits behind every screen.
            Box {
                VeilBackdrop()
                Surface(color = Color.Transparent, contentColor = MaterialTheme.colorScheme.onBackground, content = content)
            }
        }
    }
}
