import ActivityKit
import CoreLocation
import CoreMotion
import Foundation
import Observation
import UIKit
import UserNotifications
import VeilWalkerActivity
import VeilWalkerCore

/// Live walks: the iOS take on Android's WalkService. While the app is open it watches CoreMotion and starts a walk
/// after 27 s of continuous steps (or at once when the walk line is tapped). During the walk, GPS (background location
/// mode) keeps the app alive, so CMPedometer, the motion sensors and Tor keep running with the screen off. Every 10 s
/// a window is scored and filed in a tier: onion when Tor is proven up, GPS with a fix, otherwise sensor.
/// No "End walk" button: 4.5 min of stillness ends it, with a red-light notice at 3 min.
@MainActor @Observable
final class WalkController: NSObject {
    private(set) var status: WalkStatus = .idle
    private(set) var gpsOn = false
    /// Ticks once a second while anything is going on, so the walk line's clock moves.
    private(set) var nowMs: Int64 = 0

    private let store: Store
    private let tor: TorController
    private let weather: WeatherController
    private let onEnded: @MainActor () async -> Void

    private let pedometer = CMPedometer()
    private let dayPedometer = CMPedometer()
    private let motion = CMMotionManager()
    private let activity = CMMotionActivityManager()
    private let location = CLLocationManager()
    private let altimeter = CMAltimeter()
    private let days = LocalDays()
    private var climb = ColdClimb()
    private var minTempF: Int?

    private var tracker: WalkTracker?
    private var mode: WalkMode = .active
    private var walkId: Int64?
    private var verifier = WalkVerifier()
    private var gps = GpsSmoother()
    private var walkSteps: Int64 = 0          // pedometer steps since the tracker started
    private var windowSteps: Int64 = 0        // walkSteps at the last window
    private var windowStartMs: Int64 = 0
    private var verdictSum = 0.0
    private var verdictCount = 0
    private var torUsed = false
    private var automotive = false
    /// CoreMotion's latest reading says on foot. It only reports changes, so this is how a failed confirm retries.
    private var onFoot = false
    private var watching = false
    private var ticker: Task<Void, Never>?
    private var lastSource: StepSource = .activeSensor
    private var liveActivity: Activity<WalkActivityAttributes>?
    private var accel: [Float] = []
    private var gx: [Float] = []
    private var gy: [Float] = []
    private var gz: [Float] = []

    init(store: Store, tor: TorController, weather: WeatherController, onEnded: @escaping @MainActor () async -> Void) {
        self.store = store
        self.tor = tor
        self.weather = weather
        self.onEnded = onEnded
        super.init()
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.pausesLocationUpdatesAutomatically = false
        try? store.closeOpenWalks(nowMs: Self.now())   // walks left open when iOS killed the app
        if alwaysEnabled { startAlwaysWatch() }
    }

    // MARK: Hands-free walks with the app closed (opt-in "Always")

    private static let alwaysKey = "alwaysWalks"

    /// The user opted in to walks starting while the app is closed. The switch lives on the account screen.
    var alwaysEnabled: Bool { UserDefaults.standard.bool(forKey: Self.alwaysKey) }

