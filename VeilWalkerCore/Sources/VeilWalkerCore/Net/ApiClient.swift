import Foundation

/// A non-2xx response. `reason` is the server's {"error": "..."} code when it sent one
/// (taken, already_claimed, invalid_tag, ...).
public struct ApiError: Error, Equatable {
    public let status: Int
    public let reason: String?
}

/// Signed calls to the VeilWalker API. Mirrors core/net ApiClient.kt; backend/src is the truth.
/// Endpoints are added alongside the features that use them.
public struct ApiClient: Sendable {
    private let identity: Identity
    private let transport: Transport

    public init(identity: Identity, transport: Transport) {
        self.identity = identity
        self.transport = transport
    }

    public struct Me: Codable, Equatable, Sendable {
        public let username: String?
        public let clan: String?
        public let avatar: Int

        public init(username: String?, clan: String?, avatar: Int) {
            self.username = username
            self.clan = clan
            self.avatar = avatar
        }
    }

    /// Creates the account row for this key. Safe to repeat.
    public func register() async throws {
        _ = try await call("POST", "/v1/register", body: Data())
    }

    /// The account's permanent handle, clan tag and avatar. 403 if not registered.
    public func me() async throws -> Me {
        try await JSONDecoder().decode(Me.self, from: call("GET", "/v1/me"))
    }

    /// True if this client talks to the onion service (onion-tier steps only count then).
    public var viaOnion: Bool { transport.isOnion }

    public struct SyncResponse: Equatable, Sendable {
        /// Milli-points minted by this sync (0 if nothing new or held).
        public let mintedMilli: Int64
        public let heldForReview: Bool
        public let seq: Int64?

        public init(mintedMilli: Int64, heldForReview: Bool, seq: Int64?) {
            self.mintedMilli = mintedMilli
            self.heldForReview = heldForReview
            self.seq = seq
        }
    }

    private struct SyncResponseDTO: Decodable {
        let minted_milli: Int64
        let held_for_review: Bool
        let seq: Int64?
    }

    /// Sends a day's running totals. The server mints only the difference; 409 means totals didn't grow.
    public func sync(_ totals: DayTotals, summarySignature: Data) async throws -> SyncResponse {
        let body: [String: Any] = [
            "day": totals.day,
            "steps_passive": totals.passive,
            "steps_sensor": totals.sensor,
            "steps_gps": totals.gps,
            "steps_onion": totals.onion,
            "verdict": Double(totals.verdict),
            "summary_sig": summarySignature.hex,
        ]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let r = try await JSONDecoder().decode(SyncResponseDTO.self, from: call("POST", "/v1/sync", body: data))
        return SyncResponse(mintedMilli: r.minted_milli, heldForReview: r.held_for_review, seq: r.seq)
    }

    /// Up to 500 signed ledger entries after `seq`. Verify before storing (Store.appendFromServer does).
    public func ledger(after seq: Int64) async throws -> [LedgerEntry] {
        try await JSONDecoder().decode([LedgerEntryDTO].self, from: call("GET", "/v1/ledger", query: "after=\(seq)"))
            .map { try $0.entry() }
    }

    public struct DayHistory: Decodable, Equatable, Sendable {
        public let day: String
        public let passive: Int64
        public let sensor: Int64
        public let gps: Int64
        public let onion: Int64

        enum CodingKeys: String, CodingKey {
            case day
            case passive = "steps_passive"
            case sensor = "steps_sensor"
            case gps = "steps_gps"
            case onion = "steps_onion"
        }

        public init(day: String, passive: Int64, sensor: Int64, gps: Int64, onion: Int64) {
            self.day = day
            self.passive = passive
            self.sensor = sensor
            self.gps = gps
            self.onion = onion
        }
    }

    /// The account's synced daily totals, oldest first, for rebuilding history after a restore.
    public func history() async throws -> [DayHistory] {
        try await JSONDecoder().decode([DayHistory].self, from: call("GET", "/v1/history"))
    }

    // MARK: Handle, clan, profile (main.rs)

