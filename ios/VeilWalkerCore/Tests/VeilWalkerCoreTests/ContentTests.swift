import Foundation
import XCTest
@testable import VeilWalkerCore

/// Ports of Android's AchievementsTest and RouteTest, plus checks on the exported content and the stats charts.
final class ContentTests: XCTestCase {
    private let rules = AchievementRules.shared
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let today = "2026-10-27"

    // MARK: AchievementsTest.kt

    func testRulesExpandToUniqueIds() {
        XCTAssertEqual(rules.count, 91)   // the handoff's badge count
        XCTAssertEqual(rules.count, Set(rules.map(\.id)).count)
        // Every family's names line up with its tiers (no fallback names leaking through).
        XCTAssertTrue(rules.allSatisfy { !($0.name.contains("_") && $0.name.hasSuffix(String($0.threshold))) })
        XCTAssertTrue(rules.allSatisfy { !$0.name.hasPrefix("\($0.family) ") })
    }

    func testDescriptionsUseCompactNumbers() {
        XCTAssertEqual(rules.first { $0.id == "steps_10000" }?.description, "Walk 10K steps, all time")
        XCTAssertEqual(rules.first { $0.id == "longest_21097" }?.description, "Walk 21,097 m in a single walk")
        XCTAssertEqual(rules.first { $0.id == "steps_1000" }?.description, "Walk 1,000 steps, all time")
        XCTAssertEqual(rules.first { $0.id == "steps_2500000" }?.description, "Walk 2.5M steps, all time")
        XCTAssertEqual(rules.first { $0.id == "crowley_8611" }?.description, "Summit K2, the Savage Mountain: 8,611 m of freezing climb")
    }

