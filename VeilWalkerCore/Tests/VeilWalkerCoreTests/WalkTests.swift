import Foundation
import XCTest
@testable import VeilWalkerCore

/// Ports of Android's WalkVerifierTest, plus the walk timers, retroactive walks, the GPS smoother and the
/// double-counting guard.
final class WalkTests: XCTestCase {

    /// Deterministic noise in [-scale/2, scale/2). Kotlin's Random isn't reproducible here; the thresholds don't need it.
    private func noisy(_ n: Int, _ scale: Float, _ seed: UInt64) -> [Float] {
        var x = seed &* 0x9E3779B97F4A7C15 | 1
        return (0..<n).map { _ in
            x ^= x << 13; x ^= x >> 7; x ^= x << 17
            return (Float(x % 10_000) / 10_000 - 0.5) * scale
        }
    }

    private func window(_ steps: Int, accelSeed: UInt64, gyro: (UInt64, UInt64, UInt64), singleAxis: Bool = false) -> SensorWindow {
        SensorWindow(steps: steps, durationS: 10, accelMagnitudes: noisy(200, 4, accelSeed).map { 9.8 + $0 },
                     gyroX: noisy(200, singleAxis ? 3 : 1, gyro.0),
                     gyroY: singleAxis ? Array(repeating: 0, count: 200) : noisy(200, 1, gyro.1),
                     gyroZ: singleAxis ? Array(repeating: 0, count: 200) : noisy(200, 1, gyro.2))
    }

    // MARK: WalkVerifierTest.kt

    func testRealisticWalkScoresHigh() {
        XCTAssertGreaterThan(WalkVerifier().score(window(19, accelSeed: 1, gyro: (2, 3, 4)), gps: GpsCheck(speedKmh: 5, isMock: false)).score, 0.9)
    }

    func testSingleAxisSwingIsFlagged() {
        XCTAssertTrue(WalkVerifier().score(window(20, accelSeed: 1, gyro: (2, 3, 4), singleAxis: true), gps: nil).flags.contains(.singleAxisRotation))
    }

    func testStoppingAtEndOfWalkIsNotPenalised() {
        XCTAssertFalse(WalkVerifier().score(window(2, accelSeed: 9, gyro: (10, 11, 12)), gps: nil).flags.contains(.cadenceOutOfBand))
    }

    func testSlowCrossingWindowIsNotPenalised() {
        XCTAssertTrue(WalkVerifier().score(window(9, accelSeed: 13, gyro: (14, 15, 16)), gps: GpsCheck(speedKmh: 3, isMock: false)).flags.isEmpty)
    }

    func testShakerCadenceIsFlagged() {
        XCTAssertTrue(WalkVerifier().score(window(45, accelSeed: 17, gyro: (18, 19, 20)), gps: nil).flags.contains(.cadenceOutOfBand))
    }

    func testDeadZoneIsNotPenalised() {
        XCTAssertTrue(WalkVerifier().score(window(18, accelSeed: 5, gyro: (6, 7, 8)), gps: GpsCheck(speedKmh: nil, isMock: false)).flags.isEmpty)
    }

    func testVehiclesAreVetoed() {
        let car = WalkVerifier().score(window(18, accelSeed: 5, gyro: (6, 7, 8)), gps: GpsCheck(speedKmh: 40, isMock: false))
        XCTAssertTrue(car.flags.contains(.vehicleSpeed))
        XCTAssertEqual(car.score, 0.4, accuracy: 0.001)
        let automotive = WalkVerifier().score(window(18, accelSeed: 5, gyro: (6, 7, 8)), gps: nil, automotive: true)
        XCTAssertEqual(automotive.flags, [.automotive])
        let mock = WalkVerifier().score(window(18, accelSeed: 5, gyro: (6, 7, 8)), gps: GpsCheck(speedKmh: 4, isMock: true))
        XCTAssertEqual(mock.score, 0)
    }

