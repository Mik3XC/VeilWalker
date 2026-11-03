package org.trailbound.core.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow
import org.trailbound.core.data.entity.AchievementUnlock
import org.trailbound.core.data.entity.CounterBaseline
import org.trailbound.core.data.entity.DailySummary
import org.trailbound.core.data.entity.LedgerEntry
import org.trailbound.core.data.entity.RawTrace
import org.trailbound.core.data.entity.StepInterval
import org.trailbound.core.data.entity.WalkSession

@Dao
interface StepDao {
    @Query("SELECT * FROM counter_baseline WHERE id = 0")
    suspend fun baseline(): CounterBaseline?

    @Upsert
    suspend fun saveBaseline(b: CounterBaseline)

    @Insert
    suspend fun insertInterval(i: StepInterval): Long

    @Query("SELECT SUM(steps) FROM step_interval WHERE day = :day")
    fun observeStepsForDay(day: String): Flow<Long?>

    @Query("SELECT * FROM step_interval WHERE day = :day")
    suspend fun intervalsForDay(day: String): List<StepInterval>

    @Query("SELECT SUM(steps) FROM step_interval")
    fun observeTotalSteps(): Flow<Long?>

    @Query("SELECT COUNT(*) FROM step_interval")
    suspend fun intervalCount(): Int

    @Query("SELECT * FROM step_interval WHERE day = :day")
    fun observeIntervalsForDay(day: String): Flow<List<StepInterval>>

    @Query("SELECT day, SUM(steps) AS steps FROM step_interval GROUP BY day ORDER BY day")
    fun observeDailyTotals(): Flow<List<DayTotal>>

    @Query("SELECT COALESCE(SUM(steps), 0) FROM step_interval WHERE source = 'ONION'")
    fun observeOnionSteps(): Flow<Long>

    @Query("SELECT DISTINCT day FROM step_interval WHERE day >= :sinceDay ORDER BY day")
    suspend fun daysSince(sinceDay: String): List<String>

    /** The verdict is scored after the steps are read, so it's attached to the walk's newest interval afterwards. */
    @Query("UPDATE step_interval SET verdict = :verdict WHERE id = (SELECT MAX(id) FROM step_interval WHERE walkId = :walkId)")
    suspend fun setLatestVerdict(walkId: Long, verdict: Float)
}

data class GpsCalibration(val distanceM: Double?, val steps: Long?)

data class DayTotal(val day: String, val steps: Long)

@Dao
interface WalkDao {
    @Insert
    suspend fun insert(w: WalkSession): Long

    @Upsert
    suspend fun update(w: WalkSession)

    @Query("UPDATE walk_session SET endEpochMs = :nowEpochMs WHERE endEpochMs IS NULL")
    suspend fun closeOpenSessions(nowEpochMs: Long)

    @Query("SELECT * FROM walk_session WHERE id = :id")
    suspend fun get(id: Long): WalkSession?

    @Query("SELECT COALESCE(SUM(snowflakeBytes), 0) FROM walk_session WHERE startEpochMs >= :sinceEpochMs")
    suspend fun snowflakeBytesSince(sinceEpochMs: Long): Long

    /** Totals over finished walks long enough for GPS distance to be meaningful (stride calibration). */
    @Query("SELECT SUM(distanceM) AS distanceM, SUM(steps) AS steps FROM walk_session WHERE endEpochMs IS NOT NULL AND distanceM > 100")
    fun observeGpsCalibration(): Flow<GpsCalibration?>

    @Query("SELECT * FROM walk_session ORDER BY id")
    fun observeAll(): Flow<List<WalkSession>>

    @Query("SELECT COALESCE(SUM(coldClimbM), 0) FROM walk_session")
    fun observeColdClimbM(): Flow<Double>

    @Query("SELECT COALESCE(SUM(snowflakeMinutes), 0) FROM walk_session")
    fun observeSnowflakeMinutes(): Flow<Long>
}

@Dao
interface TraceDao {
    @Insert
    suspend fun insert(t: RawTrace)

    /** Privacy promise: raw traces older than 30 days are deleted. */
    @Query("DELETE FROM raw_trace WHERE epochMs < :cutoffEpochMs")
    suspend fun purgeOlderThan(cutoffEpochMs: Long): Int
}

@Dao
interface SummaryDao {
    @Upsert
    suspend fun upsert(s: DailySummary)

    @Query("SELECT * FROM daily_summary WHERE synced = 0 ORDER BY day")
    suspend fun unsynced(): List<DailySummary>
}

@Dao
interface LedgerDao {
    // ABORT, never REPLACE: the ledger is append-only.
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun append(e: LedgerEntry)

    @Query("SELECT * FROM ledger_entry ORDER BY seq DESC LIMIT 1")
    suspend fun head(): LedgerEntry?

    @Query("SELECT * FROM ledger_entry ORDER BY seq")
    suspend fun all(): List<LedgerEntry>

    @Query("SELECT COALESCE(SUM(amount), 0) FROM ledger_entry")
    fun observeBalanceMilli(): Flow<Long>
}

@Dao
interface AchievementDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun unlock(a: AchievementUnlock): Long

    @Query("SELECT achievementId FROM achievement_unlock")
    suspend fun unlockedIds(): List<String>

    @Query("SELECT * FROM achievement_unlock")
    fun observeAll(): Flow<List<AchievementUnlock>>
}
