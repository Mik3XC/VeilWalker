package org.trailbound.app.ui

import android.view.WindowManager
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun AccountScreen(onBack: () -> Unit, vm: AccountViewModel = hiltViewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val avatar by vm.avatar.collectAsStateWithLifecycle()
    val weatherOn by vm.weatherOn.collectAsStateWithLifecycle()
    var restoreText by remember { mutableStateOf("") }

    // Block screenshots and the recents thumbnail while the recovery phrase can be on screen.
    val window = LocalActivity.current?.window
    DisposableEffect(window) {
        window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        onDispose { window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }
    }

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Account", style = MaterialTheme.typography.headlineMedium)
        Text("No email, no phone number. Your 24 words are your account.")

        Text("Clan", style = MaterialTheme.typography.titleMedium)
        val tag = state.clan
        if (tag != null) {
            Text("[$tag] ${state.username ?: ""}", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.secondary)
            VeilButton("Leave [$tag]", vm::clanLeave, enabled = !state.busy, glyph = "x")
        } else {
            var clanText by remember { mutableStateOf("") }
            Text("A 2–4 character tag shown before your name, like [ROX] ${state.username ?: "HashCat"}.")
            OutlinedTextField(
                value = clanText,
                onValueChange = { clanText = it.filter { c -> c.isLetterOrDigit() }.take(4).uppercase() },
                label = { Text("clan tag") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            VeilButton("Join [$clanText]", { vm.clanJoin(clanText) }, enabled = !state.busy && clanText.length >= 2, glyph = ">")
            VeilButton("Create [$clanText]", { vm.clanCreate(clanText) }, enabled = !state.busy && clanText.length >= 2, glyph = "+")
        }

        Text("Profile picture", style = MaterialTheme.typography.titleMedium)
        AvatarPicker(avatar, vm::pickAvatar)
        Text("ID: ${state.publicKey?.take(16)}…", fontFamily = FontFamily.Monospace)

        val handle = state.username
        if (handle != null) {
            Text("@$handle", style = MaterialTheme.typography.titleLarge, fontFamily = FontFamily.Monospace)
        } else {
            var claimText by remember { mutableStateOf("") }
            Text("Claim your handle", style = MaterialTheme.typography.titleMedium)
            Text("One name. Permanent. It can never be changed or freed. 5–20 letters, numbers or _. Don't use your real name.")
            OutlinedTextField(
                value = claimText,
                onValueChange = { claimText = it.filter { c -> c.isLetterOrDigit() || c == '_' }.take(20) },
                label = { Text("handle") },
                prefix = { Text("@") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            VeilButton("Claim @$claimText forever", { vm.claim(claimText) }, enabled = !state.busy && claimText.length >= 5, filled = true, glyph = "!")
        }

        VeilButton(if (state.words == null) "Show recovery phrase" else "Hide recovery phrase", vm::toggleWords, glyph = "#")
        state.words?.let { words ->
            Text("Write these down in order and keep them offline. Anyone with them controls your points.")
            Text(
                words.mapIndexed { i, w -> "${i + 1}. $w" }.chunked(3).joinToString("\n") { it.joinToString("   ") },
                fontFamily = FontFamily.Monospace,
            )
        }

        val look = LocalLook.current
        val switchLook = LocalSwitchLook.current
        VeilButton("Look: ${look.title} (tap to switch)", switchLook, glyph = "~")
        Text(
            "// light is the easy-reading default. dark is the classic terminal. dark glass is frosted panels over a drifting ASCII aurora. Tap the logo on the home screen to cycle them.",
            color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.bodySmall,
        )

        VeilButton(if (weatherOn) "Weather: on (tap to turn off)" else "Weather: off (tap to turn on)", vm::toggleWeather, glyph = if (weatherOn) "*" else "o")
        Text(
            "// what weather collects: your last known location, rounded to about 11 km, is sent straight from " +
                "this phone to the US National Weather Service (api.weather.gov), over Tor when Tor is on. " +
                "We never receive it, and only the temperature is kept. Weather is what powers the \u2744 and " +
                "Hidden Peaks, which count climb only on freezing walks. Turn it off and nothing is sent.",
            color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.bodySmall,
        )

        VeilButton("Sync now", vm::syncNow, enabled = !state.busy, glyph = "~")
        state.syncStatus?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }

        Text("Restore from recovery phrase", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(
            value = restoreText,
            onValueChange = { restoreText = it },
            label = { Text("24 words, separated by spaces") },
            modifier = Modifier.fillMaxWidth(),
        )
        VeilButton(
            "Restore (replaces this account)",
            { vm.restore(restoreText); restoreText = "" },
            enabled = !state.busy && restoreText.trim().split(Regex("\\s+")).size == 24,
            glyph = "!",
        )

        Text("Delete account", style = MaterialTheme.typography.titleMedium)
        Text("Deletes your synced data from the server and wipes this phone's VeilWalker data. Your handle stays reserved. Can't be undone. Back up your 24 words first if you might come back.")
        var confirm by remember { mutableStateOf("") }
        OutlinedTextField(
            value = confirm,
            onValueChange = { confirm = it.uppercase().take(6) },
            label = { Text("type DELETE") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        val ctx = androidx.compose.ui.platform.LocalContext.current
        VeilButton("Delete account", { vm.deleteAccount(ctx) }, enabled = !state.busy && confirm == "DELETE", glyph = "x")

        VeilButton("Back", onBack, glyph = "<")
    }
}
