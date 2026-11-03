package org.trailbound.core.achievements

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.trailbound.core.data.dao.DayTotal
import org.trailbound.core.data.entity.WalkModeEntity
import org.trailbound.core.data.entity.WalkSession
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

class AchievementsTest {

    private val rules = AchievementRules.parse(File("src/main/assets/achievements.json").readText())
    private val utc = ZoneId.of("UTC")
    private val today = LocalDate.of(2026, 10, 27)

    @Test fun rulesExpandToUniqueIds() {
        assertTrue("got ${rules.size}", rules.size >= 60)
        assertEquals(rules.size, rules.map { it.id }.toSet().size)
        // every family's names line up with its tiers (no fallback names leaking through)
        assertTrue(rules.none { it.name.contains('_') && it.name.endsWith(it.threshold.toString()) })
    }

    @Test fun descriptionsUseCompactNumbers() {
        assertEquals("Walk 10K steps, all time", rules.first { it.id == "steps_10000" }.description)
        assertEquals("Walk 21,097 m in a single walk", rules.first { it.id == "longest_21097" }.description)
    }

    @Test fun todaysRealDataUnlocksTheRightBadges() {
        // The S26 Edge history: 1,824 steps today, walks of 31 / 1,043 / 750 steps, the last one an Onion Walk.
        fun walk(id: Long, mode: WalkModeEntity, steps: Long, m: Double, tor: Boolean) = WalkSession(
            id = id, mode = mode, steps = steps, distanceM = m, torUsed = tor,
            startEpochMs = ZonedDateTime.of(2026, 10, 27, 18, 0, 0, 0, utc).toInstant().toEpochMilli(), endEpochMs = 1,
        )
        val metrics = Metrics.compute(
            days = listOf(DayTotal("2026-10-27", 1824)),
            walks = listOf(
                walk(8, WalkModeEntity.ACTIVE, 31, 18.7, false),
                walk(9, WalkModeEntity.ACTIVE, 1043, 806.3, false),
                walk(14, WalkModeEntity.ONION, 750, 513.2, true),
            ),
            onionSteps = 750, postcards = 1, today = today, zone = utc,
        )
        val ids = AchievementRules.unlocked(rules, metrics).map { it.id }.toSet()
        assertEquals(setOf("steps_1000", "walks_1", "onion_1", "postcards_1"), ids)
    }

    @Test fun streakCountsBackFromTodayOrYesterday() {
        val days = listOf("2026-10-24", "2026-10-25", "2026-10-26").map { DayTotal(it, 5000) }
        assertEquals(3, Metrics.streak(days, today))                         // today not walked yet: still alive
        assertEquals(4, Metrics.streak(days + DayTotal("2026-10-27", 3000), today))
        assertEquals(0, Metrics.streak(days.dropLast(1), today))              // missed yesterday: broken
    }

    @Test fun secretDaysOnlyCountFinishedDays() {
        val m = Metrics.compute(listOf(DayTotal("2026-10-27", 1337)), emptyList(), 0, 0, today, utc)
        assertEquals(0L, m["leet_days"])
        val m2 = Metrics.compute(listOf(DayTotal("2026-10-26", 1337), DayTotal("2026-10-25", 12321)), emptyList(), 0, 0, today, utc)
        assertEquals(1L, m2["leet_days"])
        assertEquals(1L, m2["palindrome_days"])
    }

    @Test fun frostTiersDecorateFrames() {
        assertEquals(Frost.NONE, Frost.of(9))
        assertEquals("(>>)", Frost.of(0).apply("(>>)"))
        assertEquals("*(>>)", Frost.of(10).apply("(>>)"))
        assertEquals("*[>>]*", Frost.of(100).apply("[>>]"))
        assertEquals("**{>>}**", Frost.of(5000).apply("{>>}"))
    }

    @Test fun rankThresholds() {
        assertEquals(Rank.NONE, Rank.of(4))
        assertEquals(Rank.BRONZE, Rank.of(5))
        assertEquals(Rank.GOLD, Rank.of(30))
        assertFalse(Rank.of(49) == Rank.PLATINUM)
    }
}
