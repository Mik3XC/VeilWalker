import Foundation

/// Calendar helpers. Days are ISO local dates ("2026-10-30"), as on Android.
public struct LocalDays: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public func start(of day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// `count` days ending today, oldest first.
    public func lastDays(_ count: Int, now: Date) -> [String] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map(day)
    }
}

/// The phone's own step count per day. CMPedometer on iOS; a fake in tests.
public protocol StepHistory: Sendable {
    /// Steps per day for the given ISO days. Days the source can't answer are left out.
    func dailySteps(days: [String], now: Date) async throws -> [String: Int64]
}

#if os(iOS)
import CoreMotion

/// CMPedometer keeps 7 days of history even when the app wasn't running, so no reboot handling and
/// no midnight-split hack (Android's TYPE_STEP_COUNTER needs both). Querying asks for Motion permission.
public final class PedometerStepHistory: StepHistory, @unchecked Sendable {
    private let pedometer = CMPedometer()
    private let days: LocalDays

    public init(days: LocalDays = LocalDays()) {
        self.days = days
    }

    public static var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    public func dailySteps(days list: [String], now: Date) async throws -> [String: Int64] {
        guard Self.isAvailable else { return [:] }
        var out: [String: Int64] = [:]
        for day in list {
            guard let start = days.start(of: day), start <= now,
                  let next = days.calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            out[day] = try await steps(from: start, to: min(next, now))
        }
        return out
    }

    /// Live step counts since `start` while the app is in the foreground (CMPedometer pushes every few seconds).
    public func startLiveUpdates(from start: Date, handler: @escaping @Sendable (Int64) -> Void) {
        guard Self.isAvailable else { return }
        pedometer.startUpdates(from: start) { data, _ in
            if let n = data?.numberOfSteps.int64Value { handler(n) }
        }
    }

    public func stopLiveUpdates() {
        pedometer.stopUpdates()
    }

    /// Today's (or another recent day's) steps per hour, 24 entries; future hours are 0.
    public func hourlySteps(day: String, now: Date) async throws -> [Int64] {
        guard Self.isAvailable, let start = days.start(of: day) else { return Array(repeating: 0, count: 24) }
        var out: [Int64] = []
        for h in 0..<24 {
            guard let from = days.calendar.date(byAdding: .hour, value: h, to: start),
                  let to = days.calendar.date(byAdding: .hour, value: h + 1, to: start), from < now else {
                out.append(0)
                continue
            }
            out.append(try await steps(from: from, to: min(to, now)))
        }
        return out
    }

    private func steps(from start: Date, to end: Date) async throws -> Int64 {
        try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data?.numberOfSteps.int64Value ?? 0)
                }
            }
        }
    }
}
#endif
