import BackgroundTasks
import Foundation
import Observation
import VeilWalkerCore
import VeilWalkerTor

/// Everything the screens show, read from the local database. The phone is the source of truth for steps; the
/// server's signed ledger is the source of truth for points. Plays the part of Android's HomeViewModel,
/// StatsViewModel, AccountViewModel and AchievementRepository.
@MainActor @Observable
final class AppModel {
    let tor = TorController()
    let weather: WeatherController
    let content = ContentLibrary.shared

    /// Nothing runs (no identity, no sensors, no network) until the consent screen is accepted.
    private(set) var consented = UserDefaults.standard.integer(forKey: AppModel.consentKey) >= AppModel.consentVersion

    // Account (from /v1/me, cached in the store).
    private(set) var handle: String?
    private(set) var clan: String?
    private(set) var avatar = 0
    private(set) var publicKey = ""
    var keyPrefix: String { String(publicKey.prefix(8)) }

    // Steps: TRUE counts, multipliers only ever touch points.
    private(set) var days: [DayCount] = []
    private(set) var lifetimeSteps: Int64 = 0
    private(set) var todaySteps: Int64 = 0
    private(set) var points: Int64 = 0
    private(set) var strideM = Stride.defaultM
    private(set) var coldClimbM = 0.0
    private(set) var hourly: [Int64] = Array(repeating: 0, count: 24)

    private(set) var board = BadgeBoard(all: AchievementRules.shared, unlockedAt: [:])
    private(set) var route: RouteProgress
    private(set) var syncNote = "not synced yet"
    private(set) var walks: WalkController?
    private(set) var startupError: String?

    private var identity: Identity?
    private var store: Store?
    private var engine: SyncEngine?
    private var engineViaOnion = true
    private var syncing = false
    private let localDays = LocalDays()
    private let pedometer = PedometerStepHistory()

    static let consentKey = "consentVersion"
    /// Bump when the consent text changes materially; users are asked again.
    static let consentVersion = 1
    static let syncTaskId = "com.premisei3.veilwalker.sync"

    init() {
        let r = ContentLibrary.shared.active.route!
        route = RouteProgress(route: r, position: r.positionAt(0), strideM: Stride.defaultM)
        weather = WeatherController(tor: tor)
    }

    var todayKm: Double { Stride.km(todaySteps, strideM: strideM) }
    var outlawRank: String { board.outlawRank }

    // MARK: Lifecycle

    func acceptConsent() {
        UserDefaults.standard.set(Self.consentVersion, forKey: Self.consentKey)
        consented = true
        launch()
        Task { await foreground() }
    }

    /// Loads (or creates) the identity and opens the database.
    func launch() {
        guard consented, identity == nil else { return }
        do {
            let id = try IdentityStore().ensureIdentity()
            identity = id
            publicKey = id.publicKeyHex
            let store = try self.store ?? Store.openDefault()
            self.store = store
            if walks == nil {
                walks = WalkController(store: store, tor: tor, weather: weather) { [weak self] in
                    await self?.sync()   // a walk just ended: send it while the app is still awake
                }
            }
            refresh()
        } catch {
            startupError = "\(error)"
        }
    }

    private var foregroundRun: Task<Void, Never>?

    /// App came to the foreground. Launch and "became active" both call this at startup; running it twice at once
    /// would scan history twice and record every retroactive walk twice, so a second call waits for the first.
    func foreground() async {
        if let running = foregroundRun { return await running.value }
        let run = Task { await self.runForeground() }
        foregroundRun = run
        await run.value
        foregroundRun = nil
    }

    /// Read the pedometer and rebuild missed walks (no network), then wake Tor and sync. Walks are found before the
    /// sync so their steps go up as walk steps, not passive.
    private func runForeground() async {
        guard let store else { return }
        await readPedometer()
        await RetroWalkScanner(store: store).scan()
        refresh()
        startLiveSteps()
        walks?.startWatching()
        walks?.appDidBecomeActive()
        await tor.wake()
        await sync()
        await weather.refresh()
    }

    func background() {
        walks?.appDidEnterBackground()
        // A live walk keeps the app (and Tor) running in the background; otherwise iOS freezes both.
        if walks?.isWalking != true { tor.suspend() }
        pedometer.stopLiveUpdates()
        scheduleBackgroundSync()
    }

    // MARK: Background sync (BGAppRefreshTask, Android's hourly WorkManager sync)

