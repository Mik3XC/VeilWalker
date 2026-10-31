import Foundation

/// Hands-free walk timing, the same numbers as Android's AutoWalk.kt: 27 s of continuous steps starts a walk,
/// 47 s still pauses it, 3 min still shows the red-light notice, 4.5 min still ends it. No "End walk" button.
public enum WalkRules {
    public static let confirmMs: Int64 = 27_000
    public static let pauseMs: Int64 = 47_000
    public static let redLightMs: Int64 = 180_000
    public static let endMs: Int64 = 270_000
    /// Anti-cheat and tier window, as Android's WalkService WINDOW_MS.
    public static let windowMs: Int64 = 10_000
    /// Auto-detected movement must confirm within a minute, or it was nothing.
    public static let confirmDeadlineMs: Int64 = 60_000
    /// A gap this long between step updates breaks "continuous". Android's step detector fires per step and uses 4 s;
    /// CMPedometer pushes batched updates every few seconds, so iOS allows 6 s.
    public static let continuityGapMs: Int64 = 6_000
    /// Retroactive walks: CoreMotion labels pottering around a room "walking" too, so a walk from history must show
    /// real continuous walking near its start: this many steps in one 30 s slice of its first 3 minutes (1 step/s).
    public static let retroConfirmSteps: Int64 = 30
    public static let retroSliceMs: Int64 = 30_000
    public static let retroConfirmSpanMs: Int64 = 180_000
}

public enum WalkMode: String, Sendable {
    case active = "ACTIVE"
    case onion = "ONION"
}

/// What a live walk is doing right now, for the home screen. Mirrors WalkStatus.kt.
public enum WalkStatus: Equatable, Sendable {
    case idle
    /// Auto-detected movement; becomes a walk after 27 s of continuous steps.
    case confirming(walkingForMs: Int64)
    case walking(mode: WalkMode, startedMs: Int64, steps: Int64, gps: Bool)
    /// Still for 47 s+: steps resume the walk; 3 min shows the red-light notice; 4.5 min ends it.
    case paused(mode: WalkMode, startedMs: Int64, steps: Int64, idleMs: Int64)

    /// The home screen's walk line, same words as HomeScreen.kt's walkLine().
    public func line(nowMs: Int64) -> String {
        switch self {
        case .idle:
            return "walk: auto · 27 s of steps needed"
        case .confirming(let ms):
            return "walk: detecting… \(ms / 1000)/\(WalkRules.confirmMs / 1000) s"
        case .walking(_, let started, let steps, let gps):
            return "walk: \(Self.mmss(nowMs - started)) · \(steps) steps" + (gps ? "" : " · no gps")
        case .paused(_, _, _, let idle):
            return idle >= WalkRules.redLightMs ? "walk: red light? ends in \(Self.mmss(WalkRules.endMs - idle))"
                : "walk: paused \(Self.mmss(idle))"
        }
    }

    public var isIdle: Bool { self == .idle }

