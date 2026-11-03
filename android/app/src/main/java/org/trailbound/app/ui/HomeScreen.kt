package org.trailbound.app.ui

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.trailbound.app.R
import org.trailbound.core.net.TorState
import org.trailbound.core.route.Journeys
import org.trailbound.core.steps.AutoWalk
import org.trailbound.core.steps.WalkStatus

/** `(%) tor on · onion ok` when on, `[x] tor off` when off. Tapping toggles. */
private fun torLine(on: Boolean, t: TorState): String = if (!on) "[x] tor off" else "(%) tor on · " + when (t) {
    TorState.Off, TorState.Bootstrapping -> "connecting…"
    is TorState.Ready -> when (t.onionReachable) { true -> "onion ok"; null -> "onion checking\u2026"; false -> "onion retrying" }
    is TorState.Failed -> "waiting"
}

private fun mmss(ms: Long) = "%d:%02d".format(ms / 60_000, ms / 1000 % 60)

private fun walkLine(w: WalkStatus): String = when (w) {
    WalkStatus.Idle -> "walk: auto · 27 s of steps starts it"
    is WalkStatus.Confirming -> "walk: detecting… ${w.walkingForMs / 1000}/${AutoWalk.CONFIRM_MS / 1000} s"
    is WalkStatus.Walking -> "walk: ${mmss(System.currentTimeMillis() - w.startedMs)} · ${w.steps} steps" + if (!w.gps) " · no gps" else ""
    is WalkStatus.Paused -> if (w.idleMs >= AutoWalk.RED_LIGHT_MS) "walk: red light? ends in ${mmss(AutoWalk.END_MS - w.idleMs)}"
        else "walk: paused ${mmss(w.idleMs)}"
}

/** Everything on one screen: identity, lifetime steps, walk + privacy toggles, the live journey, the next unlock, links. */
@Composable
fun HomeScreen(
    onOpenAccount: () -> Unit,
    onOpenBadges: () -> Unit,
    onOpenJourneys: () -> Unit,
    onOpenAbout: () -> Unit,
    onOpenSocial: () -> Unit,
    onOpenStats: () -> Unit,
    onOpenBrag: () -> Unit,
    onOpenCredits: () -> Unit,
    vm: HomeViewModel = hiltViewModel(),
) {
    val steps by vm.lifetimeSteps.collectAsStateWithLifecycle()
    val todayKm by vm.todayKm.collectAsStateWithLifecycle()
    val weather by vm.weather.collectAsStateWithLifecycle()
    val weatherOn by vm.weatherOn.collectAsStateWithLifecycle()
    val points by vm.points.collectAsStateWithLifecycle()
    val tor by vm.torState.collectAsStateWithLifecycle()
    val torOn by vm.torEnabled.collectAsStateWithLifecycle()
    val flakeOn by vm.snowflakeOn.collectAsStateWithLifecycle()
    val handle by vm.handle.collectAsStateWithLifecycle()
    val clan by vm.clan.collectAsStateWithLifecycle()
    val avatar by vm.avatar.collectAsStateWithLifecycle()
    val walk by vm.walk.collectAsStateWithLifecycle()
    val route by vm.route.collectAsStateWithLifecycle()
    val badges by vm.badges.collectAsStateWithLifecycle()

    val violet = MaterialTheme.colorScheme.primary
    val green = MaterialTheme.colorScheme.secondary
    val muted = MaterialTheme.colorScheme.outline
    val dim = MaterialTheme.colorScheme.onSurfaceVariant

    // Hands-free walks need activity recognition; ask once, then register detection.
    val perms = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { vm.enableAutoWalk() }
    LaunchedEffect(Unit) {
        perms.launch(
            buildList {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) add(Manifest.permission.ACTIVITY_RECOGNITION)
                add(Manifest.permission.ACCESS_FINE_LOCATION)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
            }.toTypedArray()
        )
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.onForeground() }

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Image(painterResource(R.drawable.ic_logo), contentDescription = null, modifier = Modifier.size(32.dp))
            Text("VeilWalker", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.weight(1f))
            // Car-dashboard temperature: the snowflake means freezing, and freezing walks climb the Hidden Peaks.
            val w = weather
            when {
                !weatherOn -> Text("[ ] weather", color = muted, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.clickable { vm.enableWeather() })
                w == null -> Text("--\u00b0F", color = muted, style = MaterialTheme.typography.titleMedium)
                else -> Text(
                    (if (w.freezing) "\u2744 " else "") + "${w.tempF}\u00b0F",
                    color = if (w.freezing) Color(0xFF8FD3FF) else dim,
                    style = MaterialTheme.typography.titleMedium,
                )
            }
        }
        HorizontalDivider(thickness = 1.dp, color = violet)

        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            AvatarArt(avatar, size = 10.sp)
            Column {
                Text(
                    (clan?.let { "[$it] " } ?: "") + (handle ?: "no handle yet"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text("%,d".format(steps), style = MaterialTheme.typography.headlineMedium, color = violet)
                Text("lifetime steps · $points ${if (points == 1L) "pt" else "pts"} · %.1f km today".format(todayKm), color = dim, style = MaterialTheme.typography.bodySmall)
            }
        }

        Text(
            walkLine(walk),
            style = MaterialTheme.typography.bodyMedium,
            color = if (walk is WalkStatus.Idle) dim else green,
            modifier = Modifier.fillMaxWidth().clickable(enabled = walk is WalkStatus.Idle) { vm.startWalkNow() },
        )
        Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            Text(torLine(torOn, tor), style = MaterialTheme.typography.bodyMedium, color = if (torOn) green else muted, modifier = Modifier.clickable { vm.toggleTor() })
            if (vm.snowflakeReady) {
                Text(if (flakeOn) "(*) flake" else "[ ] flake", style = MaterialTheme.typography.bodyMedium, color = if (flakeOn) green else muted, modifier = Modifier.clickable { vm.toggleSnowflake() })
            } else {
                Text("[-] flake soon", style = MaterialTheme.typography.bodyMedium, color = muted)
            }
        }

        route?.let { RouteCard(it, compact = true, onOpen = onOpenJourneys) }

        val next = Journeys.locked.first()
        Text(
            "[#] next: ${next.title.uppercase()} · ${next.unlock}",
            color = muted,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.fillMaxWidth().clickable(onClick = onOpenJourneys),
        )

        // Two rows of links so nothing wraps on narrow phones.
        val link = { label: String, go: () -> Unit -> @Composable { Text(label, color = violet, modifier = Modifier.clickable(onClick = go).padding(vertical = 6.dp)) } }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            link("= journeys", onOpenJourneys)()
            link("& social", onOpenSocial)()
            link("~ stats", onOpenStats)()
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            link("+ ${badges ?: "badges"}", onOpenBadges)()
            link("^ brag", onOpenBrag)()
            link("@ account", onOpenAccount)()
        }

        // The spare space at the bottom: 3XC signature, taps through to About.
        Spacer(Modifier.weight(1f))
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
            ThreeXcFooter(Modifier.clickable(onClick = onOpenAbout))
            Text("> credits", color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.clickable(onClick = onOpenCredits).padding(8.dp))
        }
    }
}