    func scheduleBackgroundSync() {
        guard consented else { return }
        let req = BGAppRefreshTaskRequest(identifier: Self.syncTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(req)
    }

    /// iOS gives a refresh task about 30 s: boot Tor from its cached state, bank steps and walks, sync, stop.
    /// If Tor can't connect in time it gives up quietly and tries next time. Never clearnet while Tor is on.
    func backgroundSync() async {
        scheduleBackgroundSync()
        launch()
        guard let identity, let store, walks?.isWalking != true else { return }
        await readPedometer()
        await RetroWalkScanner(store: store).scan()
        let transport: Transport = tor.enabled ? TorTransport(bootTimeout: .seconds(12), requestTimeout: .seconds(12)) : ClearnetTransport()
        let engine = SyncEngine(identity: identity, api: ApiClient(identity: identity, transport: transport), store: store,
                                steps: pedometer)
        if let r = try? await engine.syncNow() { syncNote = note(r) + " · background" }
        if tor.enabled { Arti.shared.stop() }   // Tor sleeps until it's needed
        refresh()
    }

    // MARK: Walks, Tor

    /// Tapping the walk line starts a walk now.
    func startWalk() {
        walks?.startNow()
    }

    func toggleTor() {
        tor.toggle()
        Task { await foreground() }
    }

    // MARK: Sync

    /// Pedometer → /v1/sync → signed ledger, over the onion service unless the user turned Tor off.
    @discardableResult
    func sync() async -> SyncResult? {
        guard let identity, let store, !syncing else { return nil }
        syncing = true
        defer { syncing = false }
        if engine == nil || engineViaOnion != tor.enabled {
            engine = SyncEngine(identity: identity, api: ApiClient(identity: identity, transport: tor.transport()), store: store,
                                steps: pedometer)
            engineViaOnion = tor.enabled
        }
        var result: SyncResult?
        do {
            let r = try await engine!.syncNow()
            syncNote = note(r)
            result = r
        } catch {
            syncNote = "sync failed · \(error)"
        }
        refresh()
        return result
    }

    private func note(_ r: SyncResult) -> String {
        "synced \(r.daysSent)d · +\(r.mintedMilli / 1000) pts · ledger +\(r.ledgerPulled) verified"
            + (r.held > 0 ? " · \(r.held)d held" : "") + (r.viaOnion ? " · onion" : " · clearnet")
    }

    /// Account screen's "sync now": sync, then re-check the whole stored chain against the pinned server key.
    func syncNow() async -> String {
        guard let r = await sync() else { return syncNote }
        let chainOk = Ledger.verifyChain((try? store?.ledgerEntries()) ?? [])
        return "Synced \(r.daysSent) day(s) via \(r.viaOnion ? "onion" : "clearnet") · +\(Fmt.fixed(Double(r.mintedMilli) / 1000, 3)) pts · "
            + "\(r.ledgerPulled) new ledger entries · chain \(chainOk ? "verified" : "BROKEN")"
            + (r.held > 0 ? " · \(r.held) day(s) held for review" : "")
    }

    /// A signed API client over the current transport (onion when Tor is on).
    func api() -> ApiClient? {
        identity.map { ApiClient(identity: $0, transport: tor.transport()) }
    }

    /// Account calls need a registered account; the first sync registers it.
    private func ensureRegistered() async throws -> ApiClient {
        if (try? store?.meta("registered")) != "1" { await sync() }
        guard let api = api(), (try? store?.meta("registered")) == "1" else { throw AccountError.offline }
        return api
    }

    enum AccountError: Error { case offline }

    // MARK: Account

    /// The 24 words, only for the account screen's protected view.
    func recoveryWords() -> [String] {
        identity?.phrase.split(separator: " ").map(String.init) ?? []
    }

    func claimHandle(_ name: String) async -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
        do {
            let claimed = try await ensureRegistered().claimUsername(name)
            try? store?.setMeta("username", claimed)
            refresh()
            return "@\(claimed) is yours. Forever."
        } catch let e as ApiError {
            switch e.reason {
            case "taken": return "@\(name) is taken. Pick another."
            case "already_claimed": return "This account already has a handle."
            case "invalid_length": return "5 to 20 characters."
            case "invalid_characters": return "Letters, numbers and _ only."
            case "reserved": return "That handle is reserved."
            default: return "Failed: \(e.status)"
            }
        } catch {
            return Self.offlineMessage
        }
    }

    enum ClanOp { case create, join, leave }

    func clan(_ op: ClanOp, tag: String = "") async -> String {
        do {
            let api = try await ensureRegistered()
            let result: String? = switch op {
            case .create: try await api.clanCreate(tag)
            case .join: try await api.clanJoin(tag)
            case .leave: try await api.clanLeave()
            }
            try? store?.setMeta("clan", result)
            refresh()
            return result.map { "You're [\($0)] now." } ?? "Left the clan."
        } catch let e as ApiError {
            switch e.reason {
            case "invalid_tag": return "Tags are 2–4 letters or digits."
            case "taken": return "That tag exists. Join it instead?"
            case "not_found": return "No clan with that tag. Create it?"
            case "full": return "That clan is full (50)."
            case "in_clan": return "Leave your current clan first."
            default: return "Failed: \(e.status)"
            }
        } catch {
            return Self.offlineMessage
        }
    }