    // MARK: GpsSmoother

    func testGpsSmootherMeasuresWalkingSpeedAndDeadZones() {
        let g = GpsSmoother()
        XCTAssertNil(g.check(nowMs: 0).speedKmh)
        // 1.4 m/s north for 30 s, one fix every 5 s; a 200 m-accuracy fix in the middle is ignored.
        for i in 0...6 {
            g.add(Fix(epochMs: Int64(i) * 5000, lat: 47.6 + Double(i) * 7 / 111_195, lon: -122.3, accuracyM: 5, isMock: false))
        }
        g.add(Fix(epochMs: 31_000, lat: 48, lon: -122, accuracyM: 200, isMock: false))
        let speed = g.check(nowMs: 30_000).speedKmh!
        XCTAssertEqual(speed, 5.0, accuracy: 0.6)
        XCTAssertEqual(g.totalDistanceM, 42, accuracy: 6)
        // No fresh fixes: back to "unknown", never "cheating".
        XCTAssertNil(g.check(nowMs: 200_000).speedKmh)
    }

    // MARK: WalkTracker

    func testManualWalkPausesRedLightsAndEnds() {
        var t = WalkTracker.walking(at: 0)
        for s in stride(from: Int64(0), through: 60_000, by: 2_000) { t.steps(at: s) }
        XCTAssertNil(t.tick(now: 60_000))
        XCTAssertEqual(t.status(now: 60_000 + 47_000, mode: .onion, steps: 100, gps: true),
                       .paused(mode: .onion, startedMs: 0, steps: 100, idleMs: 47_000))
        XCTAssertEqual(t.tick(now: 60_000 + 180_000), .redLight)
        XCTAssertNil(t.tick(now: 60_000 + 181_000))
        t.steps(at: 245_000)
        XCTAssertEqual(t.tick(now: 246_000), .resumed)
        XCTAssertEqual(t.tick(now: 245_000 + 270_000), .ended)
        XCTAssertEqual(t.status(now: 600_000, mode: .active, steps: 0, gps: false), .idle)
    }

    func testAutoWalkNeeds27ContinuousSeconds() {
        var t = WalkTracker.confirming(at: 0)
        for s in stride(from: Int64(1_000), through: 26_000, by: 2_500) { t.steps(at: s) }
        XCTAssertNil(t.tick(now: 26_000))
        t.steps(at: 28_500)
        XCTAssertEqual(t.tick(now: 28_500), .started)
        XCTAssertEqual(t.startMs, 1_000)   // the walk began when the steps did
    }

    func testStoppingBeforeConfirmAbandons() {
        var t = WalkTracker.confirming(at: 0)
        for s in stride(from: Int64(0), through: 10_000, by: 2_000) { t.steps(at: s) }
        XCTAssertEqual(t.walkingForMs(now: 30_000), 0)   // standing still doesn't keep counting
        XCTAssertNil(t.tick(now: 30_000))
        XCTAssertEqual(t.tick(now: 60_000), .abandoned)
    }

    func testAGapRestartsTheConfirmTimer() {
        var t = WalkTracker.confirming(at: 0)
        for s in stride(from: Int64(0), through: 20_000, by: 2_000) { t.steps(at: s) }
        for s in stride(from: Int64(30_000), through: 50_000, by: 2_000) { t.steps(at: s) }   // 10 s gap
        XCTAssertEqual(t.walkingForMs(now: 50_000), 20_000)
        XCTAssertNil(t.tick(now: 50_000))
    }

    func testBatchedPedometerUpdatesStayContinuous() {
        var t = WalkTracker.confirming(at: 0)
        t.steps(at: 2_000, added: 3)
        t.steps(at: 12_000, added: 18)   // 10 s gap, but 18 steps came with it: still walking
        t.steps(at: 22_000, added: 17)
        t.steps(at: 30_000, added: 15)
        XCTAssertEqual(t.tick(now: 30_000), .started)
        var u = WalkTracker.confirming(at: 0)
        u.steps(at: 2_000, added: 3)
        u.steps(at: 22_000, added: 4)    // 20 s for 4 steps: a pause, not continuous
        XCTAssertEqual(u.walkingForMs(now: 22_000), 0)
    }

