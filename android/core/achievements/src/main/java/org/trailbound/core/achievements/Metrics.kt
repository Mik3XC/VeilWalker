package org.trailbound.core.achievements

import org.trailbound.core.data.dao.DayTotal
import org.trailbound.core.data.entity.WalkModeEntity
import org.trailbound.core.data.entity.WalkSession
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Turns the raw local history into the numbers rules are written against. Everything stays on the phone. */
object Metrics {
    const val STREAK_MIN_STEPS = 3_000L

    fun compute(
        days: List<DayTotal>,
        walks: List<WalkSession>,
        onionSteps: Long,
        postcards: Int,
        today: LocalDate = LocalDate.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): Map<String, Long> {
        val done = walks.filter { it.endEpochMs != null && it.steps > 0 }
        fun startHour(w: WalkSession) = Instant.ofEpochMilli(w.startEpochMs).atZone(zone).hour
        val closed = days.filter { LocalDate.parse(it.day) < today }   // exact-count badges only judge finished days

        return mapOf(
            "lifetime_steps" to days.sumOf { it.steps },
            "best_day_steps" to (days.maxOfOrNull { it.steps } ?: 0),
            "streak_days" to streak(days, today).toLong(),
            "walk_count" to done.size.toLong(),
            "onion_walk_count" to done.count { it.mode == WalkModeEntity.ONION && it.torUsed }.toLong(),
            "onion_steps" to onionSteps,
            "snowflake_minutes" to walks.sumOf { it.snowflakeMinutes.toLong() },
            "cold_climb_m" to walks.sumOf { it.coldClimbM }.toLong(),
            "route_postcards" to postcards.toLong(),
            "longest_walk_m" to (done.maxOfOrNull { it.distanceM.toLong() } ?: 0),
            "dawn_walks" to done.count { startHour(it) in 4..6 }.toLong(),
            "night_walks" to done.count { startHour(it) >= 22 || startHour(it) < 4 }.toLong(),
            "ghost_hour_walks" to done.count { startHour(it) == 3 }.toLong(),
            "leet_days" to closed.count { it.steps == 1337L }.toLong(),
            "palindrome_days" to closed.count { it.steps >= 10_000 && it.steps.toString().let { s -> s == s.reversed() } }.toLong(),
        )
    }

    /** Consecutive days at 3,000+ steps, ending today (or yesterday, so the streak isn't lost before today's walk). */
    fun streak(days: List<DayTotal>, today: LocalDate): Int {
        val good = days.filter { it.steps >= STREAK_MIN_STEPS }.map { LocalDate.parse(it.day) }.toSet()
        var d = if (today in good) today else today.minusDays(1)
        var n = 0
        while (d in good) { n++; d = d.minusDays(1) }
        return n
    }
}
