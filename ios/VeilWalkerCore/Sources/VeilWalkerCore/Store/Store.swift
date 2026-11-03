import Foundation
import GRDB

/// The app's SQLite database (GRDB). Mirrors Android's Room schema for what iOS needs so far;
/// walk sessions and raw traces arrive with live walks.
public final class Store: Sendable {
    let db: any DatabaseWriter

    /// Opens (creating if needed) the database file in Application Support, excluded from iCloud backup:
    /// it holds the account's history, and the phrase + server history are the restore path.
    public static func openDefault() throws -> Store {
        var dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dir.setResourceValues(values)
        return try Store(path: dir.appending(path: "veilwalker.sqlite").path)
    }

    public init(path: String) throws {
        db = try DatabaseQueue(path: path)
        try Self.migrator.migrate(db)
    }

    /// In-memory, for tests.
    public init() throws {
        db = try DatabaseQueue()
        try Self.migrator.migrate(db)
    }

    static let ledgerNoDelete =
        "CREATE TRIGGER ledger_no_delete BEFORE DELETE ON ledger_entry BEGIN SELECT RAISE(ABORT, 'ledger is append-only'); END"

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE step_interval (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    day TEXT NOT NULL,
                    start_ms INTEGER NOT NULL,
                    end_ms INTEGER NOT NULL,
                    steps INTEGER NOT NULL,
                    source TEXT NOT NULL,
                    walk_id INTEGER,
                    verdict REAL NOT NULL DEFAULT 1
                );
                CREATE INDEX step_interval_day ON step_interval(day);

                -- CMPedometer's true count per local day. CoreMotion only keeps 7 days, so this is the long-term record.
                CREATE TABLE pedometer_day (
                    day TEXT PRIMARY KEY,
                    steps INTEGER NOT NULL
                );

                -- The totals the server last accepted per day. Totals may only grow (409 otherwise).
                CREATE TABLE synced_day (
                    day TEXT PRIMARY KEY,
                    passive INTEGER NOT NULL,
                    sensor INTEGER NOT NULL,
                    gps INTEGER NOT NULL,
                    onion INTEGER NOT NULL,
                    verdict REAL NOT NULL
                );

                -- Local copy of the server-signed, hash-chained ledger. Same columns as Android's ledger_entry.
                CREATE TABLE ledger_entry (
                    seq INTEGER PRIMARY KEY,
                    kind TEXT NOT NULL,
                    amount INTEGER NOT NULL,
                    reason_code TEXT NOT NULL,
                    ref_id TEXT NOT NULL,
                    ts_ms INTEGER NOT NULL,
                    prev_hash BLOB NOT NULL,
                    entry_hash BLOB NOT NULL,
                    server_sig BLOB NOT NULL
                );
                CREATE TRIGGER ledger_no_update BEFORE UPDATE ON ledger_entry BEGIN SELECT RAISE(ABORT, 'ledger is append-only'); END;
                \(ledgerNoDelete);

