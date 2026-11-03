package org.trailbound.app.ui

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.animation.core.animateIntAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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

/** `(%) tor · onion ok` when on, `[x] tor off` when off. Short, so the Tor cell is never cut off. Tapping toggles. */
internal fun torLine(on: Boolean, t: TorState): String = if (!on) "[x] tor off" else "(%) tor · " + when (t) {
    TorState.Off, TorState.Bootstrapping -> "connecting\u2026"
    is TorState.Ready -> when (t.onionReachable) { true -> "onion ok"; null -> "checking\u2026"; false -> "retrying" }
    is TorState.Failed -> "waiting"
}

internal fun mmss(ms: Long) = "%d:%02d".format(ms / 60_000, ms / 1000 % 60)

internal fun walkLine(w: WalkStatus): String = when (w) {
    WalkStatus.Idle -> "walk: auto · 27 s of steps needed"
    is WalkStatus.Confirming -> "walk: detecting… ${w.walkingForMs / 1000}/${AutoWalk.CONFIRM_MS / 1000} s"
    is WalkStatus.Walking -> "walk: ${mmss(System.currentTimeMillis() - w.startedMs)} · ${w.steps} steps" + if (!w.gps) " · no gps" else ""
    is WalkStatus.Paused -> if (w.idleMs >= AutoWalk.RED_LIGHT_MS) "walk: red light? ends in ${mmss(AutoWalk.END_MS - w.idleMs)}"
        else "walk: paused ${mmss(w.idleMs)}"
}