    /// Picks the ASCII picture. Saved here at once; the server copy is best effort (Social sends it again).
    func pickAvatar(_ index: Int) {
        try? store?.setMeta("avatar", String(index))
        refresh()
        Task { try? await api()?.setAvatar(index) }
    }

    func setClan(_ tag: String?) {
        try? store?.setMeta("clan", tag)
        refresh()
    }

    /// Replaces this phone's account with the one behind `phrase`. A bad phrase changes nothing. The sync engine sees
    /// the new owner, clears the old ledger copy and sync floors, and rebuilds history from /v1/history.
    func restore(phrase: String) async -> String {
        do {
            let id = try IdentityStore().restore(phrase: phrase)
            identity = id
            publicKey = id.publicKeyHex
            engine = nil
            guard let r = await sync() else { return "Restored \(keyPrefix)… · sync pending: \(syncNote)" }
            return "Restored account \(keyPrefix)… · pulled \(r.ledgerPulled) ledger entries"
        } catch {
            return "That's not a valid 24-word phrase. Nothing changed."
        }
    }

    /// Deletes the server-side data, then wipes everything on this phone and returns to the consent screen.
    /// The handle stays reserved forever so nobody can take over the name.
    func deleteAccount() async -> String {
        do {
            if (try? store?.meta("registered")) == "1" { try await api()?.deleteAccount() }
        } catch {
            return "Couldn't reach the server, nothing deleted. \(Self.offlineMessage)"
        }
        walks?.shutdown()
        Arti.shared.stop()
        try? IdentityStore().erase()
        try? store?.wipeAll()
        if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        identity = nil
        engine = nil
        walks = nil
        publicKey = ""
        consented = false
        board = BadgeBoard(all: AchievementRules.shared, unlockedAt: [:])
        refresh()
        return "Deleted."
    }

    static let offlineMessage = "Offline or Tor still connecting. Try again in a moment."

    // MARK: Steps

    /// Today's steps per hour for the stats day view, straight from CMPedometer.
    func loadHourly() async {
        if let h = try? await pedometer.hourlySteps(day: localDays.day(Date()), now: Date()) { hourly = h }
    }

    private func readPedometer() async {
        guard let store else { return }
        let window = localDays.lastDays(SyncEngine.windowDays, now: Date())
        if let counts = try? await pedometer.dailySteps(days: window, now: Date()) {
            for (day, n) in counts { try? store.setPedometer(day: day, steps: n) }
        }
        refresh()
    }

    private func startLiveSteps() {
        let today = localDays.day(Date())
        pedometer.startLiveUpdates(from: localDays.calendar.startOfDay(for: Date())) { [weak self] n in
            Task { @MainActor [weak self] in
                guard let self, let store = self.store else { return }
                try? store.setPedometer(day: today, steps: n)
                self.refresh()
            }
        }
    }

    /// Re-reads the database and re-evaluates badges. Cheap: a few small queries.
    func refresh() {
        guard let store else { return }
        do {
            days = try store.dailyCounts()
            lifetimeSteps = days.reduce(0) { $0 + $1.steps }
            let today = localDays.day(Date())
            todaySteps = days.first { $0.day == today }?.steps ?? 0
            points = try store.balanceMilli() / 1000
            handle = try store.meta("username")
            clan = try store.meta("clan")
            avatar = Int(try store.meta("avatar") ?? "0") ?? 0
            coldClimbM = try store.coldClimbM()

            strideM = try store.strideM()   // calibrated from the walker's own GPS walks
            let r = content.active.route!
            route = RouteProgress(route: r, position: r.positionAt(Double(lifetimeSteps) * strideM), strideM: strideM)

            guard identity != nil else { return }   // after account deletion: nothing to evaluate
            let metrics = Metrics.compute(days: days, walks: try store.walkFacts(), onionSteps: try store.onionSteps(),
                                          postcards: route.position.unlocked.count, today: today)
            let earned = AchievementRules.unlocked(AchievementRules.shared, metrics: metrics).map(\.id)
            try store.unlock(earned, at: Int64(Date().timeIntervalSince1970 * 1000))   // keeps first unlock times
            board = BadgeBoard(all: AchievementRules.shared, unlockedAt: try store.unlocks())
        } catch {
            syncNote = "database error · \(error)"
        }
    }
}