    func testTodaysRealDataUnlocksTheRightBadges() {
        // The S26 Edge history: 1,824 steps today, walks of 31 / 1,043 / 750 steps, the last one an Onion Walk.
        let start = Int64(utc.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 18))!.timeIntervalSince1970 * 1000)
        func walk(_ steps: Int64, _ m: Double, onion: Bool) -> WalkFacts {
            WalkFacts(startMs: start, endMs: 1, steps: steps, distanceM: m, onion: onion, torUsed: onion)
        }
        let metrics = Metrics.compute(
            days: [DayCount(day: "2026-10-27", steps: 1824)],
            walks: [walk(31, 18.7, onion: false), walk(1043, 806.3, onion: false), walk(750, 513.2, onion: true)],
            onionSteps: 750, postcards: 1, today: today, calendar: utc
        )
        let ids = Set(AchievementRules.unlocked(rules, metrics: metrics).map(\.id))
        XCTAssertEqual(ids, ["steps_1000", "walks_1", "onion_1", "postcards_1"])
    }

    func testStreakCountsBackFromTodayOrYesterday() {
        let days = ["2026-10-24", "2026-10-25", "2026-10-26"].map { DayCount(day: $0, steps: 5000) }
        XCTAssertEqual(Metrics.streak(days, today: today, calendar: utc), 3)   // today not walked yet: still alive
        XCTAssertEqual(Metrics.streak(days + [DayCount(day: "2026-10-27", steps: 3000)], today: today, calendar: utc), 4)
        XCTAssertEqual(Metrics.streak(Array(days.dropLast()), today: today, calendar: utc), 0)   // missed yesterday: broken
        // Across a month boundary.
        let edge = ["2026-09-30", "2026-10-01"].map { DayCount(day: $0, steps: 4000) }
        XCTAssertEqual(Metrics.streak(edge, today: "2026-10-01", calendar: utc), 2)
    }

    func testSecretDaysOnlyCountFinishedDays() {
        let m = Metrics.compute(days: [DayCount(day: "2026-10-27", steps: 1337)], walks: [], onionSteps: 0, postcards: 0,
                                today: today, calendar: utc)
        XCTAssertEqual(m["leet_days"], 0)
        let m2 = Metrics.compute(days: [DayCount(day: "2026-10-26", steps: 1337), DayCount(day: "2026-10-25", steps: 12321)],
                                 walks: [], onionSteps: 0, postcards: 0, today: today, calendar: utc)
        XCTAssertEqual(m2["leet_days"], 1)
        XCTAssertEqual(m2["palindrome_days"], 1)
    }

    func testFrostTiersDecorateFrames() {
        XCTAssertEqual(Frost.of(minutes: 9), .none)
        XCTAssertEqual(Frost.of(minutes: 0).apply("(>>)"), "(>>)")
        XCTAssertEqual(Frost.of(minutes: 10).apply("(>>)"), "*(>>)")
        XCTAssertEqual(Frost.of(minutes: 100).apply("[>>]"), "*[>>]*")
        XCTAssertEqual(Frost.of(minutes: 5000).apply("{>>}"), "**{>>}**")
    }

    func testRankThresholds() {
        XCTAssertEqual(Rank.of(unlockedCount: 4), .none)
        XCTAssertEqual(Rank.of(unlockedCount: 5), .bronze)
        XCTAssertEqual(Rank.of(unlockedCount: 30), .gold)
        XCTAssertNotEqual(Rank.of(unlockedCount: 49), .platinum)
    }

    func testOutlawRankLadder() {
        let board = { (unlocked: [String]) in
            BadgeBoard(all: self.rules, unlockedAt: Dictionary(uniqueKeysWithValues: unlocked.map { ($0, 1) }))
        }
        XCTAssertEqual(board([]).outlawRank, "LANDLUBBER")
        XCTAssertEqual(board([]).nextOutlaw?.name, "Stowaway")
        XCTAssertEqual(board(["outlaw_10000", "outlaw_50000"]).outlawRank, "FOOTPAD")
        XCTAssertEqual(board(["outlaw_10000", "steps_1000"]).summary, "2/91")
    }

    /// This iPhone's first real sync (Oct 24–30, 2026): 40,081 steps, best day 16,553.
    func testFirstIPhoneWeek() {
        let days = [3638, 2965, 3840, 4036, 16553, 5795, 3254].enumerated().map {
            DayCount(day: String(format: "2026-10-%02d", 24 + $0.offset), steps: Int64($0.element))
        }
        let m = Metrics.compute(days: days, walks: [], onionSteps: 0, postcards: 1, today: "2026-10-30", calendar: utc)
        XCTAssertEqual(m["lifetime_steps"], 40_081)
        XCTAssertEqual(m["streak_days"], 5)   // Oct 25 had 2,965 steps, under the 3,000 streak line
        let ids = Set(AchievementRules.unlocked(rules, metrics: m).map(\.id))
        XCTAssertEqual(ids, ["steps_1000", "steps_10000", "outlaw_10000", "best_day_5000", "best_day_10000", "best_day_15000",
                             "streak_3", "postcards_1"])
    }

    // MARK: RouteTest.kt

    private var northStar: Route { ContentLibrary.shared.active.route! }

    func testRouteLengthIsPlausible() {
        XCTAssertTrue((150_000.0...260_000.0).contains(northStar.lengthM), "length \(northStar.lengthM)")
    }

    func testStartUnlocksFirstPostcardOnly() {
        let p = northStar.positionAt(0)
        XCTAssertEqual(p.unlocked.count, 1)
        XCTAssertEqual(p.next?.name, "Cambridge, Maryland")
    }

    func testReachingAMilestoneUnlocksIt() {
        let atThird = northStar.cumulativeM[2]
        XCTAssertEqual(northStar.positionAt(atThird).unlocked.count, 3)
        XCTAssertEqual(northStar.positionAt(atThird - 1).unlocked.count, 2)
    }

    func testPastTheEndIsFinished() {
        let p = northStar.positionAt(northStar.lengthM * 2)
        XCTAssertTrue(p.finished)
        XCTAssertEqual(p.unlocked.count, northStar.milestones.count)
        XCTAssertNil(p.next)
    }

    func testStrideNeedsEnoughGpsSteps() {
        XCTAssertEqual(Stride.from(distanceM: 100, steps: 100), 0.75)
        // From the S26 Edge test walks: 806 m / 1,043 steps
        XCTAssertEqual(Stride.from(distanceM: 806, steps: 1043), 0.773, accuracy: 0.001)
        XCTAssertEqual(Stride.from(distanceM: 5000, steps: 1000), 1.0)
    }

    // MARK: Exported content

    func testContentMatchesTheAndroidCatalogue() {
        let lib = ContentLibrary.shared
        XCTAssertEqual(lib.freedom.count, 20)
        XCTAssertEqual(lib.outlaws.count, 15)
        XCTAssertEqual(lib.peaks.count, 11)
        XCTAssertEqual(lib.all.filter { $0.route != nil }.map(\.id), ["north-star-1"])
        XCTAssertEqual(lib.active.postcards, 12)
        XCTAssertEqual(lib.locked.first?.title, "The North Star")
        XCTAssertEqual(lib.locked.first?.unlock, "finish North Star I")
        // Outlaw unlock text and km come from the step target, like Outlaws.kt.
        let capone = lib.journey(id: "outlaw-capone")!
        XCTAssertEqual(capone.card?.rarity, .boss)
        XCTAssertEqual(capone.unlock, "25,000,000 lifetime steps")
        XCTAssertEqual(capone.km, 18_750)
        XCTAssertEqual(lib.outlaws.first?.card?.collection, "OUTLAWS ON FOOT · Vol I: The Roads They Took")
        XCTAssertEqual(lib.peaks.filter(\.demon).map(\.id), ["k2"])
        XCTAssertTrue(lib.all.allSatisfy { !$0.facts.isEmpty && !$0.teaser.isEmpty })
    }

    // MARK: StepChart (StatsScreen.kt)

    func testCharts() {
        XCTAssertEqual(StepChart.spark([Bucket("a", 0), Bucket("b", 5), Bucket("c", 10)]), " ▄█")
        let bars = StepChart.bars([Bucket("Mon", 5000), Bucket("Tue", 12000)], width: 12, goal: 10_000)
        XCTAssertEqual(bars, ["Mon #####.....|. 5,000", "Tue ############ 12,000"])
        let km = StepChart.bars([Bucket("2026", 40_081)], width: 4, goal: nil, strideM: 0.75)
        XCTAssertEqual(km, ["2026 #### 40,081 30.1km"])

        let now = utc.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))!
        let days = [DayCount(day: "2026-10-28", steps: 16553), DayCount(day: "2026-10-30", steps: 3254)]
        XCTAssertEqual(StepChart.lastDays(days, 7, today: now, calendar: utc).map(\.label), ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"])
        XCTAssertEqual(StepChart.lastDays(days, 7, today: now, calendar: utc).map(\.steps), [0, 0, 0, 0, 16553, 0, 3254])
        XCTAssertEqual(StepChart.months(days, today: now, calendar: utc).last, Bucket("Oct", 19807))
        XCTAssertEqual(StepChart.years([], today: now, calendar: utc), [Bucket("2026", 0)])
    }

    func testAsciiBar() {
        XCTAssertEqual(Ascii.bar(0, width: 10), "[..........] 0.0%")
        XCTAssertEqual(Ascii.bar(0.001, width: 10), "[#.........] 0.1%")
        XCTAssertEqual(Ascii.bar(0.42, width: 10), "[####......] 42.0%")
        XCTAssertEqual(Ascii.barOnly(2, width: 4), "[####]")
        XCTAssertEqual(Fmt.grouped(Int64(1_234_567)), "1,234,567")
        XCTAssertEqual(Fmt.grouped(Int64(999)), "999")
    }

    // MARK: Store

    func testBadgeUnlocksKeepTheFirstTime() throws {
        let store = try Store()
        try store.unlock(["steps_1000"], at: 100)
        try store.unlock(["steps_1000", "streak_3"], at: 200)
        XCTAssertEqual(try store.unlocks(), ["steps_1000": 100, "streak_3": 200])
    }

    func testDailyCountsUsePedometerTotals() throws {
        let store = try Store()
        try store.setPedometer(day: "2026-10-29", steps: 5795)
        try store.setPedometer(day: "2026-10-30", steps: 3254)
        try store.insert(StepInterval(day: "2026-10-30", startMs: 0, endMs: 1, steps: 400, source: .onion))
        XCTAssertEqual(try store.dailyCounts(), [DayCount(day: "2026-10-29", steps: 5795), DayCount(day: "2026-10-30", steps: 3254)])
        XCTAssertEqual(try store.onionSteps(), 400)
    }
}
