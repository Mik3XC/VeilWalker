import SwiftUI

/// Star Wars style but monospace: the credits crawl up forever. These are also our attribution notices, so keep them
/// in sync with the build (VeilWalkerCore/Package.swift, rust/vw-tor/Cargo.toml). Mirrors CreditsScreen.kt, with the
/// iOS stack in place of the Android one.
private let credits: [(String, [String])] = [
    ("THE TOR PROJECT", [
        "Arti (Rust Tor) · MIT/Apache-2.0",
        "Tor network · volunteer relays",
        "Snowflake · BSD-3-Clause",
        "Pion WebRTC · MIT",
        "Go · BSD-3-Clause",
    ]),
    ("iOS & SWIFT", [
        "Swift & SwiftUI        · Apple",
        "CryptoKit, CoreMotion  · Apple",
        "CoreLocation, ActivityKit · Apple",
        "GRDB.swift             · MIT",
        "SQLite                 · public domain",
    ]),
    ("NETWORK & CRYPTO", [
        "rustls / ring     · Apache-2.0 / ISC",
        "tokio-rustls      · MIT / Apache-2.0",
        "webpki-roots      · CDLA-Permissive-2.0",
        "tokio             · MIT",
        "hyper             · MIT",
        "BIP39 wordlist    · MIT (bitcoin/bips)",
    ]),
    ("SERVER", [
        "Rust              · MIT / Apache-2.0",
        "Axum, Tower       · MIT",
        "sqlx              · MIT / Apache-2.0",
        "ed25519-dalek     · BSD-3-Clause",
        "PostgreSQL        · PostgreSQL License",
        "Railway           · hosting",
    ]),
    ("WEATHER", [
        "US National Weather Service · public domain",
    ]),
    ("HISTORY & IDEAS", [
        "Library of Congress & public archives",
        "cypherpunks, phreaks & privacy coders",
    ]),
    ("MADE BY", [
        "3XCypher",
        "with Claude (Anthropic)",
    ]),
]

struct CreditsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { box in
                if reduceMotion {
                    ScrollView { roll.frame(maxWidth: .infinity) }
                } else {
                    TimelineView(.animation) { tl in
                        let t = tl.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 40) / 40
                        roll
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { g in Color.clear.preference(key: RollHeight.self, value: g.size.height) })
                            .offset(y: box.size.height - t * (box.size.height + rollHeight))
                    }
                }
            }
            .clipped()
            .onPreferenceChange(RollHeight.self) { rollHeight = $0 }
        }
        .padding(.horizontal, 16)
        .safeAreaInset(edge: .top, spacing: 4) { BackBar() }
        .background(VeilBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }

    @State private var rollHeight: CGFloat = 1000

    private var roll: some View {
        VStack(spacing: 4) {
            ThreeXCArt(size: 14)
            Text("V E I L W A L K E R").font(Veil.bodyLarge).foregroundStyle(Veil.green)
            Text("built on the shoulders of open source").font(Veil.small).foregroundStyle(Veil.dim)
            ForEach(credits, id: \.0) { section, lines in
                Text(" ").font(.system(size: 8))
                Text("== \(section) ==").font(Veil.bodyLarge).foregroundStyle(Veil.violet)
                ForEach(lines, id: \.self) { Text($0).font(Veil.art(11)).foregroundStyle(Veil.text).multilineTextAlignment(.center) }
            }
            Text(" ").font(.system(size: 8))
            Text("walk the world. leave no trace.").font(Veil.bodyLarge).foregroundStyle(Veil.green)
        }
    }
}

private struct RollHeight: PreferenceKey {
    static let defaultValue: CGFloat = 1000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
