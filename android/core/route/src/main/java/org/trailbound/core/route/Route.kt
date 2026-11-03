package org.trailbound.core.route

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

data class LatLng(val lat: Double, val lng: Double)

/** A place on the route. [postcard] unlocks when the walker's virtual position reaches it. */
data class Milestone(val name: String, val point: LatLng, val postcard: String)

/**
 * A virtual route: a polyline through its milestones. Positions are computed by distance along the line,
 * so progress needs nothing but a distance in metres: no GPS, no map tiles, nothing leaves the phone.
 */
class Route(val id: String, val title: String, val subtitle: String, val milestones: List<Milestone>) {

    private val points = milestones.map { it.point }

    /** Cumulative distance (m) at each milestone; the last value is the route length. */
    val cumulativeM: DoubleArray = DoubleArray(points.size).also { c ->
        for (i in 1 until points.size) c[i] = c[i - 1] + haversineM(points[i - 1], points[i])
    }

    val lengthM: Double get() = cumulativeM.last()

    data class Position(
        val point: LatLng,
        val travelledM: Double,
        val unlocked: List<Milestone>,
        val next: Milestone?,
        val toNextM: Double?,
        val finished: Boolean,
    )

    fun positionAt(distanceM: Double): Position {
        val d = distanceM.coerceIn(0.0, lengthM)
        // Index of the last milestone at or before d (binary search on the cumulative distances).
        var lo = 0
        var hi = cumulativeM.size - 1
        while (lo < hi) {
            val mid = (lo + hi + 1) / 2
            if (cumulativeM[mid] <= d) lo = mid else hi = mid - 1
        }
        val point = if (lo == points.size - 1) points.last() else {
            val segLen = cumulativeM[lo + 1] - cumulativeM[lo]
            val t = if (segLen == 0.0) 0.0 else (d - cumulativeM[lo]) / segLen
            LatLng(points[lo].lat + t * (points[lo + 1].lat - points[lo].lat), points[lo].lng + t * (points[lo + 1].lng - points[lo].lng))
        }
        val next = milestones.getOrNull(lo + 1)
        return Position(
            point = point,
            travelledM = d,
            unlocked = milestones.take(lo + 1),
            next = next,
            toNextM = next?.let { cumulativeM[lo + 1] - d },
            finished = d >= lengthM,
        )
    }

    companion object {
        fun haversineM(a: LatLng, b: LatLng): Double {
            val r = 6_371_000.0
            val dLat = Math.toRadians(b.lat - a.lat)
            val dLng = Math.toRadians(b.lng - a.lng)
            val h = sin(dLat / 2) * sin(dLat / 2) +
                cos(Math.toRadians(a.lat)) * cos(Math.toRadians(b.lat)) * sin(dLng / 2) * sin(dLng / 2)
            return 2 * r * atan2(sqrt(h), sqrt(1 - h))
        }
    }
}
