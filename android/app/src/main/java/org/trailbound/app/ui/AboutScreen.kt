package org.trailbound.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** 3XC in figlet "standard" letters. Plain ASCII, 20 columns, so it fits at small sizes. */
private val ThreeXC = listOf(
    """ _____ __  __  ____ """,
    """|___ / \ \/ / / ___|""",
    """  |_ \  \  / | |    """,
    """ ___) | /  \ | |___ """,
    """|____/ /_/\_\ \____|""",
).joinToString("\n")

@Composable
fun ThreeXcArt(size: TextUnit, color: Color = MaterialTheme.colorScheme.primary) {
    Text(ThreeXC, color = color, fontFamily = FontFamily.Monospace, fontSize = size, lineHeight = size * 1.3f, softWrap = false)
}

/** Signature in the home screen's spare space; taps through to About. */
@Composable
fun ThreeXcFooter(modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        ThreeXcArt(9.sp, MaterialTheme.colorScheme.primary.copy(alpha = 0.6f))
        Text("// 3XCypher · walk unseen", color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
fun AboutScreen(onBack: () -> Unit, onCredits: () -> Unit) {
    val ctx = LocalContext.current
    val version = runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }.getOrNull() ?: "?"
    val dim = MaterialTheme.colorScheme.onSurfaceVariant
    val green = MaterialTheme.colorScheme.secondary

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        ThreeXcArt(15.sp)
        Text("3 X C Y P H E R", style = MaterialTheme.typography.titleMedium, color = green)
        HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.primary)

        Text("VeilWalker v$version", style = MaterialTheme.typography.titleLarge)
        Text("A walking app that doesn't watch you walk.", color = dim)

        Text("// the pledge", color = green)
        listOf(
            "no email, no phone number: 24 words are the account",
            "steps, motion and GPS stay on this phone",
            "tor on by default, never a quiet clearnet fallback",
            "no ads, no trackers, no data sold. ever",
            "points are signed, chained and yours to verify",
        ).forEach { Text("[x] $it", style = MaterialTheme.typography.bodyMedium) }

        Text("// walk for freedom", color = green)
        Text(
            "Every journey follows people who moved forward when it cost them: Tubman, Douglass, Lovelace, " +
                "Turing, Zimmermann and the ones still walking.",
            color = dim,
            style = MaterialTheme.typography.bodyMedium,
        )

        Text("// built by 3XCypher", color = green)
        Text("Systems, privacy and Tor. Made to be walked, not watched.", color = dim, style = MaterialTheme.typography.bodyMedium)

        VeilButton("Credits roll", onCredits, glyph = ">")
        VeilButton("Back", onBack, glyph = "<")
    }
}
