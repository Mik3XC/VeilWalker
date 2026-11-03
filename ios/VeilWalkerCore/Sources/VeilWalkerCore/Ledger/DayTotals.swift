import Foundation

/// Where counted steps came from. Drives the points multiplier. Raw values match Android's StepSource names.
public enum StepSource: String, Sendable, CaseIterable {
    case passive = "PASSIVE"
    case activeSensor = "ACTIVE_SENSOR"
    case activeGPS = "ACTIVE_GPS"
    case onion = "ONION"
}

/// One interval of counted steps: a walk window, or a block restored from the server's history.
public struct StepInterval: Equatable, Sendable {
    public var id: Int64?
    public var day: String          // ISO local date, e.g. 2026-10-27
    public var startMs: Int64
    public var endMs: Int64
    public var steps: Int64
    public var source: StepSource
    public var walkId: Int64?
    public var verdict: Float       // anti-cheat confidence 0...1

    public init(id: Int64? = nil, day: String, startMs: Int64, endMs: Int64, steps: Int64, source: StepSource,
                walkId: Int64? = nil, verdict: Float = 1) {
        self.id = id
        self.day = day
        self.startMs = startMs
        self.endMs = endMs
        self.steps = steps
        self.source = source
        self.walkId = walkId
        self.verdict = verdict
    }
}

/// A day's step totals by trust tier, as sent to the server. Only these numbers leave the phone.
public struct DayTotals: Equatable, Sendable {
    public var day: String
    public var passive: Int64
    public var sensor: Int64
    public var gps: Int64
    public var onion: Int64
    public var verdict: Float

    public init(day: String, passive: Int64, sensor: Int64, gps: Int64, onion: Int64, verdict: Float) {
        self.day = day
        self.passive = passive
        self.sensor = sensor
        self.gps = gps
        self.onion = onion
        self.verdict = verdict
    }

    public var total: Int64 { passive + sensor + gps + onion }

    /// What the device signs as its own record of the summary, as Android's `DayTotals.canonical()`.
    /// Swift prints Float like Kotlin does ("1.0", "0.901"); the server stores this signature without checking it.
    public var canonical: String { "\(day)|\(passive)|\(sensor)|\(gps)|\(onion)|\(verdict)" }

    /// Builds a day's totals.
    ///
    /// iOS differs from Android here: CMPedometer gives one true count per day instead of passive ticks, so
    /// passive = pedometer total − steps already credited to walks. Two floors keep it from shrinking, since the
    /// server rejects (409) any tier that goes down: steps restored from the server's history, and what was last synced.
    ///
    /// Verdict is the step-weighted average over walk intervals; passive steps carry none.
    public static func from(day: String, intervals: [StepInterval], pedometerSteps: Int64?, lastSynced: DayTotals? = nil) -> DayTotals {
        func sum(_ s: StepSource) -> Int64 { intervals.filter { $0.source == s }.reduce(0) { $0 + $1.steps } }
        let walked = intervals.filter { $0.source != .passive }
        let walkedSteps = walked.reduce(0) { $0 + $1.steps }
        let verdict: Float = walkedSteps == 0 ? 1
            : Float(walked.reduce(0.0) { $0 + Double($1.steps) * Double($1.verdict) } / Double(walkedSteps))
        let passive = max(sum(.passive), (pedometerSteps ?? 0) - walkedSteps, lastSynced?.passive ?? 0, 0)
        return DayTotals(day: day, passive: passive, sensor: sum(.activeSensor), gps: sum(.activeGPS),
                         onion: sum(.onion), verdict: verdict)
    }
}

/// The economy, for showing estimates. The server re-runs this (ledger.rs `milli_points`) and mints;
/// the ledger is the balance. 1 step at 1.0x = 1 milli-point. No daily cap; points never expire.
public enum PointsPolicy {
    public static func multiplierPermille(_ source: StepSource) -> Int64 {
        switch source {
        case .passive: 500
        case .activeSensor: 850
        case .activeGPS: 1000
        case .onion: 1250
        }
    }

    /// Same arithmetic as the server: per tier, truncated, verdict applied to every tier.
    public static func milliPoints(_ t: DayTotals) -> Int64 {
        [(t.onion, StepSource.onion), (t.gps, .activeGPS), (t.sensor, .activeSensor), (t.passive, .passive)]
            .reduce(0) { acc, tier in
                acc + Int64(Double(max(tier.0, 0)) * Double(multiplierPermille(tier.1)) * Double(t.verdict) / 1000)
            }
    }
}
