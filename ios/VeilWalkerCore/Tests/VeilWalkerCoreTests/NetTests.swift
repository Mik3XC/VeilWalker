import CryptoKit
import Foundation
import XCTest
@testable import VeilWalkerCore

private let zooPhrase = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"
private let emptySha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

final class RequestSignerTests: XCTestCase {
    func testMessageFormatMatchesAuthRs() {
        let msg = RequestSigner.message(method: "GET", path: "/v1/me", body: Data(), timestampMillis: 1_761_800_000_123, nonceHex: "00112233445566778899aabbccddeeff")
        XCTAssertEqual(String(decoding: msg, as: UTF8.self),
                       "GET\n/v1/me\n\(emptySha256)\n1761800000123\n00112233445566778899aabbccddeeff")

        let body = Data(#"{"tag":"ROX"}"#.utf8)
        let post = RequestSigner.message(method: "POST", path: "/v1/clan", body: body, timestampMillis: 1, nonceHex: "ab")
        XCTAssertEqual(String(decoding: post, as: UTF8.self),
                       "POST\n/v1/clan\n\(Data(SHA256.hash(data: body)).hex)\n1\nab")
    }

    func testHeadersVerify() throws {
        let id = try Identity(mnemonic: zooPhrase)
        let nonce = Data(hex: "0f0e0d0c0b0a09080706050403020100")!
        let now = Date(timeIntervalSince1970: 1_761_800_000.123_9)
        let h = try RequestSigner.headers(identity: id, method: "POST", path: "/v1/register", body: Data(), now: now, nonce: nonce)

        XCTAssertEqual(h["x-tb-key"], "26d63c952e3dcaa520fe87ba52250e14362259c6b3d7d2d1c2963d1ed1f04413")
        XCTAssertEqual(h["x-tb-ts"], "1761800000123")
        XCTAssertEqual(h["x-tb-nonce"], "0f0e0d0c0b0a09080706050403020100")
        let sig = try XCTUnwrap(Data(hex: h["x-tb-sig"]!))
        XCTAssertEqual(sig.count, 64)
        let msg = RequestSigner.message(method: "POST", path: "/v1/register", body: Data(), timestampMillis: 1_761_800_000_123, nonceHex: h["x-tb-nonce"]!)
        XCTAssertTrue(id.signingKey.publicKey.isValidSignature(sig, for: msg))
    }

    func testNoncesAreFresh() {
        let a = RequestSigner.randomNonce(), b = RequestSigner.randomNonce()
        XCTAssertEqual(a.count, 16)
        XCTAssertNotEqual(a, b)
    }
}

private final class RecordingTransport: Transport, @unchecked Sendable {
    let isOnion = false
    var requests: [HTTPRequest] = []
    var response = HTTPResponse(status: 204, body: Data())

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return response
    }
}

final class ApiClientTests: XCTestCase {
    func testRegisterSignsEmptyJsonPost() async throws {
        let id = try Identity(mnemonic: zooPhrase)
        let t = RecordingTransport()
        try await ApiClient(identity: id, transport: t).register()

        let r = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/v1/register")
        XCTAssertEqual(r.body, Data())
        XCTAssertEqual(r.headers["Content-Type"], "application/json")
        let msg = RequestSigner.message(method: "POST", path: "/v1/register", body: Data(),
                                        timestampMillis: Int64(r.headers["x-tb-ts"]!)!, nonceHex: r.headers["x-tb-nonce"]!)
        XCTAssertTrue(id.signingKey.publicKey.isValidSignature(Data(hex: r.headers["x-tb-sig"]!)!, for: msg))
    }

