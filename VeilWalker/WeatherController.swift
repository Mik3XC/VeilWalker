import CoreLocation
import Foundation
import Observation
import VeilWalkerCore
import VeilWalkerTor

/// Outside temperature for the home screen corner and the Hidden Peaks. Mirrors Android's WeatherRepository:
/// opt-in (the only feature that sends any location off the phone), location rounded to 0.1° (~11 km), sent straight
/// to api.weather.gov over a Tor exit when Tor is on (and not at all until Tor is up), only the temperature kept,
/// at most every 30 minutes. Not WeatherKit: that sends the location to Apple.
@MainActor @Observable
final class WeatherController: NSObject {
    private(set) var enabled: Bool
    private(set) var weather: Weather?

    private let tor: TorController
    private let location = CLLocationManager()
    private var refreshing = false
    private static let enabledKey = "weatherEnabled"
    private static let readingKey = "weatherReading"

    init(tor: TorController) {
        self.tor = tor
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        weather = UserDefaults.standard.data(forKey: Self.readingKey).flatMap { try? JSONDecoder().decode(Weather.self, from: $0) }
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyReduced   // coarse is all this needs
    }

    var freezing: Bool { enabled && weather?.freezing == true }

    /// Turning it off also forgets the last reading: no snowflake and no cold climb until it's back on.
    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
            Task { await refresh(force: true) }
        } else {
            weather = nil
            UserDefaults.standard.removeObject(forKey: Self.readingKey)
        }
    }

    /// Refreshes if the reading is over 30 min old. Safe to call often; failures keep the last reading.
    func refresh(force: Bool = false) async {
        guard enabled, !refreshing else { return }
        if !force, let w = weather, WalkController.now() - w.fetchedAtMs < NWS.maxAgeMs { return }
        guard let fix = location.location else {
            location.requestLocation()   // one coarse fix; locationManager(didUpdateLocations:) retries the refresh
            return
        }
        // Tor on but not proven up yet: wait rather than send the location in the clear.
        if tor.enabled && tor.phase != .ok { return }
        refreshing = true
        defer { refreshing = false }
        let headers = ["User-Agent": NWS.userAgent, "Accept": "application/geo+json"]
        do {
            let points = try await get(NWS.pointsURL(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude), headers)
            let tempF = try NWS.currentTempF(fromHourly: try await get(NWS.hourlyURL(fromPoints: points), headers))
            let w = Weather(tempF: tempF, fetchedAtMs: WalkController.now())
            weather = w
            UserDefaults.standard.set(try? JSONEncoder().encode(w), forKey: Self.readingKey)
        } catch {
            // Keep the last reading; the next foreground or walk tries again.
        }
    }

    private func get(_ url: URL, _ headers: [String: String]) async throws -> Data {
        if tor.enabled {
            let r = try await TorExit.get(url, headers: headers)
            guard r.status == 200 else { throw NWS.NWSError.badResponse }
            return r.body
        }
        var req = URLRequest(url: url, timeoutInterval: 45)
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NWS.NWSError.badResponse }
        return data
    }
}

extension WeatherController: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in await self.refresh(force: true) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in if self.enabled && self.weather == nil { await self.refresh(force: true) } }
    }
}
