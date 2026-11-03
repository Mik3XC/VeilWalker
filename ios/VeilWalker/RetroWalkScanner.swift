import CoreMotion
import Foundation
import VeilWalkerCore

/// Rebuilds walks the app wasn't open for, from CoreMotion's 7-day activity history plus CMPedometer counts
/// (handoff §6, "Retroactive walks"). Runs on every foreground before syncing, so walk steps are claimed before the
/// day's total goes up as passive. Sensor tier only: there was no GPS and no Tor.
struct RetroWalkScanner {
    let store: Store
    private let activity = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private let days = LocalDays()

    init(store: Store) {
        self.store = store
    }

    /// Returns how many walks were created or extended.
    @discardableResult
    func scan(now: Date = Date()) async -> Int {
        guard CMMotionActivityManager.isActivityAvailable(), CMPedometer.isStepCountingAvailable() else { return 0 }
        let from = days.calendar.date(byAdding: .day, value: -7, to: now)!
        guard let samples = await activities(from: from, to: now) else { return 0 }
        let nowMs = WalkController.now()
        var rejected = rejectedStarts(since: nowMs - 8 * 86_400_000)
        defer { saveRejected(rejected) }
        var changed = 0
        for s in RetroWalks.stretches(samples, untilMs: nowMs) {
            guard let existing = try? store.walks(from: s.startMs - WalkRules.endMs, to: s.endMs + WalkRules.endMs),
                  let action = RetroWalks.plan(s, existing: existing) else { continue }
            switch action {
            case .create(let s):
                guard !rejected.contains(s.startMs) else { continue }
                guard await confirmed(s) else {
                    rejected.insert(s.startMs)
                    continue
                }
                guard let steps = await steps(from: s.startMs, to: s.endMs), steps > 0,
                      let id = try? store.insertWalk(mode: .active, startMs: s.startMs, retro: true) else { continue }
                let verdict = cadenceVerdict(steps: steps, durationMs: s.durationMs)
                record(walkId: id, from: s.startMs, to: s.endMs, steps: steps, verdict: verdict)
                try? store.updateWalk(id: id, steps: steps, distanceM: 0, verdict: verdict, torUsed: false)
                try? store.endWalk(id: id, endMs: s.endMs)
            case .extend(let id, let a, let b):
                guard let steps = await steps(from: a, to: b), steps > 0 else { continue }
                record(walkId: id, from: a, to: b, steps: steps, verdict: cadenceVerdict(steps: steps, durationMs: b - a))
                try? store.extendWalk(id: id, steps: steps, endMs: b)
            }
            changed += 1
        }
        return changed
    }

    /// The 27 s rule, checked against the pedometer: one 30 s slice (stepping by 15 s) in the first 3 minutes with
    /// 1+ step per second. CoreMotion's "walking" label alone also covers moving around a room.
    private func confirmed(_ s: Stretch) async -> Bool {
        var t = s.startMs
        let limit = min(s.endMs, s.startMs + WalkRules.retroConfirmSpanMs)
        while t + WalkRules.retroSliceMs <= limit {
            if let n = await steps(from: t, to: t + WalkRules.retroSliceMs), n >= WalkRules.retroConfirmSteps { return true }
            t += WalkRules.retroSliceMs / 2
        }
        return false
    }

    /// Stretches already checked and turned down, so each launch doesn't query them again.
    private func rejectedStarts(since: Int64) -> Set<Int64> {
        let all = (try? store.meta("retroRejected"))??.split(separator: ",").compactMap { Int64($0) } ?? []
        return Set(all.filter { $0 >= since })
    }

    private func saveRejected(_ starts: Set<Int64>) {
        try? store.setMeta("retroRejected", starts.sorted().map(String.init).joined(separator: ","))
    }

    /// Without motion samples only the cadence check applies (over 3.2 steps/s is a shaker, not a walk).
    private func cadenceVerdict(steps: Int64, durationMs: Int64) -> Float {
        WalkVerifier().score(SensorWindow(steps: Int(min(steps, Int64(Int.max))), durationS: Double(durationMs) / 1000), gps: nil).score
    }

    private func record(walkId: Int64, from: Int64, to: Int64, steps: Int64, verdict: Float) {
        for part in RetroWalks.splitByDay(startMs: from, endMs: to, steps: steps, days: days) {
            _ = try? store.recordWalkSteps(StepInterval(day: part.day, startMs: part.startMs, endMs: part.endMs, steps: part.steps,
                                                    source: .activeSensor, walkId: walkId, verdict: verdict))
        }
    }

    private func activities(from: Date, to: Date) async -> [ActivitySample]? {
        await withCheckedContinuation { c in
            activity.queryActivityStarting(from: from, to: to, to: OperationQueue()) { list, _ in
                c.resume(returning: list?.map {
                    ActivitySample(startMs: Int64($0.startDate.timeIntervalSince1970 * 1000), onFoot: $0.walking || $0.running,
                                   automotive: $0.automotive, confident: $0.confidence != .low)
                })
            }
        }
    }

    private func steps(from: Int64, to: Int64) async -> Int64? {
        await withCheckedContinuation { c in
            pedometer.queryPedometerData(from: WalkController.date(from), to: WalkController.date(to)) { data, _ in
                c.resume(returning: data?.numberOfSteps.int64Value)
            }
        }
    }
}
