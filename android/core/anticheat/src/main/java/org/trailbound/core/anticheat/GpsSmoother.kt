package org.trailbound.core.anticheat

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

data class Fix(val epochMs: Long, val lat: Double, val lon: Double, val accuracyM: Float, val isMock: Boolean)

/**
 * Handles ±10 m jitter, rural sparsity and dead zones:
 * - drops fixes worse than [maxAccuracyM]
 * - smooths position with a 1-D Kalman per axis, weighted by reported accuracy
 * - reports speed over a [windowMs] span instead of fix-to-fix, so jitter can't fake (or hide) speed
 * - returns speedKmh = null when there aren't enough good fixes. Callers treat that as sensor-only, not as cheating.
 */
class GpsSmoother(
    private val maxAccuracyM: Float = 25f,
    private val windowMs: Long = 30_000,
    private val processNoiseMps: Double = 3.0,
) {
    private data class Smoothed(val epochMs: Long, val lat: Double, val lon: Double)

    private val history = ArrayDeque<Smoothed>()
    private var lat = 0.0
    private var lon = 0.0
    private var varianceM2 = -1.0
    private var lastMs = 0L
    private var sawMock = false

    var totalDistanceM = 0.0
        private set

    fun add(f: Fix) {
        if (f.isMock) sawMock = true
        if (f.accuracyM > maxAccuracyM) return

        val acc2 = (f.accuracyM * f.accuracyM).toDouble()
        if (varianceM2 < 0) {
            lat = f.lat; lon = f.lon; varianceM2 = acc2; lastMs = f.epochMs
        } else {
            val dt = (f.epochMs - lastMs).coerceAtLeast(0) / 1000.0
            varianceM2 += dt * processNoiseMps * processNoiseMps
            val k = varianceM2 / (varianceM2 + acc2)
            val prev = history.lastOrNull()
            lat += k * (f.lat - lat)
            lon += k * (f.lon - lon)
            varianceM2 *= (1 - k)
            lastMs = f.epochMs
            if (prev != null) totalDistanceM += haversineM(prev.lat, prev.lon, lat, lon)
        }
        history.addLast(Smoothed(f.epochMs, lat, lon))
        while (history.size > 2 && f.epochMs - history.first().epochMs > windowMs * 2) history.removeFirst()
    }

    fun check(nowMs: Long): GpsCheck {
        val recent = history.filter { nowMs - it.epochMs <= windowMs }
        if (recent.size < 3) return GpsCheck(null, sawMock)
        val first = recent.first(); val last = recent.last()
        val dtS = (last.epochMs - first.epochMs) / 1000.0
        if (dtS < 10) return GpsCheck(null, sawMock)
        val d = haversineM(first.lat, first.lon, last.lat, last.lon)
        return GpsCheck(d / dtS * 3.6, sawMock)
    }

    companion object {
        fun haversineM(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
            val r = 6_371_000.0
            val dLat = Math.toRadians(lat2 - lat1)
            val dLon = Math.toRadians(lon2 - lon1)
            val a = sin(dLat / 2) * sin(dLat / 2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2)
            return 2 * r * atan2(sqrt(a), sqrt(1 - a))
        }
    }
}
