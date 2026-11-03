package org.trailbound.core.snowflake

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton

sealed interface SnowflakeEvent {
    data class Progress(val bytes: Long, val minutes: Int) : SnowflakeEvent
    data object SoftCapReached : SnowflakeEvent   // 50 MB: ask "Walk to 150 MB?"
    data object HardCapReached : SnowflakeEvent   // 150 MB per walk, or 500 MB per day
}

/**
 * Snowflake volunteer proxy, run only during a Snowflake Walk (started and stopped by WalkService).
 * Rewards are status only (emblem frost tiers, badges), never points. See README "Play policy".
 */
@Singleton
class SnowflakeController @Inject constructor(
    @ApplicationContext private val context: Context,
    private val engine: SnowflakeEngine,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _events = MutableSharedFlow<SnowflakeEvent>(extraBufferCapacity = 8)
    val events: SharedFlow<SnowflakeEvent> = _events

    private var monitor: Job? = null
    private var walkCapBytes = SOFT_CAP
    private var softCapAsked = false
    private var startBytes = 0L
    private var startMs = 0L

    // Daily total, kept in memory and in prefs so the 500 MB/day cap survives across walks.
    private val prefs = context.getSharedPreferences("snowflake", Context.MODE_PRIVATE)

    private val _hostOnWalks = MutableStateFlow(prefs.getBoolean("host_on_walks", false))
    /** User opt-in: host a Snowflake proxy during every walk (off by default; it uses data). */
    val hostOnWalks: StateFlow<Boolean> = _hostOnWalks

    /** Whether the proxy engine is actually built into this app. */
    val isAvailable: Boolean get() = engine.isAvailable

    private val _running = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running

    /** The one public number: traffic shared through snowflake, all time. No peers, addresses or countries are kept. */
    private val _bytesShared = MutableStateFlow(prefs.getLong("bytes_total", 0))
    val bytesShared: StateFlow<Long> = _bytesShared

    /** The 50 MB prompt is open (Wake Mode shows it as a dialog as well as the walk notification). */
    private val _askToContinue = MutableStateFlow(false)
    val askToContinue: StateFlow<Boolean> = _askToContinue

    /** Stopped by a cap: "session" (150 MB, or the user said stop) or "today" (500 MB). */
    private val _cappedBy = MutableStateFlow<String?>(null)
    val cappedBy: StateFlow<String?> = _cappedBy

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError

    fun setHostOnWalks(on: Boolean) {
        prefs.edit().putBoolean("host_on_walks", on).apply()
        _hostOnWalks.value = on
    }

    fun start() {
        if (!engine.isAvailable || _running.value) return
        if (bytesToday() >= DAILY_CAP) { _cappedBy.value = "today"; _events.tryEmit(SnowflakeEvent.HardCapReached); return }
        walkCapBytes = SOFT_CAP; softCapAsked = false
        _askToContinue.value = false; _lastError.value = null
        if (_cappedBy.value == "session") _cappedBy.value = null
        startBytes = engine.bytesRelayed(); startMs = System.currentTimeMillis()
        val totalBefore = prefs.getLong("bytes_total", 0)
        engine.start(capacity = if (isMetered()) 2 else 5)
        _running.value = true
        monitor = scope.launch {
            while (isActive) {
                delay(5_000)
                engine.lastError?.let { e ->
                    Log.w(TAG, "snowflake stopped: $e")
                    _lastError.value = e.take(60); stop(); return@launch
                }
                val walkBytes = engine.bytesRelayed() - startBytes
                _bytesShared.value = totalBefore + walkBytes
                val minutes = ((System.currentTimeMillis() - startMs) / 60_000).toInt()
                _events.tryEmit(SnowflakeEvent.Progress(walkBytes, minutes))
                val dayTotal = bytesTodayExcludingThisWalk() + walkBytes
                when {
                    dayTotal >= DAILY_CAP -> { _cappedBy.value = "today"; _events.tryEmit(SnowflakeEvent.HardCapReached); stop() }
                    walkBytes >= HARD_CAP -> { _cappedBy.value = "session"; _events.tryEmit(SnowflakeEvent.HardCapReached); stop() }
                    walkBytes >= walkCapBytes && !softCapAsked -> {
                        softCapAsked = true
                        engine.pause()
                        _askToContinue.value = true
                        _events.tryEmit(SnowflakeEvent.SoftCapReached)
                    }
                }
            }
        }
    }

    /** User tapped "Walk to 150 MB" / "Keep going to 150 MB". */
    fun extendWalkCap() {
        walkCapBytes = HARD_CAP
        _askToContinue.value = false
        engine.resume()
    }

    /** User said stop at the 50 MB prompt: done for this walk. */
    fun declineSoftCap() {
        _askToContinue.value = false
        _cappedBy.value = "session"
        stop()
    }

    fun stop() {
        monitor?.cancel(); monitor = null
        if (startMs != 0L) {
            addToToday(engine.bytesRelayed() - startBytes)
            startMs = 0L
        }
        engine.stop()
        _running.value = false
    }

    /** The one-line status under the Wake Mode counter. */
    fun statusLine(): String = when {
        _lastError.value != null -> "[x] snowflake stopped: ${_lastError.value}"
        _cappedBy.value == "today" -> "[-] 500 MB shared today: resting until tomorrow"
        _cappedBy.value == "session" -> "[-] session cap reached · see you next run"
        _askToContinue.value -> "[?] 50 MB shared this run"
        _running.value -> "(*) hosting · only traffic shared is kept"
        else -> "[ ] hosts during your walks"
    }

    private fun isMetered(): Boolean {
        val cm = context.getSystemService(ConnectivityManager::class.java)
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return true
        return !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }

    private fun today() = LocalDate.now(ZoneId.systemDefault()).toString()
    private fun bytesToday(): Long = if (prefs.getString("day", null) == today()) prefs.getLong("bytes", 0) else 0
    private fun bytesTodayExcludingThisWalk() = bytesToday()
    private fun addToToday(b: Long) {
        val total = prefs.getLong("bytes_total", 0) + b
        prefs.edit().putString("day", today()).putLong("bytes", bytesToday() + b).putLong("bytes_total", total).apply()
        _bytesShared.value = total
    }

    companion object {
        private const val TAG = "VeilWalker/Snowflake"
        // Decimal megabytes, as the UI says "MB" (and as on iPhone).
        const val SOFT_CAP = 50_000_000L
        const val HARD_CAP = 150_000_000L
        const val DAILY_CAP = 500_000_000L

        /** 0 B, 512 KB, 41.2 MB, 1.30 GB. */
        fun format(b: Long): String = when {
            b >= 1_000_000_000 -> "%.2f GB".format(java.util.Locale.US, b / 1e9)
            b >= 1_000_000 -> "%.1f MB".format(java.util.Locale.US, b / 1e6)
            b >= 1_000 -> "%.0f KB".format(java.util.Locale.US, b / 1e3)
            else -> "$b B"
        }
    }
}
