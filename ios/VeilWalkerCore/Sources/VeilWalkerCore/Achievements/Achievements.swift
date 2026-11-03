import Foundation

/// One badge, expanded from a family tier. `id` is stable (family_threshold) and is what gets stored.
public struct Achievement: Identifiable, Equatable, Sendable {
    public let id: String
    public let family: String
    public let name: String
    public let glyph: String
    public let metric: String
    public let threshold: Int64
    public let description: String
    public let secret: Bool
}

/// Rules live in Resources/achievements.json (a byte-identical copy of Android's asset) as families of tiers:
/// {"id","glyph","metric","tiers":[...],"names":[...],"desc":"... {n} ...","secret"?,"format"?}.
/// Mirrors core/achievements Achievements.kt.
public enum AchievementRules {

    public static let shared: [Achievement] = {
        guard let url = Bundle.module.url(forResource: "achievements", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rules = try? parse(data) else {
            preconditionFailure("achievements.json missing or invalid")
        }
        return rules
    }()

    public static func parse(_ json: Data) throws -> [Achievement] {
        struct Family: Decodable {
            let id: String
            let glyph: String
            let metric: String
            let tiers: [Int64]
            let names: [String]?
            let desc: String
            let secret: Bool?
            let format: String?
        }
        struct Doc: Decodable { let families: [Family] }
        return try JSONDecoder().decode(Doc.self, from: json).families.flatMap { f in
            f.tiers.enumerated().map { t, n in
                let name = f.names.flatMap { t < $0.count && !$0[t].isEmpty ? $0[t] : nil } ?? "\(f.id) \(n)"
                return Achievement(
                    id: "\(f.id)_\(n)", family: f.id, name: name, glyph: f.glyph, metric: f.metric, threshold: n,
                    description: f.desc.replacingOccurrences(of: "{n}", with: f.format == "raw" ? Fmt.grouped(n) : compact(n)),
                    secret: f.secret ?? false
                )
            }
        }
    }

    /// 1,000 → 1,000; 10,000 → 10K; 2,500,000 → 2.5M.
    public static func compact(_ n: Int64) -> String {
        func trim(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(v)) : Fmt.fixed(v, 1) }
        if n >= 1_000_000 { return trim(Double(n) / 1_000_000) + "M" }
        if n >= 10_000 { return trim(Double(n) / 1_000) + "K" }
        return Fmt.grouped(n)
    }

    /// Every achievement whose metric has reached its threshold. Unknown metrics never unlock anything.
    public static func unlocked(_ all: [Achievement], metrics: [String: Int64]) -> [Achievement] {
        all.filter { (metrics[$0.metric] ?? 0) >= $0.threshold }
    }
}

/// Snowflake status: minutes hosting a Snowflake proxy while walking frost every badge frame. Status only, never points.
/// (Snowflake isn't in iOS v1, so this stays NONE for now; kept for parity and restored accounts.)
public enum Frost: CaseIterable, Sendable {
    case none, frost, ice, glacier, aurora

    public var title: String { ["NONE", "FROST", "ICE", "GLACIER", "AURORA"][index] }
    public var minMinutes: Int64 { [0, 10, 100, 1000, 5000][index] }
    private var index: Int { Self.allCases.firstIndex(of: self)! }
    private var sides: (String, String) { [("", ""), ("*", ""), ("*", "*"), ("**", "*"), ("**", "**")][index] }

    public func apply(_ frame: String) -> String { sides.0 + frame + sides.1 }

    public static func of(minutes: Int64) -> Frost { allCases.last { minutes >= $0.minMinutes }! }
}

/// Rank from how many badges are unlocked: the frame every badge is shown in.
public enum Rank: CaseIterable, Sendable {
    case none, bronze, silver, gold, platinum

    public var title: String { ["UNRANKED", "BRONZE", "SILVER", "GOLD", "PLATINUM"][index] }
    public var minBadges: Int { [0, 5, 15, 30, 50][index] }
    private var index: Int { Self.allCases.firstIndex(of: self)! }

    public static func of(unlockedCount: Int) -> Rank { allCases.last { unlockedCount >= $0.minBadges }! }

    /// The rank frame drawn around a badge glyph: the more you've unlocked, the heavier the brackets.
    public func frame(_ glyph: String) -> String {
        switch self {
        case .none: " \(glyph) "
        case .bronze: "(\(glyph))"
        case .silver: "[\(glyph)]"
        case .gold: "{\(glyph)}"
        case .platinum: "<<\(glyph)>>"
        }
    }
}

public struct BadgeBoard: Sendable {
    public let all: [Achievement]
    /// achievement id → first unlock time (epoch ms). Unlocks are permanent.
    public let unlockedAt: [String: Int64]
    public let snowflakeMinutes: Int64

    public init(all: [Achievement], unlockedAt: [String: Int64], snowflakeMinutes: Int64 = 0) {
        self.all = all
        self.unlockedAt = unlockedAt
        self.snowflakeMinutes = snowflakeMinutes
    }

    public static let outlawFamily = "outlaw"

    public var frost: Frost { .of(minutes: snowflakeMinutes) }
    public var unlockedCount: Int { all.filter { unlockedAt[$0.id] != nil }.count }
    public var rank: Rank { .of(unlockedCount: unlockedCount) }

    private var outlawLadder: [Achievement] { all.filter { $0.family == Self.outlawFamily } }
    /// Smuggler grade from the outlaw ladder: STOWAWAY up to KINGPIN. Everyone starts a landlubber.
    public var outlawRank: String { outlawLadder.last { unlockedAt[$0.id] != nil }?.name.uppercased() ?? "LANDLUBBER" }
    public var nextOutlaw: Achievement? { outlawLadder.first { unlockedAt[$0.id] == nil } }

    /// "4/91 · FROST" for the home screen's badges link.
    public var summary: String {
        "\(unlockedCount)/\(all.count)" + (frost == .none ? "" : " · \(frost.title)")
    }
}
