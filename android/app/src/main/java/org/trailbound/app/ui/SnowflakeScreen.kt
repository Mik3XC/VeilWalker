package org.trailbound.app.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import org.trailbound.core.achievements.AchievementRepository
import org.trailbound.core.achievements.BadgeBoard
import org.trailbound.core.achievements.Frost
import org.trailbound.core.snowflake.SnowflakeController
import org.trailbound.core.steps.WalkService
import javax.inject.Inject

/** Snowflake hosting state for the Snowflake page and Wake Mode. Hosting rides on walks, as it always has on Android. */
@HiltViewModel
class SnowflakeViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    val flake: SnowflakeController,
    achievements: AchievementRepository,
) : ViewModel() {
    val board: StateFlow<BadgeBoard?> = achievements.board.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
    private val prefs = context.getSharedPreferences("snowflake", Context.MODE_PRIVATE)

    /** Whether the first-time explanation has been shown (the iPhone's snowflakeHostExplained). */
    var explained: Boolean
        get() = prefs.getBoolean("host_explained", false)
        set(v) = prefs.edit().putBoolean("host_explained", v).apply()

    /** Opt in or out of hosting on walks; a walk that's already running starts or stops hosting now. */
    fun setHosting(on: Boolean) {
        flake.setHostOnWalks(on)
        if (!WalkService.isRunning) return
        context.startService(if (on) WalkService.snowflakeStartIntent(context) else WalkService.snowflakeStopIntent(context))
    }
}

/**
 * The wall breaker: a censored user's packets bounce off the wall, volunteers' snowflakes light up on the far side,
 * and the wall cracks open so traffic flows through them to Tor. One string per frame, redrawn 8 times a second.
 * A 1:1 port of iPhone's `WallBreaker.frame(t)`.
 */
object WallBreaker {
    const val CYCLE_S = 12.0

    data class Frame(val art: String, val caption: String, val through: Boolean)

    /** One frame: 9 rows x 34 columns. The user at left, the wall at column 11, snowflakes beyond, Tor at right. */
    fun frame(t: Double): Frame {
        val rows = 9; val cols = 34; val wall = 11; val mid = 4
        val g = Array(rows) { CharArray(cols) { ' ' } }
        fun render() = g.joinToString("\n") { String(it) }
        fun put(r: Int, c: Int, s: String) { s.forEachIndexed { i, ch -> if (c + i in 0 until cols) g[r][c + i] = ch } }
        put(mid, 0, "(@)")
        put(mid - 2, 0, "you")
        put(mid, 31, "(%)")
        put(mid - 2, 31, "tor")

        // Snowflakes beyond the wall: they light up one by one from 3 s.
        val flakes = listOf(1 to 16, 6 to 15, 3 to 20, 7 to 22, 2 to 25, 5 to 27, mid to 21)
        val lit = if (t < 3) 0 else minOf(flakes.size, ((t - 3) / 0.45).toInt() + 1)
        flakes.take(lit).forEach { (r, c) -> put(r, c, "*") }

        // The wall: whole until 6 s, then it cracks open around the middle row.
        val crack = if (t < 6) -1 else minOf(3, ((t - 6) / 0.6).toInt())
        for (r in 0 until rows) {
            val open = crack >= 0 && kotlin.math.abs(r - mid) <= crack - 1
            val cracking = crack >= 0 && kotlin.math.abs(r - mid) == crack
            put(r, wall, if (open) " " else if (cracking) (if (r < mid) "/" else if (r > mid) "\\" else ":") else "#")
        }
        put(rows - 1, wall - 3, "censor")

        if (t < 3) {
            // Straight at the wall, and blocked.
            val x = 4 + (t * 6).toInt() % 7
            if (x >= wall - 1) put(mid, wall - 1, "x") else put(mid, x, ">")
            return Frame(render(), "the direct path is blocked", false)
        }
        if (t < 6) {
            put(mid, 4, "> > >x")
            return Frame(render(), "volunteers light up snowflakes", false)
        }
        // Through the gap, via a snowflake, to Tor.
        for (c in 4 until 31) if (g[mid][c] == ' ') g[mid][c] = '.'
        val p = 4 + ((t - 6) * 9).toInt() % 27
        for (k in listOf(p, p - 9, p - 18)) if (k in 4 until 31 && g[mid][k] == '.') g[mid][k] = '>'
        return Frame(render(), if (crack >= 1) "traffic slips through, still encrypted by Tor" else "the wall starts to crack", crack >= 1)
    }
}

@Composable
fun WallBreakerView(modifier: Modifier = Modifier) {
    val still = animationsOff()
    var t by remember { mutableDoubleStateOf(10.0) }
    if (!still) LaunchedEffect(Unit) {
        val start = System.currentTimeMillis()
        while (true) { t = ((System.currentTimeMillis() - start) / 1000.0) % WallBreaker.CYCLE_S; delay(125) }
    }
    val f = WallBreaker.frame(t)
    Column(
        modifier.clearAndSetSemantics {
            contentDescription = "Animation: a blocked user's traffic hits a wall, volunteer snowflakes appear behind it, and the wall breaks so the traffic reaches Tor through them."
        },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(f.art, color = VeilColors.green, fontFamily = FontFamily.Monospace, fontSize = 13.sp, lineHeight = 17.sp, softWrap = false)
        Text(f.caption, color = if (f.through) VeilColors.green else VeilColors.dim, style = MaterialTheme.typography.bodySmall)
    }
}

