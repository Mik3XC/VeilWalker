import Foundation

/// Outside temperature, car-dashboard style: a snowflake at 30°F or below. Mirrors Android's Weather.
public struct Weather: Codable, Equatable, Sendable {
    public static let freezingF = 30

    public let tempF: Int
    public let fetchedAtMs: Int64

    public init(tempF: Int, fetchedAtMs: Int64) {
        self.tempF = tempF
        self.fetchedAtMs = fetchedAtMs
    }

    public var freezing: Bool { tempF <= Self.freezingF }

    /// The home screen corner: `52°F`, or ice-blue `❄ 28°F` when freezing.
    public var label: String { (freezing ? "❄ " : "") + "\(tempF)°F" }
}

/// The US National Weather Service (api.weather.gov: public domain, no key, no account). Same two-step lookup as
/// Android's WeatherRepository: /points/{lat},{lon} gives the hourly forecast URL, whose first period is "now".
/// The location is rounded to 0.1° (about 11 km) before it leaves the phone.
public enum NWS {
    /// NWS asks every app to identify itself; this names the app, never the user.
    public static let userAgent = "VeilWalker/1.0 (premiselayer@gmail.com)"
    public static let maxAgeMs: Int64 = 30 * 60_000

    public static func round(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    public static func pointsURL(lat: Double, lon: Double) -> URL {
        URL(string: "https://api.weather.gov/points/\(Fmt.fixed(round(lat), 1)),\(Fmt.fixed(round(lon), 1))")!
    }

    public static func hourlyURL(fromPoints data: Data) throws -> URL {
        guard let props = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["properties"] as? [String: Any],
              let s = props["forecastHourly"] as? String, let url = URL(string: s),
              url.scheme == "https", url.host == "api.weather.gov" else { throw NWSError.badResponse }
        return url
    }

    public static func currentTempF(fromHourly data: Data) throws -> Int {
        guard let props = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["properties"] as? [String: Any],
              let now = (props["periods"] as? [[String: Any]])?.first,
              let t = (now["temperature"] as? NSNumber)?.doubleValue else { throw NWSError.badResponse }
        return Int((now["temperatureUnit"] as? String == "C" ? t * 9 / 5 + 32 : t).rounded())
    }

    public enum NWSError: Error { case badResponse }
}

/// Hidden Peaks climb, counted only on freezing walks: every step is 7 cm of virtual 10% trail, and real hills from
/// the barometer add on top, banked once the smoothed altitude rises 3 m and capped at 0.25 m per step taken, so
/// lifts, cars and weather fronts add nothing. Same constants as Android's WalkService.onPressure.
public struct ColdClimb: Sendable {
    public static let virtualRisePerStepM = 0.07
    public static let climbStepM = 3.0
    public static let maxRisePerStepM = 0.25

    public private(set) var climbedM = 0.0
    private var altSmooth = Double.nan
    private var climbRef = Double.nan
    private var stepsSinceRef: Int64 = 0

    public init() {}

    /// Steps from a walk window. Virtual climb only counts while freezing.
    public mutating func steps(_ n: Int64, freezing: Bool) {
        stepsSinceRef += n
        if freezing && n > 0 { climbedM += Double(n) * Self.virtualRisePerStepM }
    }

    /// A barometric altitude reading in metres (CMAltimeter's relative altitude works: only differences matter).
    public mutating func altitude(_ m: Double, freezing: Bool) {
        altSmooth = altSmooth.isNaN ? m : altSmooth + 0.1 * (m - altSmooth)
        if climbRef.isNaN {
            climbRef = altSmooth
            return
        }
        if altSmooth >= climbRef + Self.climbStepM {
            let credited = min(altSmooth - climbRef, Double(stepsSinceRef) * Self.maxRisePerStepM)
            if freezing { climbedM += credited }
            climbRef = altSmooth
            stepsSinceRef = 0
        } else if altSmooth <= climbRef - Self.climbStepM {
            climbRef = altSmooth
            stepsSinceRef = 0
        }
    }
}
