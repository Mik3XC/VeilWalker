package org.trailbound.core.steps

/**
 * GPS drift indoors, or a ride, can add distance no feet covered. Nobody covers more than 2 m a step, even
 * sprinting, so a walk's distance is capped there; otherwise distance badges unlock for nothing (a 132-step walk
 * logged 2,059 m and a One K badge on 31 Oct 2026).
 */
object WalkDistance {
    const val MAX_METRES_PER_STEP = 2.0

    fun capped(gpsMetres: Double, steps: Long): Double = minOf(gpsMetres, steps * MAX_METRES_PER_STEP)
}
