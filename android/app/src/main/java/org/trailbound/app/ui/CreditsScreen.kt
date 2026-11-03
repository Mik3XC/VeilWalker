package org.trailbound.app.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue

/** (project, license, what it does in VeilWalker). Keep in sync with the build; these are also our attribution notices. */
private val Credits = listOf(
    "THE TOR PROJECT" to listOf(
        "Arti (Rust Tor) · MIT/Apache-2.0",
        "Tor network · volunteer relays",
        "Snowflake · BSD-3-Clause",
        "Pion WebRTC · MIT",
        "Go · BSD-3-Clause",
    ),
    "ANDROID & KOTLIN" to listOf(
        "Android SDK / AOSP     · Apache-2.0",
        "Kotlin & coroutines    · Apache-2.0",
        "Jetpack Compose        · Apache-2.0",
        "Room, WorkManager      · Apache-2.0",
        "Lifecycle, Activity    · Apache-2.0",
        "Hilt / Dagger          · Apache-2.0",
        "Play services location · Google APIs ToS",
    ),
    "NETWORK & CRYPTO" to listOf(
        "OkHttp            · Apache-2.0",
        "Bouncy Castle     · MIT-style",
        "kotlin-bip39      · MIT",
        "rustls / ring     · Apache-2.0 / ISC",
        "tokio             · MIT",
        "jni-rs            · MIT / Apache-2.0",
        "SQLite            · public domain",
    ),
    "SERVER" to listOf(
        "Rust              · MIT / Apache-2.0",
        "Axum, Tower       · MIT",
        "sqlx              · MIT / Apache-2.0",
        "ed25519-dalek     · BSD-3-Clause",
        "PostgreSQL        · PostgreSQL License",
        "Railway           · hosting",
    ),
    "HISTORY & IDEAS" to listOf(
        "Library of Congress & public archives",
        "cypherpunks, phreaks & privacy coders",
    ),
    "MADE BY" to listOf(
        "3XCypher",
        "with Claude (Anthropic)",
    ),
)

/** Star Wars style but monospace: the credits crawl up forever. */
@Composable
fun CreditsScreen(onBack: () -> Unit) {
    var boxH by remember { mutableIntStateOf(1) }
    var textH by remember { mutableIntStateOf(1) }
    val anim = rememberInfiniteTransition(label = "credits")
    val t by anim.animateFloat(0f, 1f, infiniteRepeatable(tween(40_000, easing = LinearEasing), RepeatMode.Restart), label = "roll")
    val violet = MaterialTheme.colorScheme.primary
    val green = MaterialTheme.colorScheme.secondary

    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
            Modifier.weight(1f).fillMaxWidth().clipToBounds().onSizeChanged { boxH = it.height },
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                Modifier.fillMaxWidth().onSizeChanged { textH = it.height }
                    .graphicsLayer { translationY = boxH - t * (boxH + textH) },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                ThreeXcArt(14.sp)
                Text("V E I L W A L K E R", color = green, fontFamily = FontFamily.Monospace)
                Text("built on the shoulders of open source", color = MaterialTheme.colorScheme.onSurfaceVariant, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                Credits.forEach { (section, lines) ->
                    Text("", fontSize = 8.sp)
                    Text("== $section ==", color = violet, fontFamily = FontFamily.Monospace)
                    lines.forEach { Text(it, fontFamily = FontFamily.Monospace, fontSize = 11.sp, textAlign = TextAlign.Center) }
                }
                Text("", fontSize = 8.sp)
                Text("walk the world. leave no trace.", color = green, fontFamily = FontFamily.Monospace)
            }
        }
        VeilButton("Back", onBack, glyph = "<")
    }
}
