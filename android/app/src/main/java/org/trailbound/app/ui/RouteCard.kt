package org.trailbound.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import org.trailbound.core.route.LatLng
import org.trailbound.core.route.RouteProgress

/** The route as a bare line on black with milestone dots and a marker: no map tiles, nothing fetched. */
@Composable
/** [compact] = home-screen size: shorter sketch, one-line stats, postcards behind [onOpen]. */
fun RouteCard(p: RouteProgress, compact: Boolean = false, onOpen: () -> Unit = {}) {
    val pos = p.position
    var openPostcard by remember { mutableStateOf<String?>(null) }
    val line = MaterialTheme.colorScheme.outline
    val walked = MaterialTheme.colorScheme.primary
    val marker = MaterialTheme.colorScheme.secondary

    Column(Modifier.veilPanel(outlined = true, outline = line, padding = 0.dp)) {
        Column(Modifier.padding(if (compact) 12.dp else 16.dp), verticalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 8.dp)) {
            Text(p.route.title, style = if (compact) MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleLarge)
            Text(p.route.subtitle, style = MaterialTheme.typography.bodySmall, maxLines = if (compact) 1 else Int.MAX_VALUE, overflow = TextOverflow.Ellipsis)

            Canvas(Modifier.fillMaxWidth().height(if (compact) 96.dp else 180.dp)) {
                val pts = p.route.milestones.map { it.point }
                val minLat = pts.minOf { it.lat }; val maxLat = pts.maxOf { it.lat }
                val minLng = pts.minOf { it.lng }; val maxLng = pts.maxOf { it.lng }
                val pad = 12.dp.toPx()
                // Keep aspect ratio so the route isn't stretched.
                val scale = minOf((size.width - 2 * pad) / (maxLng - minLng), (size.height - 2 * pad) / (maxLat - minLat))
                fun at(ll: LatLng) = Offset(
                    (pad + (ll.lng - minLng) * scale).toFloat(),
                    (size.height - pad - (ll.lat - minLat) * scale).toFloat(),
                )
                val path = Path().apply { pts.forEachIndexed { i, ll -> if (i == 0) moveTo(at(ll).x, at(ll).y) else lineTo(at(ll).x, at(ll).y) } }
                drawPath(path, line, style = Stroke(width = 2.dp.toPx()))
                val done = Path().apply {
                    pos.unlocked.forEachIndexed { i, m -> if (i == 0) moveTo(at(m.point).x, at(m.point).y) else lineTo(at(m.point).x, at(m.point).y) }
                    lineTo(at(pos.point).x, at(pos.point).y)
                }
                drawPath(done, walked, style = Stroke(width = 4.dp.toPx()))
                p.route.milestones.forEachIndexed { i, m ->
                    drawCircle(if (i < pos.unlocked.size) walked else line, radius = 4.dp.toPx(), center = at(m.point))
                }
                drawCircle(marker, radius = 7.dp.toPx(), center = at(pos.point))
            }

            Text(asciiBar(pos.travelledM / p.route.lengthM), color = MaterialTheme.colorScheme.primary)
            if (compact) {
                // One line of stats on the home screen, so the whole home fits without scrolling.
                Text(
                    "%.1f / %.0f km".format(pos.travelledM / 1000, p.route.lengthM / 1000) +
                        (pos.next?.let { " · next: ${it.name} in %.1f km".format((pos.toNextM ?: 0.0) / 1000) } ?: " · chapter complete"),
                    style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                Text(
                    "> postcards ${pos.unlocked.size}/${p.route.milestones.size}",
                    color = MaterialTheme.colorScheme.primary,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.fillMaxWidth().veilClick(onClick = onOpen),
                )
                return@Column
            }
            Text("%.1f / %.0f km · stride %.2f m".format(pos.travelledM / 1000, p.route.lengthM / 1000, p.strideM), style = MaterialTheme.typography.bodySmall)
            pos.next?.let { Text("next: ${it.name} in %.1f km".format((pos.toNextM ?: 0.0) / 1000), style = MaterialTheme.typography.bodySmall) }
                ?: Text("Chapter complete.")

            Text("Postcards ${pos.unlocked.size}/${p.route.milestones.size}", style = MaterialTheme.typography.titleSmall)
            pos.unlocked.forEach { m ->
                Text(
                    (if (openPostcard == m.name) "▾ " else "▸ ") + m.name,
                    Modifier.fillMaxWidth().veilClick { openPostcard = if (openPostcard == m.name) null else m.name },
                )
                if (openPostcard == m.name) Text(m.postcard, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}