    func testWalkLines() {
        XCTAssertEqual(WalkStatus.idle.line(nowMs: 0), "walk: auto · 27 s of steps starts it")
        XCTAssertEqual(WalkStatus.confirming(walkingForMs: 12_400).line(nowMs: 0), "walk: detecting… 12/27 s")
        XCTAssertEqual(WalkStatus.walking(mode: .onion, startedMs: 0, steps: 812, gps: false).line(nowMs: 425_000),
                       "walk: 7:05 · 812 steps · no gps")
        XCTAssertEqual(WalkStatus.paused(mode: .active, startedMs: 0, steps: 1, idleMs: 65_000).line(nowMs: 0), "walk: paused 1:05")
        XCTAssertEqual(WalkStatus.paused(mode: .active, startedMs: 0, steps: 1, idleMs: 200_000).line(nowMs: 0),
                       "walk: red light? ends in 1:10")
    }

    // MARK: RetroWalks

    private func sample(_ s: Int64, _ foot: Bool, car: Bool = false, sure: Bool = true) -> ActivitySample {
        ActivitySample(startMs: s * 1000, onFoot: foot, automotive: car, confident: sure)
    }

    func testRetroStretchesFollowTheLiveRules() {
        let samples = [
            sample(0, false),
            sample(100, true), sample(400, false),     // 5 min walk
            sample(500, true), sample(700, false),     // 100 s later: same walk (a red light)
            sample(2000, true), sample(2020, false),   // 20 s on its own
            sample(3000, true, car: true), sample(3600, false),   // in a car
            sample(4000, true, sure: false), sample(4400, false), // low confidence
            sample(5000, true),                        // still going: the live walk's job
        ]
        XCTAssertEqual(RetroWalks.stretches(samples, untilMs: 5_100_000), [Stretch(startMs: 100_000, endMs: 700_000)])
    }

    func testShortBurstsNeverStartAWalk() {
        // Moving around a room: 15–20 s of steps every couple of minutes, all day. No walk.
        let puttering = stride(from: Int64(0), to: 3600, by: 120).flatMap { [sample($0, true), sample($0 + 20, false)] }
        XCTAssertEqual(RetroWalks.stretches(puttering, untilMs: 4_000_000), [])
        // The same bursts after a real 5 min walk keep that walk going (as a live walk would), then it ends.
        let afterWalk = [sample(0, true), sample(300, false)]
            + stride(from: Int64(400), to: 800, by: 120).flatMap { [sample($0, true), sample($0 + 20, false)] }
        XCTAssertEqual(RetroWalks.stretches(afterWalk, untilMs: 2_000_000), [Stretch(startMs: 0, endMs: 780_000)])
    }

    func testRetroPlanCreatesExtendsAndRespectsLiveWalks() {
        let walk = Stretch(startMs: 100_000, endMs: 700_000)
        XCTAssertEqual(RetroWalks.plan(walk, existing: []), .create(walk))
        XCTAssertNil(RetroWalks.plan(Stretch(startMs: 0, endMs: 20_000), existing: []))   // under 27 s
        // Already recorded: nothing new. Grew since: extend from the old end.
        let rec = WalkRow(id: 7, startMs: 100_000, endMs: 700_000, retro: true)
        XCTAssertNil(RetroWalks.plan(walk, existing: [rec]))
        XCTAssertEqual(RetroWalks.plan(Stretch(startMs: 100_000, endMs: 900_000), existing: [rec]),
                       .extend(walkId: 7, from: 700_000, to: 900_000))
        // A short burst 2 min after a recorded walk is that walk resuming, even under 27 s.
        XCTAssertEqual(RetroWalks.plan(Stretch(startMs: 820_000, endMs: 835_000), existing: [rec]),
                       .extend(walkId: 7, from: 700_000, to: 835_000))
        // Live walks own their time.
        let live = WalkRow(id: 8, startMs: 600_000, endMs: nil, retro: false)
        XCTAssertNil(RetroWalks.plan(Stretch(startMs: 650_000, endMs: 900_000), existing: [live]))
    }