    func setAlways(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.alwaysKey)
        if on {
            location.requestAlwaysAuthorization()
            startAlwaysWatch()
        } else {
            location.stopMonitoringSignificantLocationChanges()
        }
    }

    /// Significant-change monitoring relaunches the app in the background after a move of a few hundred metres;
    /// it then confirms the walk with the pedometer exactly as in the foreground (handoff §6, "Live walks").
    private func startAlwaysWatch() {
        guard location.authorizationStatus == .authorizedAlways || location.authorizationStatus == .notDetermined,
              CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        location.startMonitoringSignificantLocationChanges()
    }

    /// A significant move while closed or in the background: check whether we're on foot.
    private func onSignificantMove() {
        guard tracker == nil, alwaysEnabled, location.authorizationStatus == .authorizedAlways,
              UIApplication.shared.applicationState != .active else { return }
        begin(manual: false)
    }

    var isWalking: Bool { tracker?.phase == .walking }
    var isBusy: Bool { tracker != nil }
    var line: String { status.line(nowMs: nowMs) }

    // MARK: Foreground watching (auto start)

    /// App in the foreground: start a walk when CoreMotion sees walking.
    func startWatching() {
        guard !watching, CMMotionActivityManager.isActivityAvailable() else { return }
        watching = true
        activity.startActivityUpdates(to: .main) { [weak self] a in
            guard let a else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.automotive = a.automotive && a.confidence != .low
                self.onFoot = (a.walking || a.running) && !a.automotive && a.confidence != .low
                if self.onFoot && self.tracker == nil {
                    self.begin(manual: false)
                }
            }
        }
    }

    /// App leaving the foreground. A walk with GPS keeps going in the background; anything else stops here
    /// (iOS would suspend it anyway), and the retroactive scan picks the time up later.
    func appDidEnterBackground() {
        if watching && !isWalking {
            activity.stopActivityUpdates()
            watching = false
        }
        guard let tracker else { return }
        if tracker.phase != .walking {
            abandon()
        } else if !gpsOn {
            Task { await finish(atMs: tracker.lastStepMs) }
        }
    }

    /// A minute of Snowflake hosting while walking: frost for the badge frames, on this walk's record.
    func creditSnowflakeMinute() {
        guard isWalking, let walkId else { return }
        try? store.addWalkSnowflakeMinutes(id: walkId, minutes: 1)
    }

    /// Account deleted: stop everything, including the significant-change wake.
    func shutdown() {
        if tracker != nil { stopSensors() }
        activity.stopActivityUpdates()
        watching = false
        location.stopMonitoringSignificantLocationChanges()
        Task { await endActivity() }
    }

    // MARK: Starting

    /// Tapping the walk line: a walk starts now, no confirm phase (Android's startWalkNow).
    func startNow() {
        guard tracker == nil else { return }
        begin(manual: true)
    }

    private func begin(manual: Bool) {
        let now = Self.now()
        tracker = manual ? .walking(at: now) : .confirming(at: now)
        walkSteps = 0
        windowSteps = 0
        pedometer.startUpdates(from: Date(timeIntervalSince1970: Double(now) / 1000)) { [weak self] data, _ in
            guard let data else { return }
            let n = data.numberOfSteps.int64Value
            let at = Int64(data.endDate.timeIntervalSince1970 * 1000)
            Task { @MainActor in self?.onPedometer(steps: n, atMs: at) }
        }
        startTicker()
        // Confirming in the background needs GPS running, or iOS suspends the app before 27 s pass.
        if !manual && UIApplication.shared.applicationState != .active { startLocation() }
        if manual { Task { await startWalk(at: now) } }
    }

    private func onPedometer(steps: Int64, atMs: Int64) {
        guard tracker != nil, steps > walkSteps else { return }
        let added = steps - walkSteps
        walkSteps = steps
        tracker?.steps(at: atMs, added: added)
    }

    /// Confirmed (or tapped): open the session, bring up GPS, motion and Tor.
    private func startWalk(at startMs: Int64) async {
        mode = tor.enabled ? .onion : .active
        walkId = try? store.insertWalk(mode: mode, startMs: startMs)
        verifier = WalkVerifier()
        gps = GpsSmoother()
        verdictSum = 0
        verdictCount = 0
        torUsed = false
        climb = ColdClimb()
        minTempF = nil
        windowStartMs = startMs
        startMotion()
        startAltimeter()
        Task { [weather] in   // after Tor has had a moment to come up, as Android does
            try? await Task.sleep(for: .seconds(30))
            await weather.refresh()
        }
        if !gpsOn { startLocation() }
        requestNotificationPermission()
        startActivity(at: startMs)
        if tor.enabled { Task { await tor.wake() } }
    }

    // MARK: The clock

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var lastWindow = Self.now()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.tracker != nil else { return }
                let now = Self.now()
                await self.tick(now: now)
                if self.isWalking, now - lastWindow >= WalkRules.windowMs {
                    lastWindow = now
                    await self.closeWindow(now: now)
                }
            }
        }
    }

    private func tick(now: Int64) async {
        nowMs = now
        guard var t = tracker else { return }
        let event = t.tick(now: now)
        tracker = t
        switch event {
        case .started: await startWalk(at: t.startMs)
        case .abandoned: abandon()
        case .redLight: notifyRedLight(); updateActivity()
        case .resumed: clearRedLight(); updateActivity()
        case .ended: await finish(atMs: t.lastStepMs)
        case nil: break
        }
        if let t = tracker {
            let before = status
            status = t.status(now: now, mode: mode, steps: walkSteps, gps: gpsOn)
            if Self.isPaused(before) != Self.isPaused(status) { updateActivity() }   // walking ↔ paused
        }
    }

    // MARK: Windows

    /// Every 10 s: score the window and file its steps in a tier. Mirrors WalkService.windowLoop().
    private func closeWindow(now: Int64) async {
        guard let walkId else { return }
        let delta = walkSteps - windowSteps
        windowSteps = walkSteps
        let check = gps.check(nowMs: now)
        // Onion only for a window where Tor was proven up; the server only honours it over the onion service anyway.
        let source: StepSource = tor.enabled && tor.phase == .ok ? .onion : check.speedKmh != nil ? .activeGPS : .activeSensor
        let verdict = verifier.score(
            SensorWindow(steps: Int(delta), durationS: Double(now - windowStartMs) / 1000, accelMagnitudes: accel,
                         gyroX: gx, gyroY: gy, gyroZ: gz),
            gps: check, automotive: automotive)
        accel.removeAll(keepingCapacity: true); gx.removeAll(keepingCapacity: true)
        gy.removeAll(keepingCapacity: true); gz.removeAll(keepingCapacity: true)

        // Hidden Peaks: on a freezing walk every step climbs a virtual 10% trail; real hills add on top (startAltimeter).
        climb.steps(delta, freezing: weather.freezing)
        if weather.enabled, let t = weather.weather?.tempF { minTempF = min(minTempF ?? t, t) }
        try? store.setWalkWeather(id: walkId, coldClimbM: climb.climbedM, minTempF: minTempF)

        if delta > 0 {
            await refreshTodayPedometer(now: now)
            _ = try? store.recordWalkSteps(StepInterval(day: days.day(Self.date(now)), startMs: windowStartMs, endMs: now, steps: delta,
                                                    source: source, walkId: walkId, verdict: verdict.score))
            verdictSum += Double(verdict.score)
            verdictCount += 1
            torUsed = torUsed || source == .onion
        }
        lastSource = source
        updateActivity()
        windowStartMs = now
        // GPS drift indoors, or a ride, can add distance no feet covered. Nobody covers more than 2 m a step, even
        // sprinting, so cap it there; otherwise distance badges unlock for nothing (2 km for 132 steps, 31 Oct 2026).
        let distanceM = min(gps.totalDistanceM, Double(walkSteps) * Self.maxMetresPerStep)
        try? store.updateWalk(id: walkId, steps: walkSteps, distanceM: distanceM,
                              verdict: verdictCount == 0 ? 1 : Float(verdictSum / Double(verdictCount)), torUsed: torUsed)
    }

    /// The day's true total must include the window before it's credited (walk steps come out of it).
    private func refreshTodayPedometer(now: Int64) async {
        let start = days.calendar.startOfDay(for: Self.date(now))
        let n: Int64? = await withCheckedContinuation { c in
            dayPedometer.queryPedometerData(from: start, to: Self.date(now)) { data, _ in
                c.resume(returning: data?.numberOfSteps.int64Value)
            }
        }
        if let n { try? store.setPedometer(day: days.day(Self.date(now)), steps: n) }
    }

    // MARK: Ending

    private func finish(atMs endMs: Int64) async {
        guard tracker != nil else { return }
        if isWalking { await closeWindow(now: Self.now()) }
        if let walkId { try? store.endWalk(id: walkId, endMs: max(endMs, tracker?.startMs ?? endMs)) }
        stopSensors()
        clearRedLight()
        await endActivity()
        await onEnded()   // sync right away, while the app is still awake
    }

    /// Auto-detected movement that never became a walk: leave quietly; the steps stay passive. If CoreMotion still
    /// says on foot (it won't report again until that changes), try again in a few seconds.
    private func abandon() {
        stopSensors()
        guard watching, onFoot else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.watching, self.onFoot, self.tracker == nil else { return }
            self.begin(manual: false)
        }
    }

    // MARK: Live Activity (the lock-screen walk card, iOS's ongoing notification)

    private func activityState() -> WalkActivityAttributes.ContentState {
        let tier = switch lastSource {
        case .onion: "onion"
        case .activeGPS: "gps"
        default: "sensor"
        }
        let phase: WalkActivityAttributes.ContentState.Phase
        if tracker?.redLightShown == true { phase = .redLight }
        else if Self.isPaused(status) { phase = .paused }
        else { phase = .walking }
        let still = phase == .walking ? nil : tracker.map { Self.date($0.lastStepMs) }
        return .init(tier: tier, steps: walkSteps, phase: phase, stillSince: still)
    }

    /// Must run in the foreground (iOS rule); walks that start in the background show the card when the app opens.
    private func startActivity(at startMs: Int64) {
        guard liveActivity == nil, ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }
        liveActivity = try? Activity.request(
            attributes: WalkActivityAttributes(mode: mode.rawValue, startedAt: Self.date(startMs)),
            content: .init(state: activityState(), staleDate: nil))
    }

    private func updateActivity() {
        guard let liveActivity else { return }
        let state = activityState()
        Task { await liveActivity.update(.init(state: state, staleDate: nil)) }
    }

    private func endActivity() async {
        await liveActivity?.end(nil, dismissalPolicy: .immediate)
        liveActivity = nil
    }

    /// App came back to the foreground mid-walk: show the card if the walk started in the background.
    func appDidBecomeActive() {
        if isWalking, liveActivity == nil, let t = tracker { startActivity(at: t.startMs) }
    }

    private static func isPaused(_ s: WalkStatus) -> Bool {
        if case .paused = s { return true }
        return false
    }

    private func stopSensors() {
        ticker?.cancel()
        ticker = nil
        pedometer.stopUpdates()
        motion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        gpsOn = false
        tracker = nil
        walkId = nil
        status = .idle
    }

    // MARK: Sensors

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50   // ~200 samples per window, as Android's SENSOR_DELAY_GAME
        motion.startDeviceMotionUpdates(to: OperationQueue()) { [weak self] m, _ in
            guard let m else { return }
            // Total acceleration (user + gravity) in m/s², like Android's TYPE_ACCELEROMETER magnitude.
            let ax = m.userAcceleration.x + m.gravity.x, ay = m.userAcceleration.y + m.gravity.y, az = m.userAcceleration.z + m.gravity.z
            let mag = Float((ax * ax + ay * ay + az * az).squareRoot() * 9.81)
            let r = m.rotationRate
            Task { @MainActor in
                guard let self else { return }
                self.accel.append(mag)
                self.gx.append(Float(r.x)); self.gy.append(Float(r.y)); self.gz.append(Float(r.z))
            }
        }
    }

    /// The barometer, for real climb on freezing walks. Relative altitude is enough: only rises count.
    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: OperationQueue()) { [weak self] data, _ in
            guard let m = data?.relativeAltitude.doubleValue else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.climb.altitude(m, freezing: self.weather.freezing)
            }
        }
    }

    /// GPS for distance and the vehicle veto. When In Use is enough: started in the foreground, it keeps running
    /// (blue pill) after the screen locks. Without it the walk is sensor-only and ends when the app leaves.
    private func startLocation() {
        switch location.authorizationStatus {
        case .notDetermined:
            location.requestWhenInUseAuthorization()   // continues in locationManagerDidChangeAuthorization
        case .authorizedWhenInUse, .authorizedAlways:
            location.allowsBackgroundLocationUpdates = true
            location.showsBackgroundLocationIndicator = true
            location.startUpdatingLocation()
            gpsOn = true
        default:
            gpsOn = false
        }
    }

    // MARK: Red light

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyRedLight() {
        let c = UNMutableNotificationContent()
        c.title = "Stopped for 3 min. Red light?"
        c.body = "The walk ends at 4:30 still unless you keep going."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "red-light", content: c, trigger: nil))
    }

    private func clearRedLight() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["red-light"])
    }

    // MARK: Time

    static let maxMetresPerStep = 2.0

    static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
}

extension WalkController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.walkId != nil && !self.gpsOn { self.startLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in if self.tracker == nil { self.onSignificantMove() } }
        let fixes = locations.map {
            Fix(epochMs: Int64($0.timestamp.timeIntervalSince1970 * 1000), lat: $0.coordinate.latitude, lon: $0.coordinate.longitude,
                accuracyM: $0.horizontalAccuracy, isMock: $0.sourceInformation?.isSimulatedBySoftware ?? false)
        }
        Task { @MainActor in fixes.forEach(self.gps.add) }
    }
}
