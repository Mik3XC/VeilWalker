package org.trailbound.app.ui

import android.content.Context
import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp

/** Bump when the consent text changes materially; users are asked again. */
private const val CONSENT_VERSION = 1

object Consent {
    const val PRIVACY_URL = "https://sites.google.com/view/veilwalker-app/privacy"
    const val HEALTH_URL = "https://sites.google.com/view/veilwalker-app/health-data"
    const val TERMS_URL = "https://sites.google.com/view/veilwalker-app/terms"

    fun given(ctx: Context) = ctx.getSharedPreferences("consent", Context.MODE_PRIVATE).getInt("version", 0) >= CONSENT_VERSION
    fun record(ctx: Context) = ctx.getSharedPreferences("consent", Context.MODE_PRIVATE).edit().putInt("version", CONSENT_VERSION).apply()
}

/**
 * Separate, affirmative consent for consumer health data before anything is collected (Washington My Health
 * My Data Act and similar state laws). Nothing runs (no step counting, no permissions) until this is accepted.
 */
@Composable
fun ConsentScreen(onAccept: () -> Unit) {
    var health by remember { mutableStateOf(false) }
    var terms by remember { mutableStateOf(false) }
    val uri = LocalUriHandler.current
    val green = MaterialTheme.colorScheme.secondary
    val violet = MaterialTheme.colorScheme.primary
    val dim = MaterialTheme.colorScheme.onSurfaceVariant

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("VeilWalker", style = MaterialTheme.typography.headlineMedium)
        HorizontalDivider(thickness = 1.dp, color = violet)
        Text("Before you walk", style = MaterialTheme.typography.titleLarge)

        Text("// what we collect", color = green)
        Text(
            "Step counts, motion-sensor readings and, during walks, GPS location. These are consumer health data. " +
                "They're processed on this phone. Raw motion and GPS data never leave it and are deleted after 30 days.",
            color = dim,
        )
        Text("// what leaves your phone", color = green)
        Text(
            "Only daily step totals by type and an anti-cheat score, signed by your device key, so points can be issued. " +
                "No name, email, phone number, contacts or precise location. Sent over Tor by default.",
            color = dim,
        )
        Text("// what we never do", color = green)
        Text("Sell, share or rent your data. No ads, no trackers, no analytics SDKs.", color = dim)
        Text("// your control", color = green)
        Text("Withdraw consent and delete your account any time in @ account. Deletion removes your synced data.", color = dim)

        Text("> read the consumer health data policy", color = violet, modifier = Modifier.clickable { uri.openUri(Consent.HEALTH_URL) })
        Text("> read the privacy policy", color = violet, modifier = Modifier.clickable { uri.openUri(Consent.PRIVACY_URL) })
        Text("> read the terms", color = violet, modifier = Modifier.clickable { uri.openUri(Consent.TERMS_URL) })

        Text(
            (if (health) "[x] " else "[ ] ") + "I consent to VeilWalker collecting and processing my step, motion and location data as described above.",
            color = if (health) green else MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.clickable { health = !health }.padding(vertical = 6.dp),
        )
        Text(
            (if (terms) "[x] " else "[ ] ") + "I'm 13 or older and agree to the terms.",
            color = if (terms) green else MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.clickable { terms = !terms }.padding(vertical = 6.dp),
        )
        VeilButton("Start walking", onAccept, enabled = health && terms, filled = true)
    }
}