    /// Claims the permanent handle. Errors: taken, already_claimed, invalid_length, invalid_characters, reserved.
    public func claimUsername(_ name: String) async throws -> String {
        let r = try await post("/v1/username", ["username": name])
        guard let handle = r["username"] as? String else { throw ApiError(status: 200, reason: "bad_response") }
        return handle
    }

    /// Clan calls return the new tag (nil after leaving). Errors: invalid_tag, taken, in_clan, not_found, full.
    public func clanCreate(_ tag: String) async throws -> String? { try await post("/v1/clan", ["tag": tag])["clan"] as? String }
    public func clanJoin(_ tag: String) async throws -> String? { try await post("/v1/clan/join", ["tag": tag])["clan"] as? String }
    public func clanLeave() async throws -> String? { try await post("/v1/clan/leave", ["tag": ""])["clan"] as? String }

    /// The ASCII picture friends see (0...3).
    public func setAvatar(_ index: Int) async throws {
        _ = try await call("POST", "/v1/profile", body: json(["avatar": index]))
    }

    // MARK: Social (social.rs)

    /// A friend or squadmate as the server shows them: never more than handle, clan, avatar and weekly steps.
    public struct Person: Decodable, Equatable, Identifiable, Sendable {
        public let id: String
        public let handle: String?
        public let clan: String?
        public let avatar: Int
        public let weekSteps: Int64

        enum CodingKeys: String, CodingKey {
            case id, handle, clan, avatar
            case weekSteps = "week_steps"
        }

        public init(id: String, handle: String?, clan: String?, avatar: Int, weekSteps: Int64) {
            self.id = id
            self.handle = handle
            self.clan = clan
            self.avatar = avatar
            self.weekSteps = weekSteps
        }
    }

    public struct Squad: Decodable, Equatable, Sendable {
        public let clan: String?
        public let members: [Person]
        public let weekTotal: Int64

        enum CodingKeys: String, CodingKey {
            case clan, members
            case weekTotal = "week_total"
        }
    }

    public enum InviteKind: String, Sendable {
        case friend   // one use
        case clan     // 10 uses
    }

    /// Returns the new invite code (VW-XXXX-XXXX). Errors: no_handle, no_clan.
    public func createInvite(_ kind: InviteKind) async throws -> String {
        let r = try await post("/v1/invites", ["kind": kind.rawValue])
        guard let code = r["code"] as? String else { throw ApiError(status: 200, reason: "bad_response") }
        return code
    }

    /// Returns the new friend's handle and the clan joined, if any. Errors: not_found, expired, own_invite.
    public func acceptInvite(_ code: String) async throws -> (friend: String?, joinedClan: String?) {
        let r = try await post("/v1/invites/accept", ["code": code])
        return (r["friend"] as? String, r["joined_clan"] as? String)
    }

    public func friends() async throws -> [Person] {
        try await JSONDecoder().decode([Person].self, from: call("GET", "/v1/friends"))
    }

    public func removeFriend(id: String) async throws {
        _ = try await call("POST", "/v1/friends/remove", body: json(["id": id]))
    }

    public func squad() async throws -> Squad {
        try await JSONDecoder().decode(Squad.self, from: call("GET", "/v1/squad"))
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func post(_ path: String, _ object: [String: Any]) async throws -> [String: Any] {
        let data = try await call("POST", path, body: json(object))
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Deletes the account's synced data on the server (App Store requires in-app deletion).
    public func deleteAccount() async throws {
        _ = try await call("DELETE", "/v1/account", body: Data())
    }

    private func call(_ method: String, _ path: String, query: String? = nil, body: Data? = nil) async throws -> Data {
        let bytes = body ?? Data()
        var headers = try RequestSigner.headers(identity: identity, method: method, path: path, body: bytes)
        if method != "GET" {
            headers["Content-Type"] = "application/json"
        }
        let response = try await transport.send(
            HTTPRequest(method: method, path: path, query: query, headers: headers, body: bytes)
        )
        guard (200..<300).contains(response.status) else {
            let reason = (try? JSONSerialization.jsonObject(with: response.body) as? [String: Any])?["error"] as? String
            throw ApiError(status: response.status, reason: reason)
        }
        return response.body
    }
}
