package org.trailbound.core.anticheat

import kotlin.math.sqrt

/**
 * Daily anomaly score against the user's own 30-day baseline.
 * A high score doesn't cap anyone. It marks the day "held for review" before points are minted.
 */
object DailyAnomaly {
    const val REVIEW_CEILING_STEPS = 60_000L

    data class Result(val zScore: Double, val holdForReview: Boolean)

    fun evaluate(todaySteps: Long, last30Days: List<Long>): Result {
        if (todaySteps > REVIEW_CEILING_STEPS) return Result(Double.POSITIVE_INFINITY, true)
        if (last30Days.size < 7) return Result(0.0, false) // not enough history yet; caps protect us
        val mean = last30Days.average()
        val sd = sqrt(last30Days.sumOf { (it - mean) * (it - mean) } / last30Days.size).coerceAtLeast(1500.0)
        val z = (todaySteps - mean) / sd
        return Result(z, z > 4.0)
    }
}
