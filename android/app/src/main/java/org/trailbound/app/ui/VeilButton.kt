package org.trailbound.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import android.view.HapticFeedbackConstants
import androidx.compose.ui.composed
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Terminal-style action: just `> label` in violet monospace, no box. The whole row is the touch target;
 * it flashes inverted (violet bar, dark text) while pressed. [filled] marks the main action (green).
 */
@Composable
fun VeilButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    glyph: String = ">",
    enabled: Boolean = true,
    filled: Boolean = false,
) {
    val accent = if (filled) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.primary
    val dark = MaterialTheme.colorScheme.onPrimary
    val muted = MaterialTheme.colorScheme.outline
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val view = LocalView.current

    Box(
        modifier
            .fillMaxWidth()
            .background(if (pressed && enabled) accent else Color.Transparent)
            .clickable(interaction, indication = null, enabled = enabled, role = Role.Button) { view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK); onClick() }
            .padding(vertical = 6.dp, horizontal = 4.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(
            "$glyph ${label.lowercase()}",
            color = when { !enabled -> muted; pressed -> dark; else -> accent },
            fontWeight = if (filled) FontWeight.Bold else FontWeight.Normal,
            letterSpacing = 0.5.sp,
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

/** `[##########..........]  42.0%`: progress as text, legible even at fractions of a percent. */
fun asciiBar(fraction: Double, width: Int = 22): String {
    val f = fraction.coerceIn(0.0, 1.0)
    // Show at least one '#' once anything has been walked, so day one isn't an empty bar.
    val filled = if (f > 0) maxOf(1, (f * width).toInt()) else 0
    return "[" + "#".repeat(filled) + ".".repeat(width - filled) + "] " + "%.1f%%".format(f * 100)
}

/** Plain tappable anything (tiles, bars, links) with the same light haptic tick as [VeilButton]. */
fun Modifier.veilClick(enabled: Boolean = true, onClick: () -> Unit): Modifier = composed {
    val view = LocalView.current
    clickable(enabled = enabled, role = Role.Button) { view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK); onClick() }
}
