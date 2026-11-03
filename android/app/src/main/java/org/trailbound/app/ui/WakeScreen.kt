package org.trailbound.app.ui

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import org.trailbound.app.R
import org.trailbound.core.snowflake.SnowflakeController
import org.trailbound.core.steps.WalkStatus

/**
 * Runners Wake Mode, for a phone in an arm band: the screen stays on, a walk starts if none is running, everything
 * is big enough to read mid-stride, and exit is a 1-second hold so a sweaty arm can't end it. Mirrors WakeView.swift.
 * On Android, Snowflake hosting rides on the walk (it doesn't stop when this screen closes).
 */
@Composable
fun WakeScreen(onExit: () -> Unit, home: HomeViewModel = hiltViewModel(), sf: SnowflakeViewModel = hiltViewModel()) {
    val look = LocalLook.current
    val glass = look == Look.GLASS
    val walk by home.walk.collectAsStateWithLifecycle()
    val steps by home.todaySteps.collectAsStateWithLifecycle()
    val km by home.todayKm.collectAsStateWithLifecycle()
    val tor by home.torState.collectAsStateWithLifecycle()
    val torOn by home.torEnabled.collectAsStateWithLifecycle()
    val hostOn by sf.flake.hostOnWalks.collectAsStateWithLifecycle()
    val running by sf.flake.running.collectAsStateWithLifecycle()
    val shared by sf.flake.bytesShared.collectAsStateWithLifecycle()
    val ask by sf.flake.askToContinue.collectAsStateWithLifecycle()
    var explain by remember { mutableStateOf(false) }
    var holding by remember { mutableStateOf(false) }

    // Screen on, system bars out of the way (a swipe brings them back briefly), back consumed.
    val view = LocalView.current
    DisposableEffect(Unit) {
        val window = (view.context as Activity).window
        val bars = WindowCompat.getInsetsController(window, view)
        view.keepScreenOn = true
        bars.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        bars.hide(WindowInsetsCompat.Type.systemBars())
        onDispose {
            view.keepScreenOn = false
            bars.show(WindowInsetsCompat.Type.systemBars())
        }
    }
    BackHandler { }
    LaunchedEffect(Unit) { if (walk is WalkStatus.Idle) home.startWalkNow() }

    // The walk clock ticks once a second.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(1_000) } }
    val clock = when (val w = walk) {
        is WalkStatus.Walking -> mmss(now - w.startedMs)
        is WalkStatus.Paused -> mmss(now - w.startedMs)
        else -> "0:00"
    }

    Box(Modifier.fillMaxSize().background(VeilColors.background)) {
        // The runner, anchored to the bottom so it stays in view on any screen shape.
        Image(
            painterResource(if (glass) R.drawable.wake_glass else R.drawable.wake_terminal), contentDescription = null,
            contentScale = ContentScale.Crop, alignment = Alignment.BottomCenter, modifier = Modifier.fillMaxSize(),
        )
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("WAKE MODE", style = MaterialTheme.typography.labelSmall.glow(VeilColors.green, 12f), fontWeight = FontWeight.Bold, letterSpacing = 3.sp)
                Spacer(Modifier.weight(1f))
                Text(torLine(torOn, tor), color = if (torOn) VeilColors.green else VeilColors.muted, style = MaterialTheme.typography.labelSmall, maxLines = 1)
            }

            // The walk: the one number a runner glances at, huge.
            Column(Modifier.wakePane(glass, VeilColors.violet.copy(alpha = 0.4f), 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    clock, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, maxLines = 1,
                    style = MaterialTheme.typography.displayLarge.glow(VeilColors.violet, 28f),
                    autoSize = TextAutoSize.StepBased(minFontSize = 32.sp, maxFontSize = 64.sp),
                )
                Text(walkLine(walk), color = VeilColors.dim, style = MaterialTheme.typography.bodySmall, maxLines = 1)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Stat("%,d".format(steps), "steps", glass)
                Stat("%.2f".format(km), "km", glass)
                Stat(SnowflakeController.format(shared), "shared", glass, VeilColors.ice)
            }

            HostButton(
                on = hostOn, running = running, status = sf.flake.statusLine(), offLine = "help people past censorship while you walk",
                panel = Modifier.wakePane(glass, (if (running) VeilColors.green else VeilColors.ice).copy(alpha = 0.6f), 0.dp),
            ) {
                when { hostOn -> sf.setHosting(false); sf.explained -> sf.setHosting(true); else -> explain = true }
            }

            Spacer(Modifier.weight(1f))

            // Hold to exit: an accidental brush can't end the session.
            Text(
                if (holding) "keep holding…" else "hold to exit",
                color = if (holding) VeilColors.green else VeilColors.violet, style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.wakePane(glass, VeilColors.violet.copy(alpha = 0.5f), 0.dp).padding(vertical = 14.dp).fillMaxWidth()
                    .semantics { customActions = listOf(CustomAccessibilityAction("Exit wake mode") { onExit(); true }) }
                    .pointerInput(Unit) {
                        detectTapGestures(onPress = {
                            holding = true
                            val released = withTimeoutOrNull(1_000) { tryAwaitRelease() }
                            holding = false
                            if (released == null) { view.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS); onExit() }
                        })
                    },
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }

    if (explain) HostExplainDialog(onHost = { explain = false; sf.explained = true; sf.setHosting(true) }, onDismiss = { explain = false })
    if (ask) androidx.compose.material3.AlertDialog(
        onDismissRequest = {},
        title = { Text("50 MB shared this run") },
        text = { Text("Keep helping people reach Tor on this run, up to 150 MB?") },
        confirmButton = { VeilButton("Keep going to 150 MB", { sf.flake.extendWalkCap() }, glyph = "*", filled = true) },
        dismissButton = { VeilButton("Stop hosting", { sf.flake.declineSoftCap() }, glyph = "x") },
        containerColor = VeilColors.surface,
    )
}

@Composable
private fun RowScope.Stat(value: String, label: String, glass: Boolean, color: Color = VeilColors.text) {
    Column(Modifier.weight(1f).wakePane(glass, VeilColors.muted, 10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            value, color = color, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, maxLines = 1,
            autoSize = TextAutoSize.StepBased(minFontSize = 11.sp, maxFontSize = 22.sp),
        )
        Text(label, color = VeilColors.dim, style = MaterialTheme.typography.bodySmall)
    }
}

/** A pane over the art: see-through black with an outline in Terminal, a glass panel in Glass. */
@Composable
private fun Modifier.wakePane(glass: Boolean, outline: Color, padding: Dp): Modifier =
    if (glass) veilPanel(outlined = true, outline = outline, padding = padding)
    else fillMaxWidth().background(Color.Black.copy(alpha = 0.45f)).border(1.dp, outline, RectangleShape).padding(padding)