    func testMeDecodesNulls() async throws {
        let t = RecordingTransport()
        t.response = HTTPResponse(status: 200, body: Data(#"{"username":null,"clan":"ROX","avatar":2}"#.utf8))
        let me = try await ApiClient(identity: Identity.create(), transport: t).me()
        XCTAssertEqual(me, ApiClient.Me(username: nil, clan: "ROX", avatar: 2))
        XCTAssertEqual(t.requests.first?.method, "GET")
        XCTAssertNil(t.requests.first?.headers["Content-Type"])
    }

    func testSocialCallsMatchTheServer() async throws {
        let t = RecordingTransport()
        let api = ApiClient(identity: Identity.create(), transport: t)

        t.response = HTTPResponse(status: 200, body: Data(#"{"username":"HashCat","clan":null,"avatar":0}"#.utf8))
        let handle = try await api.claimUsername("HashCat")
        XCTAssertEqual(handle, "HashCat")
        XCTAssertEqual(t.requests.last?.path, "/v1/username")
        XCTAssertEqual(t.requests.last?.body, Data(#"{"username":"HashCat"}"#.utf8))

        t.response = HTTPResponse(status: 200, body: Data(#"{"clan":"ROX"}"#.utf8))
        let joined = try await api.clanJoin("ROX")
        XCTAssertEqual(joined, "ROX")
        XCTAssertEqual(t.requests.last?.path, "/v1/clan/join")
        t.response = HTTPResponse(status: 200, body: Data(#"{"clan":null}"#.utf8))
        let left = try await api.clanLeave()
        XCTAssertNil(left)

        t.response = HTTPResponse(status: 200, body: Data(#"{"code":"VW-AB12-CD34","kind":"clan","clan":"ROX","expires_in_days":7}"#.utf8))
        let code = try await api.createInvite(.clan)
        XCTAssertEqual(code, "VW-AB12-CD34")
        XCTAssertEqual(t.requests.last?.body, Data(#"{"kind":"clan"}"#.utf8))

        t.response = HTTPResponse(status: 200, body: Data(#"{"friend":"Moll","joined_clan":null}"#.utf8))
        let accepted = try await api.acceptInvite("VW-AB12-CD34")
        XCTAssertEqual(accepted.friend, "Moll")
        XCTAssertNil(accepted.joinedClan)

        t.response = HTTPResponse(status: 200, body: Data(#"[{"id":"ab","handle":null,"clan":"ROX","avatar":3,"week_steps":40081}]"#.utf8))
        let friends = try await api.friends()
        XCTAssertEqual(friends, [ApiClient.Person(id: "ab", handle: nil, clan: "ROX", avatar: 3, weekSteps: 40081)])

        t.response = HTTPResponse(status: 200, body: Data(#"{"clan":"ROX","members":[],"week_total":0}"#.utf8))
        let squad = try await api.squad()
        XCTAssertEqual(squad.clan, "ROX")
        XCTAssertEqual(t.requests.last?.method, "GET")

        t.response = HTTPResponse(status: 204, body: Data())
        try await api.setAvatar(2)
        XCTAssertEqual(t.requests.last?.body, Data(#"{"avatar":2}"#.utf8))
    }

    func testErrorReason() async throws {
        let t = RecordingTransport()
        t.response = HTTPResponse(status: 409, body: Data(#"{"error":"taken"}"#.utf8))
        do {
            _ = try await ApiClient(identity: Identity.create(), transport: t).me()
            XCTFail("expected ApiError")
        } catch let e as ApiError {
            XCTAssertEqual(e, ApiError(status: 409, reason: "taken"))
        }
        t.response = HTTPResponse(status: 401, body: Data())
        do {
            try await ApiClient(identity: Identity.create(), transport: t).register()
            XCTFail("expected ApiError")
        } catch let e as ApiError {
            XCTAssertEqual(e, ApiError(status: 401, reason: nil))
        }
    }
}

private final class MemorySecretStore: SecretStore, @unchecked Sendable {
    var secret: Data?
    func read() throws -> Data? { secret }
    func write(_ secret: Data) throws { self.secret = secret }
    func delete() throws { secret = nil }
}

final class IdentityStoreTests: XCTestCase {
    func testEnsureRestoreErase() throws {
        let mem = MemorySecretStore()
        let store = IdentityStore(secrets: mem)
        XCTAssertNil(try store.load())

        let created = try store.ensureIdentity()
        XCTAssertEqual(try store.ensureIdentity().publicKeyHex, created.publicKeyHex, "must not replace an existing identity")
        XCTAssertEqual(mem.secret, created.entropy, "stores entropy, like Android")

        let restored = try store.restore(phrase: zooPhrase)
        XCTAssertEqual(try store.load()?.publicKeyHex, restored.publicKeyHex)
        XCTAssertThrowsError(try store.restore(phrase: "zoo zoo"))
        XCTAssertEqual(try store.load()?.publicKeyHex, restored.publicKeyHex, "a bad phrase must not wipe the account")

        try store.erase()
        XCTAssertNil(try store.load())
    }
}

/// Talks to the live server. Opt-in: VW_LIVE=1 swift test --filter LiveServerTests
/// Uses a fresh throwaway key each run; registers it (one empty account row) and reads it back.
final class LiveServerTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VW_LIVE"] == "1", "set VW_LIVE=1 to hit the live server")
    }

    func testRegisterAndMeOverClearnet() async throws {
        let api = ApiClient(identity: Identity.create(), transport: ClearnetTransport())

        // Valid signature, unknown account: auth passes, account lookup fails.
        do {
            _ = try await api.me()
            XCTFail("expected 403 before register")
        } catch let e as ApiError {
            XCTAssertEqual(e.status, 403)
        }

        try await api.register()
        try await api.register() // idempotent
        let me = try await api.me()
        XCTAssertEqual(me, ApiClient.Me(username: nil, clan: nil, avatar: 0))
    }

    func testBadSignatureIsRejected() async throws {
        let id = Identity.create()
        var headers = try RequestSigner.headers(identity: id, method: "GET", path: "/v1/me", body: Data())
        // Sign as one key, claim to be another.
        headers["x-tb-key"] = Identity.create().publicKeyHex
        let r = try await ClearnetTransport().send(HTTPRequest(method: "GET", path: "/v1/me", headers: headers, body: Data()))
        XCTAssertEqual(r.status, 401)
    }
}

#if os(iOS)
/// The real Keychain only behaves like the phone's on iOS (run via xcodebuild on a simulator).
final class KeychainSecretStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let store = KeychainSecretStore(service: "com.premisei3.veilwalker.tests", account: UUID().uuidString)
        defer { try? store.delete() }
        do {
            _ = try store.read()
        } catch let e as KeychainSecretStore.Failure where e.status == errSecMissingEntitlement {
            throw XCTSkip("SwiftPM test bundles have no keychain access group; the app target covers this")
        }
        XCTAssertNil(try store.read())
        try store.write(Data([1, 2, 3]))
        try store.write(Data([4, 5, 6])) // overwrite
        XCTAssertEqual(try store.read(), Data([4, 5, 6]))
        try store.delete()
        XCTAssertNil(try store.read())
    }
}
#endif
