package org.trailbound.core.anticheat

import kotlin.math.abs
import kotlin.math.sqrt

/** One 10 s analysis window built from raw sensor callbacks during an active walk. */
data class SensorWindow(
    val steps: Int,
    val durationS: Double,
    val accelMagnitudes: FloatArray,   // |a| samples, m/s^2
    val gyroX: FloatArray,
    val gyroY: FloatArray,
    val gyroZ: FloatArray,
)

data class WindowVerdict(val score: Float, val flags: Set<Flag>)

enum class Flag { CADENCE_OUT_OF_BAND, CADENCE_TOO_REGULAR, LOW_ACCEL_VARIANCE, SINGLE_AXIS_ROTATION, VEHICLE_SPEED, MOCK_LOCATION }

/**
 * On-device walk verification. Only the resulting verdict leaves the phone.
 * Thresholds are starting points. Tune them against real walks (S26 Edge first, then low-end devices).
 */
class WalkVerifier {

    private val recentCadences = ArrayDeque<Double>()

    fun score(w: SensorWindow, gps: GpsCheck?): WindowVerdict {
        val flags = mutableSetOf<Flag>()
        var score = 1f

        // 1. Cadence: humans walk at ~1.4–2.6 steps/s and vary window to window. Rigs are too steady.
        val cadence = if (w.durationS > 0) w.steps / w.durationS else 0.0
        // Only too-fast cadence is suspicious: shakers inflate steps. Slow windows (crossings, stopping, strolling)
        // are normal. The S26 Edge 10-min test walk had four 0.8–1.1 steps/s windows, all real.
        if (w.steps >= MIN_STEPS_FOR_CADENCE && cadence > MAX_CADENCE) { flags += Flag.CADENCE_OUT_OF_BAND; score -= 0.4f }
        recentCadences.addLast(cadence)
        if (recentCadences.size > 12) recentCadences.removeFirst()
        if (recentCadences.size >= 6 && stdDev(recentCadences.toDoubleArray()) < 0.015) {
            flags += Flag.CADENCE_TOO_REGULAR; score -= 0.3f
        }

        // 2. Accelerometer: real heel strikes give vertical variance; a gently shaken phone does not.
        if (w.accelMagnitudes.size > 10 && variance(w.accelMagnitudes) < 0.25f) {
            flags += Flag.LOW_ACCEL_VARIANCE; score -= 0.3f
        }

        // 3. Gyro: pendulum/swing rigs rotate around one dominant axis; pocket/hand carry is messy.
        val ex = energy(w.gyroX); val ey = energy(w.gyroY); val ez = energy(w.gyroZ)
        val total = ex + ey + ez
        if (total > 0.05f && maxOf(ex, ey, ez) / total > 0.92f) {
            flags += Flag.SINGLE_AXIS_ROTATION; score -= 0.35f
        }

        // 4. GPS is a veto signal only. Dead zones and rural gaps are never penalised.
        gps?.let {
            if (it.isMock) { flags += Flag.MOCK_LOCATION; score -= 1f }
            if (it.speedKmh != null && it.speedKmh > 9.0 && cadence in 1.2..3.2) {
                flags += Flag.VEHICLE_SPEED; score -= 0.6f
            }
        }

        return WindowVerdict(score.coerceIn(0f, 1f), flags)
    }

    private companion object {
        const val MIN_STEPS_FOR_CADENCE = 8
        const val MAX_CADENCE = 3.2 // steps/s; brisk walking is ~2.0, running tops out near 3
    }

    private fun variance(a: FloatArray): Float {
        val m = a.average().toFloat()
        return a.fold(0f) { acc, v -> acc + (v - m) * (v - m) } / a.size
    }

    private fun stdDev(a: DoubleArray): Double {
        val m = a.average()
        return sqrt(a.sumOf { (it - m) * (it - m) } / a.size)
    }

    private fun energy(a: FloatArray): Float = a.fold(0f) { acc, v -> acc + abs(v) }
}

/** Result of the smoothed GPS check for a window; null speed means "no trustworthy fix" (dead zone). */
data class GpsCheck(val speedKmh: Double?, val isMock: Boolean)