                -- Small facts about this install: which account the ledger copy belongs to, registration.
                CREATE TABLE meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                """)
        }
        m.registerMigration("v2") { db in
            try db.execute(sql: """
                -- First unlock time per badge. Unlocks are permanent: a broken streak doesn't take its badge back.
                CREATE TABLE achievement_unlock (
                    id TEXT PRIMARY KEY,
                    unlocked_ms INTEGER NOT NULL
                );
                """)
        }
        m.registerMigration("v3") { db in
            try db.execute(sql: """
                -- Same columns as Android's walk_session, plus `retro` for walks rebuilt from CoreMotion history.
                CREATE TABLE walk_session (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    mode TEXT NOT NULL,
                    start_ms INTEGER NOT NULL,
                    end_ms INTEGER,
                    steps INTEGER NOT NULL DEFAULT 0,
                    distance_m REAL NOT NULL DEFAULT 0,
                    verdict REAL NOT NULL DEFAULT 1,
                    tor_used INTEGER NOT NULL DEFAULT 0,
                    snowflake_minutes INTEGER NOT NULL DEFAULT 0,
                    cold_climb_m REAL NOT NULL DEFAULT 0,
                    min_temp_f INTEGER,
                    retro INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX walk_session_start ON walk_session(start_ms);
                CREATE INDEX step_interval_walk ON step_interval(walk_id);
                """)
        }
        m.registerMigration("v4") { db in
            // The first retroactive scan (dev builds of 30 Oct 2026 only) could run twice at once and record every walk
            // twice. Drop those walks and the walk badges they unlocked; the next scan rebuilds them once. Nothing was
            // synced from them: their steps were already passive.
            try db.execute(sql: """
                DELETE FROM step_interval WHERE walk_id IN (SELECT id FROM walk_session WHERE retro = 1);
                DELETE FROM walk_session WHERE retro = 1;
                DELETE FROM achievement_unlock WHERE id GLOB 'walks_*' OR id GLOB 'longest_*' OR id GLOB 'dawn_*'
                    OR id GLOB 'night_*' OR id GLOB 'ghost_hour_*';
                """)
        }
        m.registerMigration("v5") { db in
            // Same cleanup again: until the step-rate check, pottering at home counted as dozens of walks a day.
            try db.execute(sql: """
                DELETE FROM step_interval WHERE walk_id IN (SELECT id FROM walk_session WHERE retro = 1);
                DELETE FROM walk_session WHERE retro = 1;
                DELETE FROM achievement_unlock WHERE id GLOB 'walks_*' OR id GLOB 'longest_*' OR id GLOB 'dawn_*'
                    OR id GLOB 'night_*' OR id GLOB 'ghost_hour_*';
                """)
        }
        return m
    }

    // MARK: Meta

    public func meta(_ key: String) throws -> String? {
        try db.read { try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key]) }
    }

    public func setMeta(_ key: String, _ value: String?) throws {
        try db.write { db in
            if let value {
                try db.execute(sql: "INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                               arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM meta WHERE key = ?", arguments: [key])
            }
        }
    }

    // MARK: Steps

    public func insert(_ interval: StepInterval) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO step_interval(day, start_ms, end_ms, steps, source, walk_id, verdict) VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [interval.day, interval.startMs, interval.endMs, interval.steps, interval.source.rawValue,
                                 interval.walkId, Double(interval.verdict)])
        }
    }

    public func intervals(day: String) throws -> [StepInterval] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM step_interval WHERE day = ? ORDER BY start_ms, id", arguments: [day]).map { row in
                StepInterval(id: row["id"], day: row["day"], startMs: row["start_ms"], endMs: row["end_ms"], steps: row["steps"],
                             source: StepSource(rawValue: row["source"]) ?? .passive, walkId: row["walk_id"],
                             verdict: Float(row["verdict"] as Double))
            }
        }
    }

    /// Records CMPedometer's count for a day. Keeps the larger value, so a short query can't shrink history.
    public func setPedometer(day: String, steps: Int64) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO pedometer_day(day, steps) VALUES (?, ?)
                ON CONFLICT(day) DO UPDATE SET steps = max(steps, excluded.steps)
                """, arguments: [day, steps])
        }
    }

    public func pedometer(day: String) throws -> Int64? {
        try db.read { try Int64.fetchOne($0, sql: "SELECT steps FROM pedometer_day WHERE day = ?", arguments: [day]) }
    }

    /// Days with any local record on or after `since` (ISO date), oldest first.
    public func daysWithSteps(since: String) throws -> [String] {
        try db.read { db in
            try String.fetchAll(db, sql: """
                SELECT day FROM step_interval WHERE day >= ?1
                UNION SELECT day FROM pedometer_day WHERE day >= ?1 AND steps > 0
                ORDER BY day
                """, arguments: [since])
        }
    }

    /// Lifetime TRUE steps: every day's tiers added up (multipliers only touch points).
    public func lifetimeSteps() throws -> Int64 {
        try daysWithSteps(since: "").reduce(0) { try $0 + totals(day: $1).total }
    }

    /// Every day's true step count, oldest first: what stats, badges and the route are built from.
    public func dailyCounts() throws -> [DayCount] {
        try daysWithSteps(since: "").map { DayCount(day: $0, steps: try totals(day: $0).total) }
    }

    /// Steps proven over Tor (the onion tier), for the onion badges.
    public func onionSteps() throws -> Int64 {
        try db.read { try Int64.fetchOne($0, sql: "SELECT COALESCE(SUM(steps), 0) FROM step_interval WHERE source = 'ONION'") ?? 0 }
    }

    /// The day's totals as they'd be synced now.
    public func totals(day: String) throws -> DayTotals {
        try DayTotals.from(day: day, intervals: intervals(day: day), pedometerSteps: pedometer(day: day), lastSynced: synced(day: day))
    }

    // MARK: Sync state

    public func synced(day: String) throws -> DayTotals? {
        try db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM synced_day WHERE day = ?", arguments: [day]).map { row in
                DayTotals(day: row["day"], passive: row["passive"], sensor: row["sensor"], gps: row["gps"], onion: row["onion"],
                          verdict: Float(row["verdict"] as Double))
            }
        }
    }

    public func markSynced(_ t: DayTotals) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO synced_day(day, passive, sensor, gps, onion, verdict) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(day) DO UPDATE SET passive = excluded.passive, sensor = excluded.sensor,
                    gps = excluded.gps, onion = excluded.onion, verdict = excluded.verdict
                """, arguments: [t.day, t.passive, t.sensor, t.gps, t.onion, Double(t.verdict)])
        }
    }

    // MARK: Walks

    public func insertWalk(mode: WalkMode, startMs: Int64, retro: Bool = false) throws -> Int64 {
        try db.write { db in
            try db.execute(sql: "INSERT INTO walk_session(mode, start_ms, retro) VALUES (?, ?, ?)",
                           arguments: [mode.rawValue, startMs, retro ? 1 : 0])
            return db.lastInsertedRowID
        }
    }

    public func updateWalk(id: Int64, steps: Int64, distanceM: Double, verdict: Float, torUsed: Bool) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE walk_session SET steps = ?, distance_m = ?, verdict = ?, tor_used = ? WHERE id = ?",
                           arguments: [steps, distanceM, Double(verdict), torUsed ? 1 : 0, id])
        }
    }

    /// Hidden Peaks bookkeeping for a walk: cold climb so far and the coldest temperature seen.
    public func setWalkWeather(id: Int64, coldClimbM: Double, minTempF: Int?) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE walk_session SET cold_climb_m = ?, min_temp_f = ? WHERE id = ?",
                           arguments: [coldClimbM, minTempF, id])
        }
    }

    /// Minutes of Snowflake hosting during a walk: what frosts the badge frames (status only, never points).
    public func addWalkSnowflakeMinutes(id: Int64, minutes: Int64) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE walk_session SET snowflake_minutes = snowflake_minutes + ? WHERE id = ?", arguments: [minutes, id])
        }
    }

    public func snowflakeMinutes() throws -> Int64 {
        try db.read { try Int64.fetchOne($0, sql: "SELECT COALESCE(SUM(snowflake_minutes), 0) FROM walk_session") ?? 0 }
    }

    /// Metres climbed on freezing walks, all time: what reveals the Hidden Peaks.
    public func coldClimbM() throws -> Double {
        try db.read { try Double.fetchOne($0, sql: "SELECT COALESCE(SUM(cold_climb_m), 0) FROM walk_session") ?? 0 }
    }

    public func endWalk(id: Int64, endMs: Int64) throws {
        try db.write { try $0.execute(sql: "UPDATE walk_session SET end_ms = ? WHERE id = ?", arguments: [endMs, id]) }
    }

    /// Closes walks left open by a process iOS killed mid-walk, at their last recorded window.
    public func closeOpenWalks(nowMs: Int64) throws {
        try db.write { db in
            try db.execute(sql: """
                UPDATE walk_session SET end_ms = COALESCE(
                    (SELECT MAX(end_ms) FROM step_interval WHERE walk_id = walk_session.id), start_ms, ?)
                WHERE end_ms IS NULL
                """, arguments: [nowMs])
        }
    }

    /// Walks that start before `endMs` and end (or are open) after `startMs`.
    public func walks(from startMs: Int64, to endMs: Int64) throws -> [WalkRow] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, start_ms, end_ms, retro FROM walk_session WHERE start_ms < ? AND COALESCE(end_ms, ?) > ? ORDER BY start_ms
                """, arguments: [endMs, Int64.max, startMs]).map {
                WalkRow(id: $0["id"], startMs: $0["start_ms"], endMs: $0["end_ms"], retro: ($0["retro"] as Int) == 1)
            }
        }
    }

    /// Adds steps (and moves the end) of a walk that resumed within 4.5 min.
    public func extendWalk(id: Int64, steps: Int64, endMs: Int64) throws {
        try db.write { try $0.execute(sql: "UPDATE walk_session SET steps = steps + ?, end_ms = ? WHERE id = ?", arguments: [steps, endMs, id]) }
    }

    /// True if [startMs, endMs] overlaps a walk already on record (live or retro), so history isn't counted twice.
    public func overlapsWalk(startMs: Int64, endMs: Int64) throws -> Bool {
        try db.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM walk_session WHERE start_ms < ? AND COALESCE(end_ms, ?) > ?)
                """, arguments: [endMs, Int64.max, startMs]) ?? false
        }
    }

    /// Finished walks, for badges.
    public func walkFacts() throws -> [WalkFacts] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM walk_session ORDER BY id").map { r in
                WalkFacts(startMs: r["start_ms"], endMs: r["end_ms"], steps: r["steps"], distanceM: r["distance_m"],
                          onion: (r["mode"] as String) == WalkMode.onion.rawValue, torUsed: (r["tor_used"] as Int) == 1,
                          snowflakeMinutes: r["snowflake_minutes"], coldClimbM: r["cold_climb_m"])
            }
        }
    }

    /// The walker's stride from their own GPS walks over 100 m (Android's observeGpsCalibration + strideFrom).
    public func strideM() throws -> Double {
        try db.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT SUM(distance_m) AS d, SUM(steps) AS s FROM walk_session WHERE end_ms IS NOT NULL AND distance_m > 100
                """)
            return Stride.from(distanceM: row?["d"], steps: row?["s"])
        }
    }

    /// Records walk steps for a day, capped at what the day hasn't already counted.
    ///
    /// iOS-specific guard: the pedometer gives one total per day, and passive = total − walk steps. Steps the server
    /// has already accepted as passive can't move to a walk tier (passive may never shrink), so re-labelling them
    /// would count them twice. A walk is credited only with steps not yet claimed; the rest stay passive.
    /// Returns the steps credited.
    @discardableResult
    public func recordWalkSteps(_ interval: StepInterval) throws -> Int64 {
        precondition(interval.source != .passive)
        return try db.write { db in
            let pedometer = try Int64.fetchOne(db, sql: "SELECT steps FROM pedometer_day WHERE day = ?", arguments: [interval.day]) ?? 0
            let walked = try Int64.fetchOne(db, sql: """
                SELECT COALESCE(SUM(steps), 0) FROM step_interval WHERE day = ? AND source != 'PASSIVE'
                """, arguments: [interval.day]) ?? 0
            let restoredPassive = try Int64.fetchOne(db, sql: """
                SELECT COALESCE(SUM(steps), 0) FROM step_interval WHERE day = ? AND source = 'PASSIVE'
                """, arguments: [interval.day]) ?? 0
            let syncedPassive = try Int64.fetchOne(db, sql: "SELECT passive FROM synced_day WHERE day = ?", arguments: [interval.day]) ?? 0
            let room = max(pedometer - max(syncedPassive, restoredPassive) - walked, 0)
            let credit = min(interval.steps, room)
            if credit > 0 {
                try db.execute(sql: """
                    INSERT INTO step_interval(day, start_ms, end_ms, steps, source, walk_id, verdict) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [interval.day, interval.startMs, interval.endMs, credit, interval.source.rawValue,
                                     interval.walkId, Double(interval.verdict)])
            }
            return credit
        }
    }

    // MARK: Badges

    /// Records first-unlock times; ids already unlocked keep their original time.
    public func unlock(_ ids: [String], at ms: Int64) throws {
        try db.write { db in
            for id in ids {
                try db.execute(sql: "INSERT OR IGNORE INTO achievement_unlock(id, unlocked_ms) VALUES (?, ?)", arguments: [id, ms])
            }
        }
    }

    public func unlocks() throws -> [String: Int64] {
        try db.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, unlocked_ms FROM achievement_unlock").map {
                ($0["id"] as String, $0["unlocked_ms"] as Int64)
            })
        }
    }

    // MARK: Ledger

    public func ledgerHead() throws -> LedgerEntry? {
        try db.read { try Row.fetchOne($0, sql: "SELECT * FROM ledger_entry ORDER BY seq DESC LIMIT 1").map(Self.entry) }
    }

    public func ledgerEntries() throws -> [LedgerEntry] {
        try db.read { try Row.fetchAll($0, sql: "SELECT * FROM ledger_entry ORDER BY seq").map(Self.entry) }
    }

    /// Lifetime balance in milli-points.
    public func balanceMilli() throws -> Int64 {
        try db.read { try Int64.fetchOne($0, sql: "SELECT COALESCE(SUM(amount), 0) FROM ledger_entry") ?? 0 }
    }

    /// Appends `entry` only if it links onto the current head and carries a valid server signature,
    /// checked inside the write transaction so two syncs can't race past each other.
    public func appendFromServer(_ entry: LedgerEntry, serverKey: Data = Ledger.serverPublicKey) throws {
        try db.write { db in
            let head = try Row.fetchOne(db, sql: "SELECT * FROM ledger_entry ORDER BY seq DESC LIMIT 1").map(Self.entry)
            try Ledger.check(entry, after: head, serverKey: serverKey)
            try db.execute(sql: """
                INSERT INTO ledger_entry(seq, kind, amount, reason_code, ref_id, ts_ms, prev_hash, entry_hash, server_sig)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [entry.seq, entry.kind, entry.amount, entry.reasonCode, entry.refId, entry.tsMs,
                                 entry.prevHash, entry.entryHash, entry.serverSig])
        }
    }

    /// The only sanctioned way to clear the ledger copy: a different identity was restored, so the old account's
    /// chain and sync floors no longer belong here. Lifts the delete trigger just for this, as Android does.
    public func resetForNewIdentity() throws {
        try db.write { db in
            try db.execute(sql: "DROP TRIGGER IF EXISTS ledger_no_delete")
            try db.execute(sql: "DELETE FROM ledger_entry")
            try db.execute(sql: Self.ledgerNoDelete)
            try db.execute(sql: "DELETE FROM synced_day")
            try db.execute(sql: "DELETE FROM meta WHERE key IN ('owner', 'registered', 'username', 'clan', 'avatar')")
        }
    }

    /// Account deletion: removes everything this install recorded, ledger included. The phone's step history goes
    /// too; a new account starts from CMPedometer's last 7 days.
    public func wipeAll() throws {
        try db.write { db in
            try db.execute(sql: "DROP TRIGGER IF EXISTS ledger_no_delete")
            try db.execute(sql: """
                DELETE FROM ledger_entry; DELETE FROM synced_day; DELETE FROM step_interval; DELETE FROM pedometer_day;
                DELETE FROM walk_session; DELETE FROM achievement_unlock; DELETE FROM meta;
                """)
            try db.execute(sql: Self.ledgerNoDelete)
        }
    }

    private static func entry(_ row: Row) -> LedgerEntry {
        LedgerEntry(seq: row["seq"], kind: row["kind"], amount: row["amount"], reasonCode: row["reason_code"], refId: row["ref_id"],
                    tsMs: row["ts_ms"], prevHash: row["prev_hash"], entryHash: row["entry_hash"], serverSig: row["server_sig"])
    }
}
