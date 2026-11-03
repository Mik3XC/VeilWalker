package org.trailbound.core.achievements

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import org.trailbound.core.data.dao.AchievementDao
import org.trailbound.core.data.dao.StepDao
import org.trailbound.core.data.dao.WalkDao
import org.trailbound.core.data.entity.AchievementUnlock
import org.trailbound.core.route.RouteRepository
import javax.inject.Inject
import javax.inject.Singleton

data class BadgeBoard(
    val all: List<Achievement>,
    /** achievementId → unlock time (epoch ms). */
    val unlockedAt: Map<String, Long>,
    val snowflakeMinutes: Long = 0,
) {
    val frost: Frost get() = Frost.of(snowflakeMinutes)
    val unlockedCount: Int get() = unlockedAt.size
    val rank: Rank get() = Rank.of(unlockedCount)

    private val outlawLadder: List<Achievement> get() = all.filter { it.family == OUTLAW_FAMILY }
    /** Smuggler grade from the outlaw ladder: STOWAWAY up to KINGPIN. Everyone starts a landlubber. */
    val outlawRank: String get() = outlawLadder.lastOrNull { it.id in unlockedAt }?.name?.uppercase() ?: "LANDLUBBER"
    val nextOutlaw: Achievement? get() = outlawLadder.firstOrNull { it.id !in unlockedAt }

    companion object { const val OUTLAW_FAMILY = "outlaw" }
}

/**
 * Re-evaluates the rules whenever steps, walks or route progress change, and records first-unlock times.
 * Unlocks are permanent: a broken streak doesn't take its badge back.
 */
@Singleton
class AchievementRepository @Inject constructor(
    @ApplicationContext context: Context,
    steps: StepDao,
    private val walks: WalkDao,
    routes: RouteRepository,
    private val dao: AchievementDao,
) {
    val rules: List<Achievement> =
        AchievementRules.parse(context.assets.open("achievements.json").bufferedReader().use { it.readText() })

    private val earnedNow: Flow<List<Achievement>> = combine(
        steps.observeDailyTotals(),
        walks.observeAll(),
        steps.observeOnionSteps(),
        routes.progress.map { it.position.unlocked.size },
    ) { days, walkList, onion, postcards ->
        AchievementRules.unlocked(rules, Metrics.compute(days, walkList, onion, postcards))
    }.onEach { earned ->
        val now = System.currentTimeMillis()
        earned.forEach { dao.unlock(AchievementUnlock(it.id, now)) }   // IGNORE keeps the first unlock time
    }

    val board: Flow<BadgeBoard> = combine(earnedNow, dao.observeAll(), walks.observeSnowflakeMinutes()) { _, stored, flakeMin ->
        BadgeBoard(rules, stored.associate { it.achievementId to it.unlockedEpochMs }, flakeMin)
    }
}
