package org.trailbound.core.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/** Where a step interval came from. Drives the points multiplier. */
enum class StepSource { PASSIVE, ACTIVE_SENSOR, ACTIVE_GPS, ONION, HEALTH_CONNECT }

/**
 * Last raw TYPE_STEP_COUNTER reading. The hardware counter resets to 0 on reboot, so we
 * keep the boot count alongside it: a new boot (or a value lower than last time) starts a fresh baseline.
 */
@Entity(tableName = "counter_baseline")
data class CounterBaseline(
    @PrimaryKey val id: Int = 0,
    val bootCount: Int,
    val lastRawValue: Long,
    val lastReadEpochMs: Long,
)

/** One interval of counted steps (a passive worker tick or a walk window). */
@Entity(tableName = "step_interval", indices = [Index("day"), Index("walkId")])
data class StepInterval(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val day: String,              // ISO local date, e.g. 2026-10-27
    val startEpochMs: Long,
    val endEpochMs: Long,
    val steps: Long,
    val source: StepSource,
    val walkId: Long? = null,
    val verdict: Float = 1f,      // anti-cheat confidence 0..1
)

enum class WalkModeEntity { ACTIVE, ONION, SNOWFLAKE }

@Entity(tableName = "walk_session")
data class WalkSession(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val mode: WalkModeEntity,
    val startEpochMs: Long,
    val endEpochMs: Long? = null,
    val steps: Long = 0,
    val distanceM: Double = 0.0,
    val verdict: Float = 1f,
    val torUsed: Boolean = false,
    val snowflakeBytes: Long = 0,
    val snowflakeMinutes: Int = 0,
    val dogTagged: Boolean = false,
    /** Climb on freezing walks only (30°F or below): 7 cm of virtual trail per step plus real barometric climb. Feeds Hidden Peaks. */
    val coldClimbM: Double = 0.0,
    /** Coldest outside temperature seen during the walk, if known. */
    val minTempF: Int? = null,
)

/**
 * Raw sensor/GPS traces. Local only, never synced, purged after 30 days (privacy promise).
 * Stored as compact blobs per window to keep the table small.
 */
@Entity(tableName = "raw_trace", indices = [Index("walkId"), Index("epochMs")])
data class RawTrace(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val walkId: Long,
    val epochMs: Long,
    val kind: String,             // "accel" | "gyro" | "gps"
    val payload: ByteArray,
)

/** Signed summary that IS synced. Kept forever and included in the E2E-encrypted backup. */
@Entity(tableName = "daily_summary")
data class DailySummary(
    @PrimaryKey val day: String,
    val stepsPassive: Long,
    val stepsVerified: Long,
    val stepsOnion: Long,
    val verdict: Float,
    val routeProgressM: Double,
    val synced: Boolean = false,
    val signature: ByteArray? = null,
)

/**
 * Local mirror of the server-authoritative points ledger. Append-only and hash-chained:
 * entryHash = SHA-256(prevHash || canonical(fields)). Never UPDATE or DELETE rows.
 */
@Entity(tableName = "ledger_entry", indices = [Index(value = ["seq"], unique = true)])
data class LedgerEntry(
    @PrimaryKey val seq: Long,
    val kind: String,             // earn | redeem | adjust (no expire: points are lifetime)
    val amount: Long,             // milli-points, so 1.25x multipliers stay integer
    val reasonCode: String,
    val refId: String,
    val tsEpochMs: Long,
    val prevHash: ByteArray,
    val entryHash: ByteArray,
    val clientSig: ByteArray?,
    val serverSig: ByteArray?,
)

@Entity(tableName = "achievement_unlock")
data class AchievementUnlock(
    @PrimaryKey val achievementId: String,
    val unlockedEpochMs: Long,
    val synced: Boolean = false,
)
