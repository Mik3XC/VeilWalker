import Foundation

/// A day's true step count (all tiers added up).
public struct DayCount: Equatable, Sendable {
    public let day: String
    public let steps: Int64

    public init(day: String, steps: Int64) {
        self.day = day
        self.steps = steps
    }
}

/// The parts of a finished walk that badges are written against. Walk records arrive with live and retroactive walks.
public struct WalkFacts: Sendable {
    public let startMs: Int64
    public let endMs: Int64?
    public let steps: Int64
    public let distanceM: Double
    public let onion: Bool
    public let torUsed: Bool
    public let snowflakeMinutes: Int64
    public let coldClimbM: Double

    public init(startMs: Int64, endMs: Int64?, steps: Int64, distanceM: Double, onion: Bool = false, torUsed: Bool = false,
                snowflakeMinutes: Int64 = 0, coldClimbM: Double = 0) {
        self.startMs = startMs
        self.endMs = endMs
        self.steps = steps
        self.distanceM = distanceM
        self.onion = onion
        self.torUsed = torUsed
        self.snowflakeMinutes = snowflakeMinutes
        self.coldClimbM = coldClimbM
    }
}

/// Turns the local history into the numbers badge rules are written against. Everything stays on the phone.
/// Mirrors core/achievements Metrics.kt.
public enum Metrics {
    public static let streakMinSteps: Int64 = 3_000

    public static func compute(days: [DayCount], walks: [WalkFacts], onionSteps: Int64, postcards: Int,
                               today: String, calendar: Calendar = .current) -> [String: Int64] {
        let done = walks.filter { $0.endMs != nil && $0.steps > 0 }
        func startHour(_ w: WalkFacts) -> Int {
            calendar.component(.hour, from: Date(timeIntervalSince1970: Double(w.startMs) / 1000))
        }
        let closed = days.filter { $0.day < today }   // exact-count badges only judge finished days
        func count(_ p: (WalkFacts) -> Bool) -> Int64 { Int64(done.filter(p).count) }

        return [
            "lifetime_steps": days.reduce(0) { $0 + $1.steps },
            "best_day_steps": days.map(\.steps).max() ?? 0,
            "streak_days": Int64(streak(days, today: today, calendar: calendar)),
            "walk_count": Int64(done.count),
            "onion_walk_count": count { $0.onion && $0.torUsed },
            "onion_steps": onionSteps,
            "snowflake_minutes": walks.reduce(0) { $0 + $1.snowflakeMinutes },
            "cold_climb_m": Int64(walks.reduce(0) { $0 + $1.coldClimbM }),
            "route_postcards": Int64(postcards),
            "longest_walk_m": done.map { Int64($0.distanceM) }.max() ?? 0,
            "dawn_walks": count { (4...6).contains(startHour($0)) },
            "night_walks": count { startHour($0) >= 22 || startHour($0) < 4 },
            "ghost_hour_walks": count { startHour($0) == 3 },
            "leet_days": Int64(closed.filter { $0.steps == 1337 }.count),
            "palindrome_days": Int64(closed.filter { $0.steps >= 10_000 && String($0.steps) == String(String($0.steps).reversed()) }.count),
        ]
    }

    /// Consecutive days at 3,000+ steps, ending today (or yesterday, so the streak isn't lost before today's walk).
    public static func streak(_ days: [DayCount], today: String, calendar: Calendar = .current) -> Int {
        let local = LocalDays(calendar: calendar)
        let good = Set(days.filter { $0.steps >= streakMinSteps }.map(\.day))
        guard var d = local.start(of: today) else { return 0 }
        if !good.contains(today) { d = calendar.date(byAdding: .day, value: -1, to: d)! }
        var n = 0
        while good.contains(local.day(d)) {
            n += 1
            d = calendar.date(byAdding: .day, value: -1, to: d)!
        }
        return n
    }
}
