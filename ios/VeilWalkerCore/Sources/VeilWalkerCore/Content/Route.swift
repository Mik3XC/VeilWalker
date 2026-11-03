import Foundation

public struct LatLng: Codable, Equatable, Sendable {
    public let lat: Double
    public let lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

/// A place on the route. Its postcard unlocks when the walker's virtual position reaches it.
public struct Milestone: Equatable, Sendable {
    public let name: String
    public let point: LatLng
    public let postcard: String
}

/// A virtual route: a polyline through its milestones. Progress needs nothing but a distance in metres:
/// no GPS, no map tiles, nothing leaves the phone. Mirrors core/route Route.kt.
public struct Route: Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let milestones: [Milestone]
    /// Cumulative distance (m) at each milestone; the last value is the route length.
    public let cumulativeM: [Double]

    public init(id: String, title: String, subtitle: String, milestones: [Milestone]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.milestones = milestones
        var c = [0.0]
        for i in milestones.indices.dropFirst() {
            c.append(c[i - 1] + Self.haversineM(milestones[i - 1].point, milestones[i].point))
        }
        cumulativeM = c
    }

    public var lengthM: Double { cumulativeM.last ?? 0 }

    public struct Position: Equatable, Sendable {
        public let point: LatLng
        public let travelledM: Double
        public let unlocked: [Milestone]
        public let next: Milestone?
        public let toNextM: Double?
        public let finished: Bool
    }

    public func positionAt(_ distanceM: Double) -> Position {
        let d = min(max(distanceM, 0), lengthM)
        // Index of the last milestone at or before d (binary search on the cumulative distances).
        var lo = 0
        var hi = cumulativeM.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cumulativeM[mid] <= d { lo = mid } else { hi = mid - 1 }
        }
        let points = milestones.map(\.point)
        let point: LatLng
        if lo == points.count - 1 {
            point = points[lo]
        } else {
            let seg = cumulativeM[lo + 1] - cumulativeM[lo]
            let t = seg == 0 ? 0 : (d - cumulativeM[lo]) / seg
            point = LatLng(lat: points[lo].lat + t * (points[lo + 1].lat - points[lo].lat),
                           lng: points[lo].lng + t * (points[lo + 1].lng - points[lo].lng))
        }
        let next = lo + 1 < milestones.count ? milestones[lo + 1] : nil
        return Position(point: point, travelledM: d, unlocked: Array(milestones.prefix(lo + 1)), next: next,
                        toNextM: next.map { _ in cumulativeM[lo + 1] - d }, finished: d >= lengthM)
    }

    public static func haversineM(_ a: LatLng, _ b: LatLng) -> Double {
        let r = 6_371_000.0
        let rad = Double.pi / 180
        let dLat = (b.lat - a.lat) * rad
        let dLng = (b.lng - a.lng) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * rad) * cos(b.lat * rad) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * atan2(sqrt(h), sqrt(1 - h))
    }
}

public struct RouteProgress: Sendable {
    public let route: Route
    public let position: Route.Position
    public let strideM: Double

    public init(route: Route, position: Route.Position, strideM: Double) {
        self.route = route
        self.position = position
        self.strideM = strideM
    }
}

/// km anywhere in the app = true steps × the walker's stride. Mirrors RouteRepository.kt.
public enum Stride {
    public static let defaultM = 0.75

    public static func km(_ steps: Int64, strideM: Double) -> Double { Double(steps) * strideM / 1000 }

    /// Needs ~500 GPS-measured steps before trusting the user's own stride; clamped to human range.
    public static func from(distanceM: Double?, steps: Int64?) -> Double {
        guard let distanceM, let steps, steps >= 500 else { return defaultM }
        return min(max(distanceM / Double(steps), 0.5), 1.0)
    }
}
