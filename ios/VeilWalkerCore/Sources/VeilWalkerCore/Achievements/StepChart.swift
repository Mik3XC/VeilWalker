import Foundation

/// One labelled bucket of a stats chart.
public struct Bucket: Equatable, Sendable {
    public let label: String
    public let steps: Int64

    public init(_ label: String, _ steps: Int64) {
        self.label = label
        self.steps = steps
    }
}

/// Text charts for the stats screen: block sparklines and `#`-bars. Mirrors StepChart in StatsScreen.kt.
public enum StepChart {
    public static let goal: Int64 = 10_000
    private static let blocks = Array(" ▁▂▃▄▅▆▇█")
    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// 24 buckets labelled "00".."23". iOS reads these straight from CMPedometer, so they're true counts.
    public static func hourly(_ byHour: [Int64]) -> [Bucket] {
        (0..<24).map { Bucket(String(format: "%02d", $0), $0 < byHour.count ? byHour[$0] : 0) }
    }

    /// The last `n` days ending `today`: weekday labels for a week, day-of-month otherwise.
    public static func lastDays(_ days: [DayCount], _ n: Int, today: Date, calendar: Calendar = .current) -> [Bucket] {
        let local = LocalDays(calendar: calendar)
        let map = Dictionary(days.map { ($0.day, $0.steps) }, uniquingKeysWith: +)
        return local.lastDays(n, now: today).map { day in
            let d = local.start(of: day)!
            let label = n <= 7 ? weekdays[calendar.component(.weekday, from: d) - 1] : String(calendar.component(.day, from: d))
            return Bucket(label, map[day] ?? 0)
        }
    }

    /// The 12 months ending this one.
    public static func months(_ days: [DayCount], today: Date, calendar: Calendar = .current) -> [Bucket] {
        (0..<12).reversed().map { back in
            let m = calendar.date(byAdding: .month, value: -back, to: today)!
            let c = calendar.dateComponents([.year, .month], from: m)
            let key = String(format: "%04d-%02d", c.year!, c.month!)
            return Bucket(months[c.month! - 1], days.filter { $0.day.hasPrefix(key) }.reduce(0) { $0 + $1.steps })
        }
    }

    public static func years(_ days: [DayCount], today: Date, calendar: Calendar = .current) -> [Bucket] {
        let byYear = Dictionary(grouping: days) { String($0.day.prefix(4)) }
        if byYear.isEmpty { return [Bucket(String(calendar.component(.year, from: today)), 0)] }
        return byYear.keys.sorted().map { y in Bucket(y, byYear[y]!.reduce(0) { $0 + $1.steps }) }
    }

    /// Vertical sparkline: one block character per bucket, scaled to the busiest one.
    public static func spark(_ b: [Bucket]) -> String {
        let max = Swift.max(b.map(\.steps).max() ?? 1, 1)
        return String(b.map { blocks[Int(min(Swift.max((($0.steps * 8 + max - 1) / max), 0), 8))] })
    }

    /// Horizontal bars with a '|' marking the goal where it fits on the scale, optionally with km.
    public static func bars(_ b: [Bucket], width: Int = 18, goal: Int64? = goal, strideM: Double? = nil) -> [String] {
        let max = Swift.max(b.map(\.steps).max() ?? 0, goal ?? 0, 1)
        let labelW = b.map(\.label.count).max() ?? 0
        return b.map { k in
            let filled = Int(k.steps * Int64(width) / max)
            let goalAt = goal.map { min(Swift.max(Int($0 * Int64(width) / max), 0), width - 1) }
            let bar = String((0..<width).map { i in i < filled ? "#" : i == goalAt ? "|" : "." })
            let label = k.label.padding(toLength: labelW, withPad: " ", startingAt: 0)
            return "\(label) \(bar) \(Fmt.grouped(k.steps))" + (strideM.map { " " + Fmt.fixed(Stride.km(k.steps, strideM: $0), 1) + "km" } ?? "")
        }
    }
}
