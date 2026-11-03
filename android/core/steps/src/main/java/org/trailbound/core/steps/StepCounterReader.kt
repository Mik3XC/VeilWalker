package org.trailbound.core.steps

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.provider.Settings
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import org.trailbound.core.data.dao.StepDao
import org.trailbound.core.data.entity.CounterBaseline
import org.trailbound.core.data.entity.StepInterval
import org.trailbound.core.data.entity.StepSource
import java.time.Instant
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

/**
 * Reads TYPE_STEP_COUNTER, the hardware counter that keeps counting while the app is dead, and turns
 * raw readings into deltas. Handles the reboot reset to 0 via Settings.Global.BOOT_COUNT.
 */
@Singleton
class StepCounterReader @Inject constructor(
    @ApplicationContext private val context: Context,
    private val dao: StepDao,
) {
    private val sensorManager = context.getSystemService(SensorManager::class.java)
    private val counter: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

    val isAvailable: Boolean get() = counter != null

    // The walk service and the passive worker both read the counter; without this, two reads racing on the
    // same baseline would each record the same steps.
    private val lock = Mutex()

    /** One-shot read of the current raw counter value. Null if there's no sensor, no permission, or a timeout. */
    suspend fun readRaw(): Long? {
        val sensor = counter ?: return null
        return withTimeoutOrNull(5_000) {
            suspendCancellableCoroutine { cont ->
                val listener = object : SensorEventListener {
                    override fun onSensorChanged(e: SensorEvent) {
                        sensorManager.unregisterListener(this)
                        if (cont.isActive) cont.resume(e.values[0].toLong())
                    }
                    override fun onAccuracyChanged(s: Sensor?, a: Int) = Unit
                }
                sensorManager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)
                cont.invokeOnCancellation { sensorManager.unregisterListener(listener) }
            }
        }
    }

    /**
     * Records the steps taken since the last reading as one interval.
     * Returns the delta (0 on first run or right after a reboot with no steps yet).
     */
    suspend fun recordDelta(source: StepSource, walkId: Long? = null): Long = lock.withLock {
        val raw = readRaw() ?: return 0
        val now = System.currentTimeMillis()
        val boot = bootCount()
        val prev = dao.baseline()

        val delta = when {
            prev == null -> 0L                                   // first run: just set the baseline
            prev.bootCount != boot || raw < prev.lastRawValue -> raw  // rebooted: counter restarted at 0
            else -> raw - prev.lastRawValue
        }
        dao.saveBaseline(CounterBaseline(bootCount = boot, lastRawValue = raw, lastReadEpochMs = now))

        if (delta > 0 && prev != null) {
            for ((day, start, end, steps) in splitAtMidnight(prev.lastReadEpochMs, now, delta)) {
                dao.insertInterval(StepInterval(day = day, startEpochMs = start, endEpochMs = end, steps = steps, source = source, walkId = walkId))
            }
        }
        return delta
    }

    private data class Piece(val day: String, val start: Long, val end: Long, val steps: Long)

    /**
     * An interval that spans midnight (the phone slept, so no reading at 00:00) is split across the days it
     * covers in proportion to time, so last night's steps don't land on today. The counter can't say exactly
     * when each step happened; time-proportional is the closest honest guess.
     */
    private fun splitAtMidnight(start: Long, end: Long, steps: Long): List<Piece> {
        val zone = ZoneId.systemDefault()
        val cuts = mutableListOf(start)
        var d = Instant.ofEpochMilli(start).atZone(zone).toLocalDate().plusDays(1)
        while (true) {
            val m = d.atStartOfDay(zone).toInstant().toEpochMilli()
            if (m >= end) break
            cuts += m; d = d.plusDays(1)
        }
        cuts += end
        val span = (end - start).coerceAtLeast(1)
        var left = steps
        return cuts.zipWithNext().mapIndexed { i, (a, b) ->
            val n = if (i == cuts.size - 2) left else steps * (b - a) / span
            left -= n
            Piece(Instant.ofEpochMilli(a).atZone(zone).toLocalDate().toString(), a, b, n)
        }.filter { it.steps > 0 }
    }

    private fun bootCount(): Int =
        Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
}
