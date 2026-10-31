import Foundation

/// Card rarity, from the street-level operators up to the one boss card.
public enum Rarity: String, Codable, Comparable, Sendable {
    case rare = "RARE", epic = "EPIC", legendary = "LEGENDARY", boss = "BOSS"

    public var label: String { rawValue }

    private var order: Int { [.rare, .epic, .legendary, .boss].firstIndex(of: self)! }
    public static func < (a: Rarity, b: Rarity) -> Bool { a.order < b.order }
}

/// A collectible outlaw card: real history, game-mechanic step target. Collected when true lifetime steps reach `steps`.
public struct OutlawCard: Codable, Equatable, Sendable {
    public let name: String
    public let collection: String
    public let rarity: Rarity
    public let steps: Int64
    public let quote: String
}

/// A Walk for Freedom route or an Outlaws on Foot card. Only journeys with a `route` are walkable; every one has a
/// detail page with `facts`. Mirrors core/route Journeys.kt.
public struct Journey: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let km: Int
    public let postcards: Int
    public let teaser: String
    /// How it unlocks, shown on the locked card.
    public let unlock: String
    public let route: Route?
    public let facts: [String]
    public let why: String
    public let card: OutlawCard?
}

/// A hidden mountain card, revealed by climbing its height on freezing walks. Mirrors Peaks.kt.
public struct Peak: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let region: String
    public let heightM: Int
    public let quote: String
    public let facts: [String]
    /// The K2 easter egg: drawn as the Demon and awards the secret Crowley Award.
    public let demon: Bool

    public var heightFt: Int { Int(Double(heightM) * 3.28084) }
}

/// All journey, outlaw and peak copy, loaded from Resources/content/content.json. That file is generated from the
/// Android sources by tools/export_content.py, so both apps show the same words.
public struct ContentLibrary: Sendable {
    public let freedom: [Journey]
    public let outlaws: [Journey]
    public let peaks: [Peak]
    public let peaksTitle: String

    public static let shared: ContentLibrary = {
        guard let url = Bundle.module.url(forResource: "content", withExtension: "json", subdirectory: "content"),
              let data = try? Data(contentsOf: url),
              let lib = try? ContentLibrary(json: data) else {
            preconditionFailure("content.json missing or invalid")
        }
        return lib
    }()

    /// Walk for Freedom first, then the outlaw cards as the endgame past the Silk Road.
    public var all: [Journey] { freedom + outlaws }
    public var active: Journey { all.first { $0.route != nil }! }
    public var locked: [Journey] { all.filter { $0.route == nil } }
    public func journey(id: String) -> Journey? { all.first { $0.id == id } }
    public func peak(id: String) -> Peak? { peaks.first { $0.id == id } }

    public init(json: Data) throws {
        let doc = try JSONDecoder().decode(Doc.self, from: json)
        let routes = Dictionary(uniqueKeysWithValues: doc.routes.map { r in
            (r.id, Route(id: r.id, title: r.title, subtitle: r.subtitle, milestones: r.milestones.map {
                Milestone(name: $0.name, point: LatLng(lat: $0.lat, lng: $0.lng), postcard: $0.postcard)
            }))
        })
        freedom = try doc.freedom.map { j in
            if let id = j.route {
                guard let r = routes[id] else { throw ContentError.unknownRoute(id) }
                return Journey(id: j.id, title: r.title, subtitle: r.subtitle, km: Int(r.lengthM / 1000),
                               postcards: r.milestones.count, teaser: j.teaser, unlock: j.unlock, route: r,
                               facts: j.facts, why: j.why, card: nil)
            }
            guard let title = j.title, let subtitle = j.subtitle, let km = j.km, let postcards = j.postcards else {
                throw ContentError.incomplete(j.id)
            }
            return Journey(id: j.id, title: title, subtitle: subtitle, km: km, postcards: postcards, teaser: j.teaser,
                           unlock: j.unlock, route: nil, facts: j.facts, why: j.why, card: nil)
        }
        outlaws = doc.outlaws.cards.map { o in
            Journey(id: o.id, title: o.title, subtitle: o.subtitle,
                    km: Int(Double(o.card.steps) * Stride.defaultM / 1000), postcards: 1, teaser: o.teaser,
                    unlock: "\(Fmt.grouped(o.card.steps)) lifetime steps", route: nil, facts: o.facts, why: o.why,
                    card: o.card)
        }
        peaks = doc.peaks.all
        peaksTitle = doc.peaks.title
    }

    enum ContentError: Error {
        case unknownRoute(String)
        case incomplete(String)
    }

    private struct Doc: Decodable {
        struct RouteDoc: Decodable {
            struct M: Decodable { let name: String; let lat: Double; let lng: Double; let postcard: String }
            let id: String
            let title: String
            let subtitle: String
            let milestones: [M]
        }
        struct FreedomDoc: Decodable {
            let id: String
            let route: String?
            let title: String?
            let subtitle: String?
            let km: Int?
            let postcards: Int?
            let teaser: String
            let unlock: String
            let facts: [String]
            let why: String
        }
        struct OutlawDoc: Decodable {
            let id: String
            let title: String
            let subtitle: String
            let card: OutlawCard
            let teaser: String
            let facts: [String]
            let why: String
        }
        struct Outlaws: Decodable { let volumes: [String]; let cards: [OutlawDoc] }
        struct Peaks: Decodable { let title: String; let all: [Peak] }
        let routes: [RouteDoc]
        let freedom: [FreedomDoc]
        let outlaws: Outlaws
        let peaks: Peaks
    }
}
