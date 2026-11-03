package org.trailbound.core.snowflake

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
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

    fun setHostOnWalks(on: Boolean) {
        prefs.edit().putBoolean("host_on_walks", on).apply()
        _hostOnWalks.value = on
    }

    fun start() {
        if (!engine.isAvailable) return
        if (bytesToday() >= DAILY_CAP) { _events.tryEmit(SnowflakeEvent.HardCapReached); return }
        walkCapBytes = SOFT_CAP; softCapAsked = false
        startBytes = engine.bytesRelayed(); startMs = System.currentTimeMillis()
        engine.start(capacity = if (isMetered()) 2 else 5)
        monitor = scope.launch {
            while (isActive) {
                delay(5_000)
                val walkBytes = engine.bytesRelayed() - startBytes
                val minutes = ((System.currentTimeMillis() - startMs) / 60_000).toInt()
                _events.tryEmit(SnowflakeEvent.Progress(walkBytes, minutes))
                val dayTotal = bytesTodayExcludingThisWalk() + walkBytes
                when {
                    dayTotal >= DAILY_CAP || walkBytes >= HARD_CAP -> {
                        _events.tryEmit(SnowflakeEvent.HardCapReached); stop()
                    }
                    walkBytes >= walkCapBytes && !softCapAsked -> {
                        softCapAsked = true
                        engine.pause()
                        _events.tryEmit(SnowflakeEvent.SoftCapReached)
                    }
                }
            }
        }
    }

    /** User tapped "Walk to 150 MB". */
    fun extendWalkCap() {
        walkCapBytes = HARD_CAP
        engine.resume()
    }

    fun stop() {
        monitor?.cancel(); monitor = null
        if (startMs != 0L) {
            addToToday(engine.bytesRelayed() - startBytes)
            startMs = 0L
        }
        engine.stop()
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
        prefs.edit().putString("day", today()).putLong("bytes", bytesToday() + b).apply()
    }

    companion object {
        const val SOFT_CAP = 50L * 1024 * 1024
        const val HARD_CAP = 150L * 1024 * 1024
        const val DAILY_CAP = 500L * 1024 * 1024
    }
}
