package org.trailbound.core.ledger

import org.trailbound.core.data.entity.StepSource

/**
 * The economy in one place. Amounts are milli-points (1 pt = 1,000 steps = 1,000 milli-points),
 * so multipliers stay exact integers. Points never expire.
 */
object PointsPolicy {
    /** Snowflake hosting is intentionally absent: it earns status and emblems, never points (Play proxyware policy). */
    fun multiplierPermille(source: StepSource): Long = when (source) {
        StepSource.PASSIVE -> 500
        StepSource.HEALTH_CONNECT -> 500
        StepSource.ACTIVE_SENSOR -> 850
        StepSource.ACTIVE_GPS -> 1000
        StepSource.ONION -> 1250
    }

    data class Bucket(val source: StepSource, val steps: Long, val verdict: Float)

    /**
     * No daily cap, free or paid: every verified step counts. Abuse is handled by the verdict and the
     * server's 60k/day hold-for-review. Returns milli-points to propose to the server; the server re-runs this and mints.
     */
    fun milliPointsForDay(buckets: List<Bucket>): Long =
        // 1 step at 1.0x = 1 milli-point, so milli = steps * permille / 1000.
        buckets.sumOf { (it.steps * multiplierPermille(it.source) * it.verdict.toDouble() / 1000.0).toLong() }
}
