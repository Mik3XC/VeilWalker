package org.trailbound.app.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun AvatarArt(index: Int, size: TextUnit = 13.sp, color: Color = MaterialTheme.colorScheme.primary) {
    Text(
        Avatars[index].art,
        color = color,
        fontFamily = FontFamily.Monospace,
        fontSize = size,
        lineHeight = size * 1.1f,
        softWrap = false,
    )
}

/** Four framed tiles; the chosen one gets the violet frame. */
@Composable
fun AvatarPicker(selected: Int, onSelect: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Avatars.forEachIndexed { i, a ->
            val on = i == selected
            Column(
                Modifier
                    .weight(1f)
                    .border(1.dp, if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline, RectangleShape)
                    .veilClick { onSelect(i) }
                    .padding(vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                AvatarArt(i, size = 9.sp, color = if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    if (on) "[${a.name}]" else a.name,
                    color = if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
    }
}
