package org.trailbound.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily

/**
 * Always dark, always monospace: near-black with a violet "veil" accent and a single green signal colour.
 * No dynamic colour and no light mode, on purpose. The look is part of the identity.
 */
private val Veil = darkColorScheme(
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

private val Mono: Typography = Typography().run {
    fun androidx.compose.ui.text.TextStyle.mono() = copy(fontFamily = FontFamily.Monospace)
    copy(
        displaySmall = displaySmall.mono(), headlineMedium = headlineMedium.mono(),
        titleLarge = titleLarge.mono(), titleMedium = titleMedium.mono(), titleSmall = titleSmall.mono(),
        bodyLarge = bodyLarge.mono(), bodyMedium = bodyMedium.mono(), bodySmall = bodySmall.mono(),
        labelLarge = labelLarge.mono(), labelMedium = labelMedium.mono(), labelSmall = labelSmall.mono(),
    )
}

@Composable
fun VeilWalkerTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Veil, typography = Mono) {
        androidx.compose.material3.Surface(color = Veil.background, content = content)
    }
}
