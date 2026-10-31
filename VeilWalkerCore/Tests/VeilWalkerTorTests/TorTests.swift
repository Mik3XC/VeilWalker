import Foundation
import XCTest
import VeilWalkerCore
@testable import VeilWalkerTor

final class TorOfflineTests: XCTestCase {
    func testRequestWithoutTorFailsInsteadOfLeaking() async throws {
        let arti = Arti()
        arti.stop()
        do {
            _ = try await arti.http(method: "GET", url: Backend.onion.absoluteString + "/health", headers: "", body: Data(), timeout: .seconds(5))
            XCTFail("expected an error while Tor is not running")
        } catch let e as TorError {
            XCTAssertTrue(e.message.contains("not running"), e.message)
        }
    }
}

/// Bootstraps real Tor and talks to the production onion service. Opt-in:
/// VW_LIVE=1 swift test --filter TorLiveTests
final class TorLiveTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VW_LIVE"] == "1", "set VW_LIVE=1 to bootstrap Tor")
    }

    func testOnionEndToEnd() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "vw-arti-test")
        let dirs = (state: root.appending(path: "state"), cache: root.appending(path: "cache"))
        for d in [dirs.state, dirs.cache] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }

        let arti = Arti()
        let t0 = ContinuousClock.now
        try await arti.start(timeout: .seconds(90), directories: dirs)
        print("tor bootstrapped in \(ContinuousClock.now - t0)")
        XCTAssertTrue(arti.isRunning)
        defer { arti.stop() }

        // Plain HTTP to a clearnet host over Tor is refused.
        do {
            _ = try await arti.http(method: "GET", url: "http://example.com/", headers: "", body: Data(), timeout: .seconds(10))
            XCTFail("clearnet http must be refused")
        } catch let e as TorError {
            XCTAssertTrue(e.message.contains(".onion"), e.message)
        }
        // HTTPS through the exit only to api.weather.gov.
        do {
            _ = try await arti.http(method: "GET", url: "https://example.com/", headers: "", body: Data(), timeout: .seconds(10))
            XCTFail("https to other clearnet hosts must be refused")
        } catch let e as TorError {
            XCTAssertTrue(e.message.contains("api.weather.gov"), e.message)
        }
        let t2 = ContinuousClock.now
        let headers = ["User-Agent": NWS.userAgent, "Accept": "application/geo+json"]
        let points = try await TorExit.get(NWS.pointsURL(lat: 47.61, lon: -122.33), headers: headers, arti: arti, timeout: .seconds(90))
        XCTAssertEqual(points.status, 200, String(decoding: points.body, as: UTF8.self))
        let hourly = try await TorExit.get(try NWS.hourlyURL(fromPoints: points.body), headers: headers, arti: arti, timeout: .seconds(90))
        let tempF = try NWS.currentTempF(fromHourly: hourly.body)
        XCTAssertTrue((-60...130).contains(tempF))
        print("weather over a Tor exit: \(tempF)°F in \(ContinuousClock.now - t2)")

        let tor = TorTransport(arti: arti, requestTimeout: .seconds(90))
        let t1 = ContinuousClock.now
        let healthy = try await tor.health()
        XCTAssertTrue(healthy)
        print("onion /health in \(ContinuousClock.now - t1)")

        // Signed calls over the onion service, fresh throwaway key.
        let api = ApiClient(identity: Identity.create(), transport: tor)
        try await api.register()
        let me = try await api.me()
        XCTAssertEqual(me, ApiClient.Me(username: nil, clan: nil, avatar: 0))

        // A zero-step day: exercises /v1/sync, /v1/ledger and /v1/history without minting anything.
        let today = LocalDays().day(Date())
        let zero = DayTotals(day: today, passive: 0, sensor: 0, gps: 0, onion: 0, verdict: 1)
        let identity = Identity.create()
        let fresh = ApiClient(identity: identity, transport: tor)
        try await fresh.register()
        let r = try await fresh.sync(zero, summarySignature: try identity.sign(Data(zero.canonical.utf8)))
        XCTAssertEqual(r, ApiClient.SyncResponse(mintedMilli: 0, heldForReview: false, seq: nil))
        let ledger = try await fresh.ledger(after: 0)
        XCTAssertEqual(ledger, [])
        let history = try await fresh.history()
        XCTAssertEqual(history.map(\.day), [today])
    }
}

/// Starts a real snowflake against the Tor Project's broker for 60 s. Opt-in: VW_LIVE=1.
final class SnowflakeLiveTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VW_LIVE"] == "1", "set VW_LIVE=1 to run a real snowflake")
    }

    func testSnowflakeStartsAndStops() async throws {
        let relayed = Counter()
        SnowflakeHost.shared.start(capacity: 1) { relayed.add($0) }
        try await Task.sleep(for: .seconds(60))
        XCTAssertTrue(SnowflakeHost.shared.isRunning, SnowflakeHost.shared.lastError ?? "")
        XCTAssertNil(SnowflakeHost.shared.lastError)
        print("snowflake relayed \(relayed.value) bytes in 60 s (0 is normal: depends on being matched with a client)")
        SnowflakeHost.shared.stop()
        XCTAssertFalse(SnowflakeHost.shared.isRunning)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n: Int64 = 0
        func add(_ v: Int64) { lock.withLock { n += v } }
        var value: Int64 { lock.withLock { n } }
    }
}
