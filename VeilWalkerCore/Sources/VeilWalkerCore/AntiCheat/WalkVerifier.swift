import Foundation

/// One 10 s analysis window built from raw motion samples during a live walk.
public struct SensorWindow: Sendable {
    public let steps: Int
    public let durationS: Double
    public let accelMagnitudes: [Float]   // |a| samples, m/s²
    public let gyroX: [Float]
    public let gyroY: [Float]
    public let gyroZ: [Float]

    public init(steps: Int, durationS: Double, accelMagnitudes: [Float] = [], gyroX: [Float] = [], gyroY: [Float] = [],
                gyroZ: [Float] = []) {
        self.steps = steps
        self.durationS = durationS
        self.accelMagnitudes = accelMagnitudes
        self.gyroX = gyroX
        self.gyroY = gyroY
        self.gyroZ = gyroZ
    }
}

public enum CheatFlag: String, Sendable {
    case cadenceOutOfBand, cadenceTooRegular, lowAccelVariance, singleAxisRotation, vehicleSpeed, mockLocation
    /// iOS only: CoreMotion says the phone is in a vehicle (handoff §7: "add CMMotionActivity automotive as a veto").
    case automotive
}

public struct WindowVerdict: Sendable {
    public let score: Float
    public let flags: Set<CheatFlag>
}

/// Result of the smoothed GPS check for a window; nil speed means "no trustworthy fix" (dead zone).
public struct GpsCheck: Equatable, Sendable {
    public let speedKmh: Double?
    public let isMock: Bool

    public init(speedKmh: Double?, isMock: Bool) {
        self.speedKmh = speedKmh
        self.isMock = isMock
    }
}

/// On-device walk verification; only the resulting verdict leaves the phone. Same thresholds as Android's
/// WalkVerifier.kt: penalise only cadence over 3.2 steps/s (8+ steps), rigs, vehicle speed and mock location.
public final class WalkVerifier {
    static let minStepsForCadence = 8
    static let maxCadence = 3.2   // steps/s; brisk walking is ~2.0, running tops out near 3

    private var recentCadences: [Double] = []

    public init() {}

    public func score(_ w: SensorWindow, gps: GpsCheck?, automotive: Bool = false) -> WindowVerdict {
        var flags = Set<CheatFlag>()
        var score: Float = 1

        // 1. Cadence: only too-fast is suspicious (shakers inflate steps). Slow windows are crossings and strolls.
        let cadence = w.durationS > 0 ? Double(w.steps) / w.durationS : 0
        if w.steps >= Self.minStepsForCadence && cadence > Self.maxCadence { flags.insert(.cadenceOutOfBand); score -= 0.4 }
        recentCadences.append(cadence)
        if recentCadences.count > 12 { recentCadences.removeFirst() }
        if recentCadences.count >= 6 && Self.stdDev(recentCadences) < 0.015 { flags.insert(.cadenceTooRegular); score -= 0.3 }

        // 2. Accelerometer: real heel strikes give vertical variance; a gently shaken phone does not.
        if w.accelMagnitudes.count > 10 && Self.variance(w.accelMagnitudes) < 0.25 { flags.insert(.lowAccelVariance); score -= 0.3 }

        // 3. Gyro: pendulum/swing rigs rotate around one dominant axis; pocket/hand carry is messy.
        let ex = Self.energy(w.gyroX), ey = Self.energy(w.gyroY), ez = Self.energy(w.gyroZ)
        let total = ex + ey + ez
        if total > 0.05 && max(ex, ey, ez) / total > 0.92 { flags.insert(.singleAxisRotation); score -= 0.35 }

        // 4. GPS is a veto signal only. Dead zones and rural gaps are never penalised.
        if let gps {
            if gps.isMock { flags.insert(.mockLocation); score -= 1 }
            if let v = gps.speedKmh, v > 9.0, (1.2...3.2).contains(cadence) { flags.insert(.vehicleSpeed); score -= 0.6 }
        }
        // 5. iOS: CoreMotion's own vehicle detection, weighted like vehicle speed.
        if automotive && !flags.contains(.vehicleSpeed) { flags.insert(.automotive); score -= 0.6 }

        return WindowVerdict(score: min(max(score, 0), 1), flags: flags)
    }

    private static func variance(_ a: [Float]) -> Float {
        let m = a.reduce(0, +) / Float(a.count)
        return a.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Float(a.count)
    }

    private static func stdDev(_ a: [Double]) -> Double {
        let m = a.reduce(0, +) / Double(a.count)
        return (a.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(a.count)).squareRoot()
    }

    private static func energy(_ a: [Float]) -> Float { a.reduce(0) { $0 + abs($1) } }
}
