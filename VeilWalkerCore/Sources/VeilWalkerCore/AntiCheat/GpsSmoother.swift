import Foundation

public struct Fix: Sendable {
    public let epochMs: Int64
    public let lat: Double
    public let lon: Double
    public let accuracyM: Double
    public let isMock: Bool

    public init(epochMs: Int64, lat: Double, lon: Double, accuracyM: Double, isMock: Bool) {
        self.epochMs = epochMs
        self.lat = lat
        self.lon = lon
        self.accuracyM = accuracyM
        self.isMock = isMock
    }
}

/// Handles ±10 m jitter, rural sparsity and dead zones. Same model as Android's GpsSmoother.kt:
/// drops fixes worse than `maxAccuracyM`, smooths with a 1-D Kalman weighted by reported accuracy, reports speed over
/// a `windowMs` span instead of fix-to-fix, and returns nil speed without enough good fixes (sensor-only, not cheating).
public final class GpsSmoother {
    private struct Smoothed { let epochMs: Int64; let lat: Double; let lon: Double }

    private let maxAccuracyM: Double
    private let windowMs: Int64
    private let processNoiseMps: Double
    private var history: [Smoothed] = []
    private var lat = 0.0
    private var lon = 0.0
    private var varianceM2 = -1.0
    private var lastMs: Int64 = 0
    private var sawMock = false

    public private(set) var totalDistanceM = 0.0

    public init(maxAccuracyM: Double = 25, windowMs: Int64 = 30_000, processNoiseMps: Double = 3.0) {
        self.maxAccuracyM = maxAccuracyM
        self.windowMs = windowMs
        self.processNoiseMps = processNoiseMps
    }

    public func add(_ f: Fix) {
        if f.isMock { sawMock = true }
        guard f.accuracyM >= 0, f.accuracyM <= maxAccuracyM else { return }   // iOS reports -1 for an invalid fix

        let acc2 = f.accuracyM * f.accuracyM
        if varianceM2 < 0 {
            lat = f.lat; lon = f.lon; varianceM2 = acc2; lastMs = f.epochMs
        } else {
            let dt = Double(max(f.epochMs - lastMs, 0)) / 1000
            varianceM2 += dt * processNoiseMps * processNoiseMps
            let k = varianceM2 / (varianceM2 + acc2)
            let prev = history.last
            lat += k * (f.lat - lat)
            lon += k * (f.lon - lon)
            varianceM2 *= (1 - k)
            lastMs = f.epochMs
            if let prev { totalDistanceM += Route.haversineM(LatLng(lat: prev.lat, lng: prev.lon), LatLng(lat: lat, lng: lon)) }
        }
        history.append(Smoothed(epochMs: f.epochMs, lat: lat, lon: lon))
        while history.count > 2, f.epochMs - history[0].epochMs > windowMs * 2 { history.removeFirst() }
    }

    public func check(nowMs: Int64) -> GpsCheck {
        let recent = history.filter { nowMs - $0.epochMs <= windowMs }
        guard recent.count >= 3, let first = recent.first, let last = recent.last else { return GpsCheck(speedKmh: nil, isMock: sawMock) }
        let dtS = Double(last.epochMs - first.epochMs) / 1000
        guard dtS >= 10 else { return GpsCheck(speedKmh: nil, isMock: sawMock) }
        let d = Route.haversineM(LatLng(lat: first.lat, lng: first.lon), LatLng(lat: last.lat, lng: last.lon))
        return GpsCheck(speedKmh: d / dtS * 3.6, isMock: sawMock)
    }
}
