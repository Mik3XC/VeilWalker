import SwiftUI
import VeilWalkerCore

/// What Snowflake is, why it helps, and where VeilWalker fits. Hosting isn't in iOS v1 (handoff §8: keeping a proxy
/// alive in the background through location mode would misuse a background mode, App Store guideline 2.5.4), so this
/// page teaches and points to the browser Snowflake, which anyone can run today.
struct SnowflakeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    static let site = URL(string: "https://snowflake.torproject.org/")!

    var body: some View {
        VeilScreen(spacing: 10) {
            Text("Snowflake").font(Veil.headline)
            Text("Breaking walls, one volunteer at a time.").foregroundStyle(Veil.dim)

            WallBreaker()
                .veilPanel(outlined: true, outline: Veil.green.opacity(0.5), padding: 12)

            SectionHeader(text: "what is snowflake")
            Text("In some countries the network is walled off: Tor's known entry points are blocked, so people there can't reach it. Snowflake is a Tor Project tool that gets around the wall. Volunteers around the world run a tiny proxy, a \"snowflake\", and a blocked user's Tor connection hops through one of them on its way in.")
                .font(Veil.body).foregroundStyle(Veil.dim)

            SectionHeader(text: "why the wall can't keep up")
            Text("Snowflakes are many, short-lived and constantly changing, and their traffic looks like an ordinary video call. A censor would have to block thousands of everyday addresses that keep moving, which breaks things people rely on. Melt one and another falls.")
                .font(Veil.body).foregroundStyle(Veil.dim)

            SectionHeader(text: "is it safe to run one")
            Text("A snowflake only passes along traffic that's already encrypted by Tor. It can't read it, and it isn't an exit: websites never see your address. It uses a little bandwidth while it's on.")
                .font(Veil.body).foregroundStyle(Veil.dim)

            SectionHeader(text: "snowflake in veilwalker")
            Text("Hosting a snowflake while you walk will earn frost on every badge frame: FROST at 10 minutes, then ICE, GLACIER and AURORA at 5,000. Status only, never points, so nobody's helping for the wrong reasons. Data stays capped: a prompt at 50 MB and never more than 500 MB a day.")
                .font(Veil.body).foregroundStyle(Veil.dim)
            Text("Frost now: \(app.board.frost.title) · \(app.board.snowflakeMinutes) min hosted")
                .font(Veil.body).foregroundStyle(app.board.frost == .none ? Veil.muted : Veil.ice)

            SectionHeader(text: "on iPhone")
            Text("iPhone apps can't keep a proxy running in the background, so hosting from VeilWalker isn't here yet. You can help today from any computer or browser: the Tor Project's own Snowflake runs in a browser tab or extension.")
                .font(Veil.body).foregroundStyle(Veil.dim)
            VeilButton(label: "Run a snowflake in your browser", glyph: "*", filled: true) { openURL(Self.site) }
            Text("snowflake.torproject.org · made by the Tor Project, not by VeilWalker").font(Veil.small).foregroundStyle(Veil.muted)
        }
    }
}

/// The wall breaker: a censored user's packets bounce off the wall, volunteers' snowflakes light up on the far side,
/// and the wall cracks open so traffic flows through them to Tor. Pure text, redrawn ~8 times a second as one string,
/// so it costs almost nothing.
struct WallBreaker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let cycle = 12.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.125)) { tl in
            let t = reduceMotion ? 10.0 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle)
            let frame = Self.frame(t)
            VStack(alignment: .leading, spacing: 6) {
                Text(frame.art)
                    .font(Veil.art(13))
                    .lineSpacing(2)
                    .foregroundStyle(Veil.green)
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                Text(frame.caption).font(Veil.small).foregroundStyle(frame.through ? Veil.green : Veil.dim)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animation: a blocked user's traffic hits a wall, volunteer snowflakes appear behind it, and the wall breaks so the traffic reaches Tor through them.")
    }

    /// One frame: 9 rows × 34 columns. The user at left, the wall at column 11, snowflakes beyond, Tor at right.
    static func frame(_ t: Double) -> (art: String, caption: String, through: Bool) {
        let rows = 9, cols = 34, wall = 11, mid = 4
        var g = Array(repeating: Array(repeating: Character(" "), count: cols), count: rows)
        func render(_ g: [[Character]]) -> String { g.map { String($0) }.joined(separator: "\n") }
        func put(_ r: Int, _ c: Int, _ s: String) {
            for (i, ch) in s.enumerated() where c + i >= 0 && c + i < cols { g[r][c + i] = ch }
        }
        put(mid, 0, "(@)")
        put(mid - 2, 0, "you")
        put(mid, 31, "(%)")
        put(mid - 2, 31, "tor")

        // Snowflakes beyond the wall: they light up one by one from 3 s.
        let flakes = [(1, 16), (6, 15), (3, 20), (7, 22), (2, 25), (5, 27), (mid, 21)]
        let lit = t < 3 ? 0 : min(flakes.count, Int((t - 3) / 0.45) + 1)
        for (r, c) in flakes.prefix(lit) { put(r, c, "*") }

        // The wall: whole until 6 s, then it cracks open around the middle row.
        let crack = t < 6 ? -1 : min(3, Int((t - 6) / 0.6))
        for r in 0..<rows {
            let open = crack >= 0 && abs(r - mid) <= crack - 1
            let cracking = crack >= 0 && abs(r - mid) == crack
            put(r, wall, open ? " " : cracking ? (r < mid ? "/" : r > mid ? "\\" : ":") : "#")
        }
        put(rows - 1, wall - 3, "censor")

        if t < 3 {
            // Straight at the wall, and blocked.
            let x = 4 + Int(t * 6) % 7
            if x >= wall - 1 { put(mid, wall - 1, "x") } else { put(mid, x, ">") }
            return (render(g), "the direct path is blocked", false)
        }
        if t < 6 {
            put(mid, 4, "> > >x")
            return (render(g), "volunteers light up snowflakes", false)
        }
        // Through the gap, via a snowflake, to Tor.
        for c in 4..<31 where g[mid][c] == " " { g[mid][c] = "." }
        let p = 4 + Int((t - 6) * 9) % 27
        for k in [p, p - 9, p - 18] where k >= 4 && k < 31 && g[mid][k] == "." { g[mid][k] = ">" }
        return (render(g), crack >= 1 ? "traffic slips through, still encrypted by Tor" : "the wall starts to crack", crack >= 1)
    }
}