/**
 * Everything on one screen, no scroll: identity, the walk | Tor bar, the snowflake | wake bar, the live journey,
 * the next unlock, and a 3 x 2 grid of destinations down where thumbs reach. Mirrors iPhone's HomeView.swift.
 */
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
    onOpenSnowflake: () -> Unit,
    onOpenWake: () -> Unit,
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
    val look = LocalLook.current
    val switchLook = LocalSwitchLook.current

    val violet = VeilColors.violet
    val green = VeilColors.green
    val muted = VeilColors.muted
    val dim = VeilColors.dim
    val ice = VeilColors.ice
    val body = MaterialTheme.typography.bodyMedium.copy(fontSize = 13.sp)

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
        // 1. Header: the logo switches looks; weather on the right.
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Image(
                painterResource(R.drawable.ic_logo),
                contentDescription = "switch look, now ${look.title}",
                modifier = Modifier.size(32.dp).veilClick(onClick = switchLook),
            )
            Text("VeilWalker", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.weight(1f))
            val w = weather
            when {
                !weatherOn -> Text("[ ] weather", color = muted, style = body, modifier = Modifier.veilClick { vm.enableWeather() })
                w == null -> Text("--\u00b0F", color = muted, style = MaterialTheme.typography.titleMedium)
                else -> Text(
                    (if (w.freezing) "\u2744 " else "") + "${w.tempF}\u00b0F",
                    color = if (w.freezing) ice else dim,
                    style = MaterialTheme.typography.titleMedium,
                )
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(violet).shadow(4.dp, ambientColor = violet, spotColor = violet))

        // 2. Identity: the picture in its own pane, the numbers in the other.
        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(
                Modifier.width(92.dp).fillMaxHeight().veilPanel(outlined = true, padding = 10.dp).veilClick(onClick = onOpenAccount),
                contentAlignment = Alignment.Center,
            ) { AvatarArt(avatar, size = 10.sp) }
            Column(Modifier.weight(1f).fillMaxHeight().veilPanel(outlined = true, padding = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    (clan?.let { "[$it] " } ?: "") + (handle ?: "no handle yet"),
                    style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 1,
                )
                val shown by animateIntAsState(steps.toInt(), tween(600), label = "steps")
                Text("%,d".format(shown), style = MaterialTheme.typography.headlineMedium.glow(violet), fontWeight = FontWeight.SemiBold)
                Text(
                    "lifetime steps · $points ${if (points == 1L) "pt" else "pts"} · %.1f km today".format(todayKm),
                    color = dim, style = MaterialTheme.typography.bodySmall, maxLines = 1, softWrap = false,
                    modifier = Modifier.fillMaxWidth(), autoSize = TextAutoSize.StepBased(minFontSize = 9.sp, maxFontSize = 12.sp),
                )
            }
        }

        // 3. Walk | Tor: one bar, two cells. The Tor cell never truncates; the walk text gives way.
        Row(
            Modifier.fillMaxWidth().height(IntrinsicSize.Min).veilPanel(outlined = true, padding = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                walkLine(walk), color = if (walk is WalkStatus.Idle) dim else green, style = body, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).veilClick(enabled = walk is WalkStatus.Idle) { vm.startWalkNow() },
            )
            Box(Modifier.width(1.dp).fillMaxHeight().padding(vertical = 2.dp).background(violet.copy(alpha = 0.4f)))
            val ok = torOn && (tor as? TorState.Ready)?.onionReachable == true
            Text(
                torLine(torOn, tor), style = if (ok) body.glow(green) else body.copy(color = if (torOn) green else muted),
                maxLines = 1, softWrap = false, modifier = Modifier.veilClick { vm.toggleTor() },
            )
        }

        // 4. Snowflake | Wake mode, outlined in ice.
        Row(
            Modifier.fillMaxWidth().height(IntrinsicSize.Min).veilPanel(outlined = true, outline = ice.copy(alpha = 0.35f), padding = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(Modifier.weight(1f).veilClick(onClick = onOpenSnowflake), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(if (flakeOn && vm.snowflakeReady) "(*) snowflake" else "[ ] snowflake", style = body.glow(ice, 10f), maxLines = 1)
                Text("> learn", color = violet, style = body, maxLines = 1)
            }
            Box(Modifier.width(1.dp).fillMaxHeight().padding(vertical = 2.dp).background(ice.copy(alpha = 0.35f)))
            Text("(o) wake mode", style = body.glow(green, 10f), maxLines = 1, softWrap = false, modifier = Modifier.veilClick(onClick = onOpenWake))
        }

        // 5. The live journey and the next unlock.
        route?.let { RouteCard(it, compact = true, onOpen = onOpenJourneys) }
        val next = Journeys.locked.first()
        Text(
            "[#] next: ${next.title.uppercase()} · ${next.unlock}",
            color = muted, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth().veilClick(onClick = onOpenJourneys),
        )

        Spacer(Modifier.weight(1f))

        // 6. Six destinations, 3 x 2, with the 3XC signature peeking out above them (7).
        Box {
            Box(Modifier.offset(x = 2.dp, y = (-96).dp).clearAndSetSemantics {}) { ThreeXcArt(24.sp, violet.copy(alpha = 0.10f)) }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    HomeTile("=", "journeys", onOpenJourneys)
                    HomeTile("&", "social", onOpenSocial)
                    HomeTile("~", "stats", onOpenStats)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    HomeTile("+", "badges " + (badges?.substringBefore(" ·") ?: ""), onOpenBadges)
                    HomeTile("^", "brag", onOpenBrag)
                    HomeTile("@", "account", onOpenAccount)
                }
            }
        }

        // 8. The easter egg: tiny links most people only find by accident.
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End)) {
            val tiny = MaterialTheme.typography.labelSmall.copy(color = muted)
            Text("about", style = tiny, modifier = Modifier.veilClick(onClick = onOpenAbout).padding(vertical = 2.dp))
            Text("·", style = tiny)
            Text("credits", style = tiny, modifier = Modifier.veilClick(onClick = onOpenCredits).padding(vertical = 2.dp))
        }
    }
}

/** One home destination: a glowing glyph over its name, in a pane (outlined in Terminal, glass in Glass). */
@Composable
private fun RowScope.HomeTile(glyph: String, name: String, onClick: () -> Unit) {
    Column(
        Modifier.weight(1f).veilPanel(outlined = true, outline = VeilColors.violet.copy(alpha = 0.45f), padding = 8.dp)
            .veilClick(onClick = onClick).semantics { contentDescription = name },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(glyph, style = MaterialTheme.typography.titleLarge.glow(VeilColors.violet, 12f), fontWeight = FontWeight.SemiBold)
        Text(
            name, color = VeilColors.text, style = MaterialTheme.typography.bodySmall, maxLines = 1, softWrap = false,
            autoSize = TextAutoSize.StepBased(minFontSize = 8.sp, maxFontSize = 12.sp),
        )
    }
}
