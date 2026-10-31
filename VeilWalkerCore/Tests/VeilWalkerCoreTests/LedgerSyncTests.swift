import CryptoKit
import Foundation
import GRDB
import XCTest
@testable import VeilWalkerCore

// Generated independently with Python hashlib + PyNaCl (libsodium) from the ledger.rs formula,
// signed by a test-only key (seed = 32 × 0x42). Not the production key.
private let testServerKey = Data(hex: "2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12")!
private let vectorJSON = #"""
[{"seq": 1, "kind": "earn", "amount": 5250, "reason_code": "daily_steps", "ref_id": "2026-10-28", "ts_ms": 1761700000123, "prev_hash": "0000000000000000000000000000000000000000000000000000000000000000", "entry_hash": "b2b2ca9f3f99a6533c9240567167afb0d7d13c661f89810f6fd037266916338a", "server_sig": "a2aa279a97159d976cf48af84ba8dd8730adc9a40627a79cbcab444d35893c83c1f91df97be9eefdd97dad7067e74f97a1749dfdf57afee96cb698197024770d"}, {"seq": 2, "kind": "earn", "amount": 1250, "reason_code": "daily_steps", "ref_id": "2026-10-28", "ts_ms": 1761710000456, "prev_hash": "b2b2ca9f3f99a6533c9240567167afb0d7d13c661f89810f6fd037266916338a", "entry_hash": "f7276a7e376b9ababa2271d9e27427af35157b77be442bba3b872e1baa4814a2", "server_sig": "32b18b0d57901a866a33d8cb9e76596ec4a21536fa899f7a9293e390263c9a7298084b5d4d7a2cfebcf6a3741a906c54ead7692dd2ba4e2c252a8f3b59e3c607"}, {"seq": 3, "kind": "adjust", "amount": -500, "reason_code": "review", "ref_id": "2026-10-29", "ts_ms": 1761790000789, "prev_hash": "f7276a7e376b9ababa2271d9e27427af35157b77be442bba3b872e1baa4814a2", "entry_hash": "7461e5eb241bd6032132cd20b4862e5adfb2c3d995b3dcb695c5453f3c37d6ed", "server_sig": "dd1ef6d3638f5305ead1884bcf7736329d8a9eb4c2c01f762d3e746917eeebb19e272429b5f59f6518ca72d2881283ec66fb93c7cfe115e98f2618b1adff9209"}]
"""#

private func vectors() throws -> [LedgerEntry] {
    try JSONDecoder().decode([LedgerEntryDTO].self, from: Data(vectorJSON.utf8)).map { try $0.entry() }
}

private func with(_ e: LedgerEntry, amount: Int64? = nil, sig: Data? = nil, seq: Int64? = nil) -> LedgerEntry {
    LedgerEntry(seq: seq ?? e.seq, kind: e.kind, amount: amount ?? e.amount, reasonCode: e.reasonCode, refId: e.refId,
                tsMs: e.tsMs, prevHash: e.prevHash, entryHash: e.entryHash, serverSig: sig ?? e.serverSig)
}

final class LedgerTests: XCTestCase {
    func testHashMatchesIndependentVectors() throws {
        for e in try vectors() {
            XCTAssertEqual(Ledger.hash(e), e.entryHash, "seq \(e.seq)")
        }
    }

    func testChainVerifies() throws {
        let v = try vectors()
        XCTAssertTrue(Ledger.verifyChain(v, serverKey: testServerKey))
        XCTAssertFalse(Ledger.verifyChain(v, serverKey: Ledger.serverPublicKey), "wrong pinned key must fail")
    }

    func testRejectsTampering() throws {
        let v = try vectors()
        XCTAssertThrowsError(try Ledger.check(with(v[0], amount: 999_999), after: nil, serverKey: testServerKey)) {
            XCTAssertEqual($0 as? Ledger.Rejection, .hashMismatch(seq: 1))
        }
        var badSig = v[0].serverSig
        badSig[0] ^= 1
        XCTAssertThrowsError(try Ledger.check(with(v[0], sig: badSig), after: nil, serverKey: testServerKey)) {
            XCTAssertEqual($0 as? Ledger.Rejection, .badSignature(seq: 1))
        }
        XCTAssertThrowsError(try Ledger.check(v[2], after: v[0], serverKey: testServerKey)) {
            XCTAssertEqual($0 as? Ledger.Rejection, .gap(seq: 3))
        }
        XCTAssertThrowsError(try Ledger.check(v[1], after: nil, serverKey: testServerKey)) {
            XCTAssertEqual($0 as? Ledger.Rejection, .brokenChain(seq: 2))
        }
    }
}

final class DayTotalsTests: XCTestCase {
    private func iv(_ steps: Int64, _ source: StepSource, _ verdict: Float = 1) -> StepInterval {
        StepInterval(day: "2026-10-27", startMs: 0, endMs: 0, steps: steps, source: source, verdict: verdict)
    }

    /// Android DayTotalsTest.bucketsBySourceAndWeightsVerdictBySteps (minus HEALTH_CONNECT, which iOS doesn't have).
    func testBucketsBySourceAndWeightsVerdictBySteps() {
        let t = DayTotals.from(day: "2026-10-27", intervals: [
            iv(600, .passive), iv(750, .onion, 1), iv(250, .activeGPS, 0.6), iv(10, .activeSensor, 1),
        ], pedometerSteps: nil)
        XCTAssertEqual([t.passive, t.onion, t.gps, t.sensor], [600, 750, 250, 10])
        XCTAssertEqual(t.verdict, 0.9010, accuracy: 0.0005)
    }

    func testPassiveOnlyDayHasFullVerdict() {
        XCTAssertEqual(DayTotals.from(day: "2026-10-27", intervals: [iv(3000, .passive)], pedometerSteps: nil).verdict, 1)
    }

    func testPassiveIsPedometerMinusWalks() {
        let t = DayTotals.from(day: "d", intervals: [iv(4000, .activeGPS)], pedometerSteps: 10_000)
        XCTAssertEqual(t.passive, 6000)
        XCTAssertEqual(t.total, 10_000, "shown steps stay true: walks aren't counted twice")
    }

    func testPassiveNeverShrinks() {
        // A walk classified after its steps were already synced as passive can't lower passive (server 409s).
        let synced = DayTotals(day: "d", passive: 8000, sensor: 0, gps: 0, onion: 0, verdict: 1)
        let t = DayTotals.from(day: "d", intervals: [iv(4000, .activeSensor)], pedometerSteps: 10_000, lastSynced: synced)
        XCTAssertEqual(t.passive, 8000)
        // Restored history from the server is a floor too.
        XCTAssertEqual(DayTotals.from(day: "d", intervals: [iv(7000, .passive)], pedometerSteps: 2000).passive, 7000)
    }

    func testCanonicalMatchesKotlinFormatting() {
        let t = DayTotals(day: "2026-10-27", passive: 1, sensor: 2, gps: 3, onion: 4, verdict: 1)
        XCTAssertEqual(t.canonical, "2026-10-27|1|2|3|4|1.0")
        XCTAssertEqual(DayTotals(day: "d", passive: 0, sensor: 0, gps: 0, onion: 0, verdict: 0.901).canonical, "d|0|0|0|0|0.901")
    }

    /// Android PointsPolicyTest and backend ledger.rs tests.
    func testPointsPolicy() {
        XCTAssertEqual(PointsPolicy.milliPoints(DayTotals(day: "d", passive: 10_000, sensor: 0, gps: 0, onion: 5_000, verdict: 1)), 11_250)
        XCTAssertEqual(PointsPolicy.milliPoints(DayTotals(day: "d", passive: 0, sensor: 0, gps: 30_000, onion: 0, verdict: 1)), 30_000)
        XCTAssertEqual(PointsPolicy.milliPoints(DayTotals(day: "d", passive: 0, sensor: 0, gps: 10_000, onion: 0, verdict: 0.5)), 5_000)
        XCTAssertEqual(PointsPolicy.milliPoints(DayTotals(day: "d", passive: 0, sensor: 1_000, gps: 0, onion: 0, verdict: 1)), 850)
    }
}

final class StoreTests: XCTestCase {
    func testLedgerIsAppendOnly() throws {
        let store = try Store()
        let v = try vectors()
        try store.appendFromServer(v[0], serverKey: testServerKey)
        XCTAssertThrowsError(try store.db.write { try $0.execute(sql: "UPDATE ledger_entry SET amount = 1") })
        XCTAssertThrowsError(try store.db.write { try $0.execute(sql: "DELETE FROM ledger_entry") })
        XCTAssertThrowsError(try store.appendFromServer(v[2], serverKey: testServerKey), "gap")
        try store.appendFromServer(v[1], serverKey: testServerKey)
        try store.appendFromServer(v[2], serverKey: testServerKey)
        XCTAssertEqual(try store.balanceMilli(), 5250 + 1250 - 500)
        XCTAssertTrue(Ledger.verifyChain(try store.ledgerEntries(), serverKey: testServerKey))

        try store.resetForNewIdentity()
        XCTAssertNil(try store.ledgerHead())
        try store.appendFromServer(v[0], serverKey: testServerKey)
        XCTAssertThrowsError(try store.db.write { try $0.execute(sql: "DELETE FROM ledger_entry") })
    }

    func testPedometerKeepsLargest() throws {
        let store = try Store()
        try store.setPedometer(day: "d", steps: 5000)
        try store.setPedometer(day: "d", steps: 3000)
        XCTAssertEqual(try store.pedometer(day: "d"), 5000)
    }

    func testPersistsAcrossReopen() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "vw-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Store(path: path).setPedometer(day: "2026-10-30", steps: 42)
        XCTAssertEqual(try Store(path: path).pedometer(day: "2026-10-30"), 42)
    }
}

// MARK: - Sync engine against a fake server

/// A tiny in-process server: verifies request signatures like auth.rs, keeps day totals and a signed ledger.
private final class FakeServer: Transport, @unchecked Sendable {
    let isOnion = false
    let signer = Curve25519.Signing.PrivateKey()
    var registered = false
    var days: [String: [String: Any]] = [:]
    var ledger: [[String: Any]] = []
    var history: [[String: Any]] = []
    var calls: [String] = []

    var publicKey: Data { signer.publicKey.rawRepresentation }

    func send(_ r: HTTPRequest) async throws -> HTTPResponse {
        calls.append("\(r.method) \(r.path)")
        // Same check as auth.rs.
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(hex: r.headers["x-tb-key"]!)!)
        let msg = RequestSigner.message(method: r.method, path: r.path, body: r.body,
                                        timestampMillis: Int64(r.headers["x-tb-ts"]!)!, nonceHex: r.headers["x-tb-nonce"]!)
        guard key.isValidSignature(Data(hex: r.headers["x-tb-sig"]!)!, for: msg) else { return json(401, [:]) }

        switch r.path {
        case "/v1/register": registered = true; return HTTPResponse(status: 204, body: Data())
        case "/v1/me": return json(200, ["username": NSNull(), "clan": NSNull(), "avatar": 0])
        case "/v1/history": return json(200, history)
        case "/v1/sync":
            let b = try JSONSerialization.jsonObject(with: r.body) as! [String: Any]
            let day = b["day"] as! String
            // Same rule as main.rs: passive and sensor may not shrink; GPS + onion are compared together.
            func n(_ o: [String: Any], _ k: String) -> Int64 { o[k] as! Int64 }
            if let p = days[day], n(b, "steps_passive") < n(p, "steps_passive") || n(b, "steps_sensor") < n(p, "steps_sensor")
                || n(b, "steps_gps") + n(b, "steps_onion") < n(p, "steps_gps") + n(p, "steps_onion") {
                return json(409, [:])
            }
            let worth = PointsPolicy.milliPoints(DayTotals(day: day, passive: b["steps_passive"] as! Int64, sensor: b["steps_sensor"] as! Int64,
                                                           gps: b["steps_gps"] as! Int64, onion: b["steps_onion"] as! Int64,
                                                           verdict: Float(b["verdict"] as! Double)))
            let already = ledger.filter { $0["ref_id"] as? String == day }.reduce(Int64(0)) { $0 + ($1["amount"] as! Int64) }
            days[day] = b
            guard worth > already else { return json(200, ["minted_milli": 0, "held_for_review": false, "seq": NSNull()]) }
            let seq = Int64(ledger.count + 1)
            let prev = ledger.last.map { Data(hex: $0["entry_hash"] as! String)! } ?? Ledger.genesis
            let ts: Int64 = 1_761_800_000_000 + seq
            let hash = Ledger.hash(prev: prev, seq: seq, kind: "earn", amount: worth - already, reasonCode: "daily_steps", refId: day, tsMs: ts)
            ledger.append(["seq": seq, "kind": "earn", "amount": worth - already, "reason_code": "daily_steps", "ref_id": day, "ts_ms": ts,
                           "prev_hash": prev.hex, "entry_hash": hash.hex, "server_sig": try signer.signature(for: hash).hex])
            return json(200, ["minted_milli": worth - already, "held_for_review": false, "seq": seq])
        case "/v1/ledger":
            let after = Int64(r.query!.replacingOccurrences(of: "after=", with: ""))!
            // Pages of 2 to exercise paging.
            return json(200, Array(ledger.filter { ($0["seq"] as! Int64) > after }.prefix(2)))
        default: return json(404, [:])
        }
    }

    private func json(_ status: Int, _ obj: Any) -> HTTPResponse {
        HTTPResponse(status: status, body: try! JSONSerialization.data(withJSONObject: obj))
    }
}

private struct FakeSteps: StepHistory {
    let counts: [String: Int64]
    func dailySteps(days: [String], now: Date) async throws -> [String: Int64] { counts.filter { days.contains($0.key) } }
}

final class SyncEngineTests: XCTestCase {
    private let utc: LocalDays = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return LocalDays(calendar: c)
    }()
    private let now = Date(timeIntervalSince1970: 1_793_361_600) // 2026-10-30 12:00 UTC

    private func engine(_ id: Identity, _ server: FakeServer, _ store: Store, steps: [String: Int64]) -> SyncEngine {
        let now = self.now
        return SyncEngine(identity: id, api: ApiClient(identity: id, transport: server), store: store,
                          steps: FakeSteps(counts: steps), days: utc, serverKey: server.publicKey, now: { now })
    }

    func testSyncMintsAndPullsVerifiedLedger() async throws {
        let server = FakeServer(), store = try Store(), id = Identity.create()
        let steps: [String: Int64] = ["2026-10-28": 4000, "2026-10-29": 6000, "2026-10-30": 2000, "2026-10-01": 9999]
        let r = try await engine(id, server, store, steps: steps).syncNow()

        XCTAssertTrue(server.registered)
        XCTAssertEqual(r.daysSent, 3, "only days inside the 7-day window")
        XCTAssertEqual(r.mintedMilli, 6000)  // 12,000 passive × 0.5
        XCTAssertEqual(r.ledgerPulled, 3)
        XCTAssertEqual(try store.balanceMilli(), 6000)
        XCTAssertTrue(Ledger.verifyChain(try store.ledgerEntries(), serverKey: server.publicKey))

        // Same counts again: nothing re-sent, nothing minted, no extra register.
        server.calls.removeAll()
        let again = try await engine(id, server, store, steps: steps).syncNow()
        XCTAssertEqual(again.daysSent, 0)
        XCTAssertFalse(server.calls.contains("POST /v1/register"))

        // Today grows: only the difference is minted.
        var more = steps
        more["2026-10-30"] = 3000
        let grew = try await engine(id, server, store, steps: more).syncNow()
        XCTAssertEqual(grew.daysSent, 1)
        XCTAssertEqual(grew.mintedMilli, 500)
        XCTAssertEqual(try store.balanceMilli(), 6500)
    }

    func testForgedLedgerEntryFailsSync() async throws {
        let server = FakeServer(), store = try Store(), id = Identity.create()
        _ = try await engine(id, server, store, steps: ["2026-10-30": 2000]).syncNow()
        // Server (or a man in the middle) slips in an entry signed by someone else.
        let forger = Curve25519.Signing.PrivateKey()
        let prev = Data(hex: server.ledger.last!["entry_hash"] as! String)!
        let hash = Ledger.hash(prev: prev, seq: 2, kind: "earn", amount: 1_000_000, reasonCode: "daily_steps", refId: "x", tsMs: 1)
        server.ledger.append(["seq": Int64(2), "kind": "earn", "amount": Int64(1_000_000), "reason_code": "daily_steps", "ref_id": "x",
                              "ts_ms": Int64(1), "prev_hash": prev.hex, "entry_hash": hash.hex, "server_sig": try forger.signature(for: hash).hex])
        do {
            _ = try await engine(id, server, store, steps: ["2026-10-30": 2000]).syncNow()
            XCTFail("forged entry must be rejected")
        } catch let e as Ledger.Rejection {
            XCTAssertEqual(e, .badSignature(seq: 2))
        }
        XCTAssertEqual(try store.balanceMilli(), 1000, "forged points never land")
    }

    func testRestoreTopsUpHistoryWithoutDoubleMinting() async throws {
        let server = FakeServer(), id = Identity.create()
        // The old phone synced these; the server re-filed 300 onion steps as GPS.
        server.registered = true
        server.history = [["day": "2026-10-29", "steps_passive": 5000, "steps_sensor": 100, "steps_gps": 1300, "steps_onion": 700]]
        server.days["2026-10-29"] = ["steps_passive": Int64(5000), "steps_sensor": Int64(100), "steps_gps": Int64(1300), "steps_onion": Int64(700)]

        let store = try Store()
        // The new phone's pedometer only saw part of that day.
        let r = try await engine(id, server, store, steps: ["2026-10-29": 1200]).syncNow()
        let t = try store.totals(day: "2026-10-29")
        XCTAssertEqual(t.total, 7100, "history restored once, onion/GPS not double counted")
        XCTAssertEqual(t.onion, 700, "proven onion steps stay onion")
        XCTAssertEqual(t.gps, 1300)
        XCTAssertEqual(r.daysSent, 0, "matches the server already: nothing to send, no 409")
    }

    func testNewIdentityResetsLedgerCopy() async throws {
        let server = FakeServer(), store = try Store()
        _ = try await engine(Identity.create(), server, store, steps: ["2026-10-30": 2000]).syncNow()
        XCTAssertEqual(try store.balanceMilli(), 1000)

        // Restore a different account on the same phone. The phone's own pedometer days sync to it.
        let other = FakeServer()
        _ = try await engine(Identity.create(), other, store, steps: [:]).syncNow()
        XCTAssertTrue(other.registered, "new identity registers")
        let entries = try store.ledgerEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(Ledger.verifyChain(entries, serverKey: other.publicKey), "only the new account's chain is left")
    }
}