/** What Snowflake is, why it helps, and where VeilWalker fits. Mirrors iPhone's SnowflakeView, adapted for Android. */
@Composable
fun SnowflakeScreen(onBack: () -> Unit, vm: SnowflakeViewModel = hiltViewModel()) {
    val ctx = LocalContext.current
    val hostOn by vm.flake.hostOnWalks.collectAsStateWithLifecycle()
    val running by vm.flake.running.collectAsStateWithLifecycle()
    val shared by vm.flake.bytesShared.collectAsStateWithLifecycle()
    val board by vm.board.collectAsStateWithLifecycle()
    var explain by remember { androidx.compose.runtime.mutableStateOf(false) }
    val dim = VeilColors.dim
    val body = MaterialTheme.typography.bodyMedium

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("Snowflake", style = MaterialTheme.typography.headlineMedium)
        Text("Breaking walls, one volunteer at a time.", color = dim)

        // Status up front, with the switch right there.
        Column(Modifier.veilPanel(outlined = true, outline = VeilColors.ice.copy(alpha = 0.5f)), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("(*) ON ANDROID: HOSTS DURING YOUR WALKS", color = VeilColors.ice, fontWeight = FontWeight.Bold)
            HostButton(hostOn, running, vm.flake.statusLine(), "help people past censorship while you walk") {
                when { hostOn -> vm.setHosting(false); vm.explained -> vm.setHosting(true); else -> explain = true }
            }
            Text("Shared so far: ${SnowflakeController.format(shared)}", color = dim, style = MaterialTheme.typography.bodySmall)
        }

        WallBreakerView(Modifier.veilPanel(outlined = true, outline = VeilColors.green.copy(alpha = 0.5f)))

        Section("what is snowflake")
        Text("In some countries the network is walled off: Tor's known entry points are blocked, so people there can't reach it. Snowflake is a Tor Project tool that gets around the wall. Volunteers around the world run a tiny proxy, a \"snowflake\", and a blocked user's Tor connection hops through one of them on its way in.", color = dim, style = body)
        Section("why the wall can't keep up")
        Text("Snowflakes are many, short-lived and constantly changing, and their traffic looks like an ordinary video call. A censor would have to block thousands of everyday addresses that keep moving, which breaks things people rely on. Melt one and another falls.", color = dim, style = body)
        Section("is it safe to run one")
        Text("A snowflake only passes along traffic that's already encrypted by Tor. It can't read it, and it isn't an exit: websites never see your address. It uses a little bandwidth while it's on.", color = dim, style = body)
        Section("snowflake in veilwalker")
        Text("Hosting a snowflake while you walk earns frost on every badge frame: FROST at 10 minutes, then ICE, GLACIER and AURORA at 5,000. Status only, never points, so nobody's helping for the wrong reasons. Data stays capped: a prompt at 50 MB and never more than 500 MB a day.", color = dim, style = body)
        board?.let { b ->
            Text("Frost now: ${b.frost.title} · ${b.snowflakeMinutes} min hosted", color = if (b.frost == Frost.NONE) VeilColors.muted else VeilColors.ice, style = body)
        }
        Text("On iPhone, Snowflake hosts only in wake mode; Apple doesn't allow a proxy in the background.", color = dim, style = body)
        Text("It's the Tor Project's own Snowflake code, forwarding only to the Tor Project's relays. Not at your phone? A browser tab or extension helps too.", color = dim, style = body)
        VeilButton("Run a snowflake in your browser", { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://snowflake.torproject.org/"))) }, glyph = "*", filled = true)
        Text("snowflake.torproject.org · made by the Tor Project, not by VeilWalker", color = VeilColors.muted, style = MaterialTheme.typography.bodySmall)
        VeilButton("Back", onBack, glyph = "<")
    }
    if (explain) HostExplainDialog(onHost = { explain = false; vm.explained = true; vm.setHosting(true) }, onDismiss = { explain = false })
}

@Composable
private fun Section(text: String) = Text("// $text", color = VeilColors.green, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))

/**
 * The big hosting switch (the first iPhone version was a thin line people missed). Off: `[ ] HOST A SNOWFLAKE`;
 * on: `(*) HOSTING A SNOWFLAKE` in green while it relays, `(*) HOSTING ON WALKS` in ice between walks.
 */
@Composable
fun HostButton(on: Boolean, running: Boolean, status: String, offLine: String, panel: Modifier = Modifier, onClick: () -> Unit) {
    val accent = if (running) VeilColors.green else VeilColors.ice
    Column(
        panel.fillMaxWidth().veilClick(onClick = onClick).padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            when { !on -> "[ ] HOST A SNOWFLAKE"; running -> "(*) HOSTING A SNOWFLAKE"; else -> "(*) HOSTING ON WALKS" },
            style = MaterialTheme.typography.bodyLarge.glow(accent, 12f), fontWeight = FontWeight.Bold, letterSpacing = 1.sp,
        )
        Text(if (on) status else offLine, color = VeilColors.dim, style = MaterialTheme.typography.labelSmall, maxLines = 2)
    }
}

/** First tap ever on the host switch: what hosting means, before it's on. */
@Composable
fun HostExplainDialog(onHost: () -> Unit, onDismiss: () -> Unit) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Host a snowflake?") },
        text = {
            Text("While you walk, your phone relays already-encrypted Tor traffic for people in censored countries. They can see your phone's IP address, as with any snowflake, but not what you do; you can't see what they do either. It uses data (capped at 500 MB a day) and stops when your walk ends. Only the amount shared is kept.")
        },
        confirmButton = { VeilButton("Host", onHost, glyph = "*", filled = true, modifier = Modifier.padding(horizontal = 8.dp)) },
        dismissButton = { VeilButton("Not now", onDismiss, glyph = "<", modifier = Modifier.padding(horizontal = 8.dp)) },
        containerColor = VeilColors.surface,
    )
}