    func testSplitAcrossMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let days = LocalDays(calendar: cal)
        let midnight = Int64(cal.date(from: DateComponents(year: 2026, month: 10, day: 31))!.timeIntervalSince1970 * 1000)
        let parts = RetroWalks.splitByDay(startMs: midnight - 600_000, endMs: midnight + 300_000, steps: 1500, days: days)
        XCTAssertEqual(parts.map(\.day), ["2026-10-30", "2026-10-31"])
        XCTAssertEqual(parts.map(\.steps), [1000, 500])
    }

    // MARK: Store

    func testWalkStepsNeverDoubleCountSyncedPassive() throws {
        let store = try Store()
        let day = "2026-10-30"
        try store.setPedometer(day: day, steps: 3254)
        try store.markSynced(DayTotals(day: day, passive: 3254, sensor: 0, gps: 0, onion: 0, verdict: 1))
        // A walk found afterwards inside steps already synced as passive gets nothing: they stay passive.
        let walk = try store.insertWalk(mode: .active, startMs: 0, retro: true)
        XCTAssertEqual(try store.recordWalkSteps(StepInterval(day: day, startMs: 0, endMs: 1, steps: 1000, source: .activeSensor, walkId: walk)), 0)
        XCTAssertEqual(try store.totals(day: day).total, 3254)
        // New steps after the sync can be walk steps.
        try store.setPedometer(day: day, steps: 4254)
        XCTAssertEqual(try store.recordWalkSteps(StepInterval(day: day, startMs: 2, endMs: 3, steps: 1500, source: .onion, walkId: walk)), 1000)
        let t = try store.totals(day: day)
        XCTAssertEqual([t.passive, t.onion, t.total], [3254, 1000, 4254])
    }

    func testWalkSessionsFeedBadgesAndStride() throws {
        let store = try Store()
        let w = try store.insertWalk(mode: .onion, startMs: 1_000)
        try store.updateWalk(id: w, steps: 1043, distanceM: 806, verdict: 0.95, torUsed: true)
        XCTAssertEqual(try store.strideM(), 0.75)   // still open: doesn't calibrate
        try store.endWalk(id: w, endMs: 600_000)
        XCTAssertEqual(try store.strideM(), 0.773, accuracy: 0.001)
        let facts = try store.walkFacts()
        XCTAssertEqual(facts.count, 1)
        XCTAssertTrue(facts[0].onion && facts[0].torUsed)
        XCTAssertTrue(try store.overlapsWalk(startMs: 500_000, endMs: 700_000))
        XCTAssertFalse(try store.overlapsWalk(startMs: 600_000, endMs: 700_000))
    }

    func testOpenWalksCloseAtTheirLastWindow() throws {
        let store = try Store()
        try store.setPedometer(day: "2026-10-30", steps: 500)
        let w = try store.insertWalk(mode: .active, startMs: 1_000)
        try store.recordWalkSteps(StepInterval(day: "2026-10-30", startMs: 1_000, endMs: 11_000, steps: 20, source: .activeGPS, walkId: w))
        try store.closeOpenWalks(nowMs: 99_000)
        XCTAssertEqual(try store.walkFacts().first?.endMs, 11_000)
    }
}

