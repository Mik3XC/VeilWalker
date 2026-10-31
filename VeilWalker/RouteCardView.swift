import SwiftUI
import VeilWalkerCore

/// The route as a bare line on black with milestone dots and a marker: no map tiles, nothing fetched.
/// `compact` is the home-screen size: shorter sketch, postcards behind `onOpen`. Mirrors RouteCard.kt.
struct RouteCardView: View {
    let progress: RouteProgress
    var compact = false
    var onOpen: (() -> Void)?
    @State private var openPostcard: String?

    var body: some View {
        let pos = progress.position
        let r = progress.route
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            Text(r.title).font(compact ? Veil.titleMedium : Veil.titleLarge)
            Text(r.subtitle).font(Veil.small)
            sketch.frame(height: compact ? 110 : 180)
            Text(Ascii.bar(pos.travelledM / r.lengthM)).foregroundStyle(Veil.violet)
            Text("\(Fmt.fixed(pos.travelledM / 1000, 1)) / \(Fmt.fixed(r.lengthM / 1000, 0)) km · stride \(Fmt.fixed(progress.strideM, 2)) m")
                .font(Veil.small)
            if let next = pos.next {
                Text("next: \(next.name) in \(Fmt.fixed((pos.toNextM ?? 0) / 1000, 1)) km").font(Veil.small)
            } else {
                Text("Chapter complete.")
            }
            if compact {
                TextLink(label: "> postcards \(pos.unlocked.count)/\(r.milestones.count)", font: Veil.small, action: onOpen)
            } else {
                Text("Postcards \(pos.unlocked.count)/\(r.milestones.count)").font(Veil.titleSmall)
                ForEach(pos.unlocked, id: \.name) { m in
                    Button {
                        openPostcard = openPostcard == m.name ? nil : m.name
                    } label: {
                        Text((openPostcard == m.name ? "▾ " : "▸ ") + m.name).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    if openPostcard == m.name {
                        Text(m.postcard).font(Veil.body)
                    }
                }
            }
        }
        .foregroundStyle(Veil.text)
        .veilPanel(outlined: true, padding: compact ? 12 : 16)
    }

    private var sketch: some View {
        let pos = progress.position
        let milestones = progress.route.milestones
        return Canvas { ctx, size in
            let pts = milestones.map(\.point)
            guard let minLat = pts.map(\.lat).min(), let maxLat = pts.map(\.lat).max(),
                  let minLng = pts.map(\.lng).min(), let maxLng = pts.map(\.lng).max() else { return }
            let pad = 16.0   // room for the walker's halo
            // Keep the aspect ratio so the route isn't stretched.
            let scale = min((size.width - 2 * pad) / (maxLng - minLng), (size.height - 2 * pad) / (maxLat - minLat))
            func at(_ ll: LatLng) -> CGPoint {
                CGPoint(x: pad + (ll.lng - minLng) * scale, y: size.height - pad - (ll.lat - minLat) * scale)
            }
            var line = Path()
            line.addLines(pts.map(at))
            ctx.stroke(line, with: .color(Veil.muted), lineWidth: 2)
            var done = Path()
            done.addLines(pos.unlocked.map { at($0.point) } + [at(pos.point)])
            ctx.stroke(done, with: .color(Veil.violet), lineWidth: 4)
            for (i, m) in milestones.enumerated() {
                let c = at(m.point)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                         with: .color(i < pos.unlocked.count ? Veil.violet : Veil.muted))
            }
            let me = at(pos.point)
            // The walker: a green dot with a soft halo.
            ctx.fill(Path(ellipseIn: CGRect(x: me.x - 14, y: me.y - 14, width: 28, height: 28)), with: .color(Veil.green.opacity(0.18)))
            ctx.fill(Path(ellipseIn: CGRect(x: me.x - 7, y: me.y - 7, width: 14, height: 14)), with: .color(Veil.green))
        }
        .accessibilityLabel("route sketch, \(pos.unlocked.count) of \(milestones.count) postcards")
    }
}
