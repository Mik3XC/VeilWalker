import Foundation

public struct SyncResult: Equatable, Sendable {
    public var daysSent = 0
    public var mintedMilli: Int64 = 0
    public var held = 0
    public var ledgerPulled = 0
    public var viaOnion = false
}

/// Syncs daily totals and pulls the signed ledger. Mirrors Android's SyncRepository.syncNow().
/// Runs on foreground, after walks and from BGAppRefreshTask; one sync at a time per engine.
public actor SyncEngine {
    private let identity: Identity
    private let api: ApiClient
    private let store: Store
    private let steps: StepHistory?
    private let days: LocalDays
    private let serverKey: Data
    private let now: @Sendable () -> Date
    private var historyChecked = false

    /// Handle, clan and avatar from the last sync. The server is the source of truth.
    public private(set) var me: ApiClient.Me?

    /// The server accepts days up to 7 back; Android sends today and the 6 before it.
    public static let windowDays = 7

    public init(identity: Identity, api: ApiClient, store: Store, steps: StepHistory?, days: LocalDays = LocalDays(),
                serverKey: Data = Ledger.serverPublicKey, now: @escaping @Sendable () -> Date = { Date() }) {
        self.identity = identity
        self.api = api
        self.store = store
        self.steps = steps
        self.days = days
        self.serverKey = serverKey
        self.now = now
    }

    public func syncNow() async throws -> SyncResult {
        var result = SyncResult(viaOnion: api.viaOnion)

        // The ledger copy and sync floors belong to one account. A restored phrase starts them over.
        let owner = try store.meta("owner")
        if owner != identity.publicKeyHex {
            if owner != nil { try store.resetForNewIdentity() }
            try store.setMeta("owner", identity.publicKeyHex)
            historyChecked = false
        }
        if try store.meta("registered") != "1" {
            try await api.register()
            try store.setMeta("registered", "1")
        }
        let me = try await api.me()
        self.me = me
        // Kept locally so the home screen shows the handle before the next sync (Tor can take a while).
        try store.setMeta("username", me.username)
        try store.setMeta("clan", me.clan)
        try store.setMeta("avatar", String(me.avatar))

        let window = days.lastDays(Self.windowDays, now: now())
        if let steps {
            for (day, n) in try await steps.dailySteps(days: window, now: now()) {
                try store.setPedometer(day: day, steps: n)
            }
        }

        // After a restore or on a new phone, local history is missing: top it up from the server's daily totals
        // so lifetime steps, routes and badges come back. Idempotent; once per launch, as on Android.
        if !historyChecked {
            try await topUpHistory()
            historyChecked = true
        }

        for day in try store.daysWithSteps(since: window[0]) {
            let totals = try store.totals(day: day)
            if try store.synced(day: day) == totals { continue }   // nothing new since the server accepted it
            let sig = try identity.sign(Data(totals.canonical.utf8))
            do {
                let r = try await api.sync(totals, summarySignature: sig)
                result.mintedMilli += r.mintedMilli
                if r.heldForReview { result.held += 1 }
                try store.markSynced(totals)
            } catch let e as ApiError where e.status == 409 {
                // Totals didn't grow past what the server has. Nothing to mint; not an error.
            }
            result.daysSent += 1
        }

        result.ledgerPulled = try await pullLedger()
        return result
    }

    private func topUpHistory() async throws {
        for d in try await api.history() {
            let local = try store.intervals(day: d.day)
            func sum(_ s: StepSource...) -> Int64 { local.filter { s.contains($0.source) }.reduce(0) { $0 + $1.steps } }
            let t = Int64((days.start(of: d.day)?.timeIntervalSince1970 ?? 0) * 1000)
            // Onion steps that reached the server over clearnet were re-filed there as GPS. Those are already
            // here as onion, so they don't count as missing GPS. Restoring tiers separately keeps proven onion steps
            // onion: re-sending them as GPS would make the server downgrade them for good.
            let refiledOnion = max(0, sum(.onion) - d.onion)
            let missing: [(StepSource, Int64)] = [
                (.passive, d.passive - sum(.passive)),
                (.activeSensor, d.sensor - sum(.activeSensor)),
                (.activeGPS, d.gps - sum(.activeGPS) - refiledOnion),
                (.onion, d.onion - sum(.onion)),
            ]
            for (source, n) in missing where n > 0 {
                // Stamped at local midnight; syncs back as the same totals, so nothing is minted twice.
                try store.insert(StepInterval(day: d.day, startMs: t, endMs: t, steps: n, source: source))
            }
            // The server's totals are the floor for this day from now on.
            let floor = try store.synced(day: d.day)
            try store.markSynced(DayTotals(day: d.day, passive: max(d.passive, floor?.passive ?? 0),
                                           sensor: max(d.sensor, floor?.sensor ?? 0), gps: max(d.gps, floor?.gps ?? 0),
                                           onion: max(d.onion, floor?.onion ?? 0), verdict: floor?.verdict ?? 1))
        }
    }

    /// Fetches and verifies every new signed entry; the store rejects anything that doesn't chain or verify.
    private func pullLedger() async throws -> Int {
        var count = 0
        while true {
            let page = try await api.ledger(after: store.ledgerHead()?.seq ?? 0)
            if page.isEmpty { return count }
            for entry in page {
                try store.appendFromServer(entry, serverKey: serverKey)
                count += 1
            }
        }
    }
}