    public static func mmss(_ ms: Int64) -> String {
        let s = max(ms, 0) / 1000
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

/// The stillness and confirm timers of a live walk, as a pure state machine (Android keeps these in WalkService).
/// Feed it step-update times and clock ticks; it reports what happened.
public struct WalkTracker: Sendable {
    public enum Event: Equatable, Sendable { case started, abandoned, redLight, resumed, ended }
    public enum Phase: Equatable, Sendable { case confirming(deadlineMs: Int64), walking, ended }

    public private(set) var phase: Phase
    public private(set) var startMs: Int64
    public private(set) var lastStepMs: Int64
    public private(set) var redLightShown = false
    private var walkingSinceMs: Int64?

    /// A manual start (the user tapped the walk line): no confirm phase, like Android's startIntent.
    public static func walking(at ms: Int64) -> WalkTracker { WalkTracker(phase: .walking, startMs: ms, lastStepMs: ms) }

    /// An automatic start: steps must run continuously for 27 s within the next minute.
    public static func confirming(at ms: Int64) -> WalkTracker {
        WalkTracker(phase: .confirming(deadlineMs: ms + WalkRules.confirmDeadlineMs), startMs: ms, lastStepMs: 0)
    }

    private init(phase: Phase, startMs: Int64, lastStepMs: Int64) {
        self.phase = phase
        self.startMs = startMs
        self.lastStepMs = lastStepMs
    }

    /// The pedometer reported `added` new steps at `ms`. CMPedometer batches its updates, so a long gap that brought
    /// at least one step per second of gap is still continuous walking; a gap with few steps breaks it.
    public mutating func steps(at ms: Int64, added: Int64 = 1) {
        let gap = ms - lastStepMs
        let continuous = gap <= WalkRules.continuityGapMs || added * 1000 >= gap
        if walkingSinceMs == nil || !continuous { walkingSinceMs = ms }
        lastStepMs = ms
    }

    /// Continuous walking so far. Unlike Android, stopping resets it: 10 s of steps then standing still never confirms.
    public func walkingForMs(now: Int64) -> Int64 {
        guard let since = walkingSinceMs, now - lastStepMs <= WalkRules.continuityGapMs else { return 0 }
        return now - since
    }

    public func idleMs(now: Int64) -> Int64 { max(now - lastStepMs, 0) }

    public mutating func tick(now: Int64) -> Event? {
        switch phase {
        case .ended:
            return nil
        case .confirming(let deadline):
            if walkingForMs(now: now) >= WalkRules.confirmMs {
                phase = .walking
                startMs = walkingSinceMs ?? now   // the walk began when the continuous steps did
                return .started
            }
            if now >= deadline {
                phase = .ended
                return .abandoned
            }
            return nil
        case .walking:
            let idle = idleMs(now: now)
            if idle >= WalkRules.endMs {
                phase = .ended
                return .ended
            }
            if idle >= WalkRules.redLightMs && !redLightShown {
                redLightShown = true
                return .redLight
            }
            if idle < WalkRules.pauseMs && redLightShown {
                redLightShown = false
                return .resumed
            }
            return nil
        }
    }

    /// Steps walked since the start, for the status line.
    public func status(now: Int64, mode: WalkMode, steps: Int64, gps: Bool) -> WalkStatus {
        switch phase {
        case .ended: return .idle
        case .confirming: return .confirming(walkingForMs: walkingForMs(now: now))
        case .walking:
            let idle = idleMs(now: now)
            return idle >= WalkRules.pauseMs ? .paused(mode: mode, startedMs: startMs, steps: steps, idleMs: idle)
                : .walking(mode: mode, startedMs: startMs, steps: steps, gps: gps)
        }
    }
}

/// One CoreMotion activity reading: it holds from `startMs` until the next sample.
public struct ActivitySample: Sendable {
    public let startMs: Int64
    public let onFoot: Bool       // walking or running
    public let automotive: Bool
    public let confident: Bool    // medium or high confidence

    public init(startMs: Int64, onFoot: Bool, automotive: Bool, confident: Bool) {
        self.startMs = startMs
        self.onFoot = onFoot
        self.automotive = automotive
        self.confident = confident
    }
}

public struct Stretch: Equatable, Sendable {
    public let startMs: Int64
    public let endMs: Int64

    public init(startMs: Int64, endMs: Int64) {
        self.startMs = startMs
        self.endMs = endMs
    }

    public var durationMs: Int64 { endMs - startMs }
}

/// A walk already on record, for deciding what a retroactive stretch adds.
public struct WalkRow: Equatable, Sendable {
    public let id: Int64
    public let startMs: Int64
    public let endMs: Int64?
    public let retro: Bool

    public init(id: Int64, startMs: Int64, endMs: Int64?, retro: Bool) {
        self.id = id
        self.startMs = startMs
        self.endMs = endMs
        self.retro = retro
    }
}

/// Retroactive walks (handoff §6): iOS can't wake a suspended app on motion, so on each foreground and background
/// refresh the app reads CoreMotion's activity history and applies the same 27 s / 4.5 min rules after the fact.
/// These walks earn the sensor tier: no GPS, and Tor wasn't up.
public enum RetroWalks {
    public enum Action: Equatable, Sendable {
        case create(Stretch)
        /// Walking resumed within 4.5 min of a recorded walk: the same walk, from its old end to the new one.
        case extend(walkId: Int64, from: Int64, to: Int64)
    }

    /// Walks in `samples` (sorted; the last lasts until `untilMs`) that have ended, by the live rules: a walk starts
    /// only with one on-foot segment of 27 s or more (Android: 27 s of continuous steps), then any on-foot reading less
    /// than 4.5 min after the last keeps it going, as a red light doesn't end a live walk. Short bursts on their own
    /// (moving around a room) never start one. A walk still going at `untilMs` is left to the live walk.
    public static func stretches(_ samples: [ActivitySample], untilMs: Int64) -> [Stretch] {
        var walks: [Stretch] = []
        var open: Stretch?
        for (i, s) in samples.enumerated() where s.onFoot && !s.automotive && s.confident {
            let end = i + 1 < samples.count ? samples[i + 1].startMs : untilMs
            guard end > s.startMs else { continue }
            if let o = open, s.startMs - o.endMs < WalkRules.endMs {
                open = Stretch(startMs: o.startMs, endMs: max(o.endMs, end))
                continue
            }
            if let o = open { walks.append(o) }
            open = end - s.startMs >= WalkRules.confirmMs ? Stretch(startMs: s.startMs, endMs: end) : nil
        }
        if let o = open { walks.append(o) }
        return walks.filter { $0.endMs < untilMs }
    }

    /// What to record for one stretch, given the walks already on record. Recording as soon as a stretch ends
    /// (instead of 4.5 min later) matters on iOS: anything not yet a walk syncs as passive and can't be re-labelled.
    public static func plan(_ s: Stretch, existing: [WalkRow]) -> Action? {
        // Live walks own their time; never add history on top of them.
        if existing.contains(where: { !$0.retro && $0.startMs < s.endMs && ($0.endMs ?? .max) > s.startMs }) { return nil }
        // The latest retro walk that this stretch overlaps or follows within 4.5 min.
        if let w = existing.filter({ $0.retro && $0.startMs < s.endMs && ($0.endMs ?? .max) + WalkRules.endMs > s.startMs })
            .max(by: { $0.startMs < $1.startMs }) {
            let end = w.endMs ?? w.startMs
            return s.endMs > end ? .extend(walkId: w.id, from: end, to: s.endMs) : nil
        }
        return s.durationMs >= WalkRules.confirmMs ? .create(s) : nil
    }

    /// Splits steps over [start, end] across the local days it covers, in proportion to time (as Android's
    /// StepCounterReader.splitAtMidnight): the pedometer can't say when each step happened.
    public static func splitByDay(startMs: Int64, endMs: Int64, steps: Int64, days: LocalDays = LocalDays())
        -> [(day: String, startMs: Int64, endMs: Int64, steps: Int64)] {
        var cuts = [startMs]
        var d = days.calendar.startOfDay(for: Date(timeIntervalSince1970: Double(startMs) / 1000))
        while let next = days.calendar.date(byAdding: .day, value: 1, to: d) {
            let m = Int64(next.timeIntervalSince1970 * 1000)
            if m >= endMs { break }
            cuts.append(m)
            d = next
        }
        cuts.append(endMs)
        let span = max(endMs - startMs, 1)
        var left = steps
        var out: [(String, Int64, Int64, Int64)] = []
        for i in 0..<(cuts.count - 1) {
            let n = i == cuts.count - 2 ? left : steps * (cuts[i + 1] - cuts[i]) / span
            left -= n
            if n > 0 { out.append((days.day(Date(timeIntervalSince1970: Double(cuts[i]) / 1000)), cuts[i], cuts[i + 1], n)) }
        }
        return out
    }
}