/// Weather and Hidden Peaks climb.
final class WeatherTests: XCTestCase {
    func testNWSLookupRoundsLocation() throws {
        XCTAssertEqual(NWS.pointsURL(lat: 47.6062, lon: -122.3321).absoluteString, "https://api.weather.gov/points/47.6,-122.3")
        let points = Data(#"{"properties":{"forecastHourly":"https://api.weather.gov/gridpoints/SEW/125,68/forecast/hourly"}}"#.utf8)
        XCTAssertEqual(try NWS.hourlyURL(fromPoints: points).path, "/gridpoints/SEW/125,68/forecast/hourly")
        // A response pointing anywhere else is refused (only api.weather.gov may be reached over Tor).
        let evil = Data(#"{"properties":{"forecastHourly":"https://example.com/x"}}"#.utf8)
        XCTAssertThrowsError(try NWS.hourlyURL(fromPoints: evil))
        XCTAssertEqual(try NWS.currentTempF(fromHourly: Data(#"{"properties":{"periods":[{"temperature":28,"temperatureUnit":"F"}]}}"#.utf8)), 28)
        XCTAssertEqual(try NWS.currentTempF(fromHourly: Data(#"{"properties":{"periods":[{"temperature":-2,"temperatureUnit":"C"}]}}"#.utf8)), 28)
    }

    func testFreezingCorner() {
        XCTAssertEqual(Weather(tempF: 52, fetchedAtMs: 0).label, "52°F")
        XCTAssertEqual(Weather(tempF: 30, fetchedAtMs: 0).label, "❄ 30°F")
        XCTAssertFalse(Weather(tempF: 31, fetchedAtMs: 0).freezing)
    }

    func testColdClimbOnlyCountsWhenFreezing() {
        var warm = ColdClimb()
        warm.steps(1000, freezing: false)
        XCTAssertEqual(warm.climbedM, 0)
        var cold = ColdClimb()
        cold.steps(1000, freezing: true)
        XCTAssertEqual(cold.climbedM, 70, accuracy: 0.001)   // Everest is ~126K cold steps
    }

    func testBarometerClimbIsCappedPerStep() {
        // A lift: 30 m up with 4 steps taken. Only 4 × 0.25 m counts.
        var lift = ColdClimb()
        lift.altitude(0, freezing: true)
        lift.steps(4, freezing: false)
        for _ in 0..<200 { lift.altitude(30, freezing: true) }
        XCTAssertEqual(lift.climbedM, 1.0, accuracy: 0.001)
        // A real hill: 30 m with 400 steps. All of it (banked in ~3 m chunks as the smoothing catches up).
        var hill = ColdClimb()
        hill.altitude(0, freezing: true)
        for i in 1...400 {
            hill.steps(1, freezing: false)
            hill.altitude(Double(i) * 0.075, freezing: true)
        }
        for _ in 0..<200 { hill.altitude(30, freezing: true) }
        XCTAssertEqual(hill.climbedM, 30, accuracy: 3.1)
        XCTAssertGreaterThan(hill.climbedM, 26)
    }

    func testWipeAllClearsEverythingAndKeepsTheLedgerAppendOnly() throws {
        let store = try Store()
        try store.setPedometer(day: "2026-10-30", steps: 10)
        try store.setMeta("owner", "ab")
        try store.db.write { try $0.execute(sql: """
            INSERT INTO ledger_entry VALUES (1, 'earn', 5, 'daily_steps', '2026-10-30', 0, x'00', x'00', x'00')
            """) }
        try store.wipeAll()
        XCTAssertEqual(try store.dailyCounts(), [])
        XCTAssertNil(try store.meta("owner"))
        XCTAssertEqual(try store.ledgerEntries().count, 0)
        // The delete trigger is back.
        try store.db.write { try $0.execute(sql: "INSERT INTO ledger_entry VALUES (1, 'earn', 5, 'x', 'x', 0, x'00', x'00', x'00')") }
        XCTAssertThrowsError(try store.db.write { try $0.execute(sql: "DELETE FROM ledger_entry") })
    }
}
