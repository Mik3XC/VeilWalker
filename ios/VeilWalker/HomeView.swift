import SwiftUI
import VeilWalkerCore

enum Screen: Hashable {
    case journeys, journey(String), peak(String), stats, badges, about, account, social, brag, credits, snowflake
}

/// Everything on one screen, no scroll: identity, lifetime steps, walk + privacy lines, the live journey,
/// the next unlock, links. Mirrors HomeScreen.kt. Links for screens that arrive in build step 7 show muted.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Binding var path: [Screen]
    @AppStorage(Look.key) private var look = Look.terminal.rawValue
    @State private var wake = false
    private var glass: Bool { look == Look.glass.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Tapping the mark switches between the Terminal and Glass looks.
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.35)) { look = (Look(rawValue: look) ?? .terminal).next.rawValue }
                } label: {
                    LogoMark().frame(width: 32, height: 32).glow(Veil.violet, radius: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("switch look, now \(Look(rawValue: look)?.title ?? "terminal")")
                Text("VeilWalker").font(Veil.titleLarge)
                Spacer()
                // Car-dashboard temperature: the snowflake means freezing, and freezing walks climb the Hidden Peaks.
                if !app.weather.enabled {
                    Button { app.weather.setEnabled(true) } label: {
                        Text("[ ] weather").font(Veil.body).foregroundStyle(Veil.muted)
                    }
                    .buttonStyle(.plain)
                } else if let w = app.weather.weather {
                    Text(w.label).font(Veil.titleMedium).foregroundStyle(w.freezing ? Veil.ice : Veil.dim)
                } else {
                    Text("--°F").font(Veil.titleMedium).foregroundStyle(Veil.muted)
                }
            }
            Rectangle().fill(Veil.violet).frame(height: 1).glow(Veil.violet, radius: 4)

            HStack(spacing: 8) {
                // The picture in its own pane; tap to change it in @ account.
                Button { Haptics.tap(); path.append(.account) } label: {
                    AvatarArt(index: app.avatar, size: 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)   // centred in its pane
                        .veilPanel(outlined: true, padding: 10)
                        .frame(width: 92)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("profile picture, change in account")
                VStack(alignment: .leading, spacing: 2) {
                    Text((app.clan.map { "[\($0)] " } ?? "") + (app.handle ?? "no handle yet"))
                        .font(Veil.titleMedium).fontWeight(.bold)
                    Text(Fmt.grouped(app.lifetimeSteps))
                        .font(Veil.headline.weight(.semibold)).foregroundStyle(Veil.violet)
                        .glow(Veil.violet, radius: 10)
                        .contentTransition(.numericText(value: Double(app.lifetimeSteps)))
                        .animation(.snappy, value: app.lifetimeSteps)
                        .accessibilityIdentifier("lifetime-steps")
                    Text("lifetime steps · \(app.points) \(app.points == 1 ? "pt" : "pts") · \(Fmt.fixed(app.todayKm, 1)) km today")
                        .font(Veil.small).foregroundStyle(Veil.dim)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxHeight: .infinity)
                .veilPanel(outlined: true, padding: 10)
            }
            .fixedSize(horizontal: false, vertical: true)

            // Walk and Tor share one bar, two cells: tap the walk cell to start a walk, the Tor cell to switch Tor.
            HStack(spacing: 10) {
                Button { Haptics.tap(); app.startWalk() } label: {
                    Text(app.walks?.line ?? WalkStatus.idle.line(nowMs: 0))
                        .foregroundStyle(app.walks?.status.isIdle ?? true ? Veil.dim : Veil.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)   // a tap during a walk does nothing (startNow ignores it), so the green stays
                .accessibilityIdentifier("walk-status")

                Rectangle().fill(Veil.violet.opacity(0.4)).frame(width: 1).padding(.vertical, 2)

                Button { Haptics.tap(); app.toggleTor() } label: {
                    Text(app.tor.line).foregroundStyle(app.tor.enabled ? Veil.green : Veil.muted)
                        .glow(app.tor.phase == .ok && app.tor.enabled ? Veil.green : .clear, radius: 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .layoutPriority(1)   // the Tor state is short and always shown whole; the walk text gives way
                .accessibilityIdentifier("tor-status")
            }
            .font(Veil.body)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .veilPanel(outlined: true, padding: 10)

            // Snowflake and Wake Mode share a bar: learn what it is, or go always-on for a run.
            HStack(spacing: 10) {
                Button { Haptics.tap(); path.append(.snowflake) } label: {
                    HStack(spacing: 6) {
                        // Android's markers: (*) hosting, [ ] off. On iPhone it only hosts inside wake mode.
                        Text(app.snowflake.running ? "(*) snowflake" : "[ ] snowflake").foregroundStyle(Veil.ice).glow(Veil.ice, radius: 5)
                        Text("> learn").foregroundStyle(Veil.violet)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Snowflake: help people past censorship. Learn more.")

                Rectangle().fill(Veil.ice.opacity(0.35)).frame(width: 1).padding(.vertical, 2)

                Button { Haptics.tap(); wake = true } label: {
                    Text("(o) wake mode").foregroundStyle(Veil.green).glow(Veil.green, radius: 5).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wake mode: screen stays on for runs")
            }
            .font(Veil.body)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
            .veilPanel(outlined: true, outline: Veil.ice.opacity(0.35), padding: 10)

            RouteCardView(progress: app.route, compact: true) { path.append(.journeys) }

            if let next = app.content.locked.first {
                Button { path.append(.journeys) } label: {
                    Text("[#] next: \(next.title.uppercased()) · \(next.unlock)")
                        .font(Veil.small).foregroundStyle(Veil.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            // Six destinations as a 3 × 2 grid of buttons, down where thumbs reach.
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    tile("=", "journeys") { path.append(.journeys) }
                    tile("&", "social") { path.append(.social) }
                    tile("~", "stats") { path.append(.stats) }
                }
                HStack(spacing: 8) {
                    tile("+", "badges \(app.board.unlockedCount)/\(app.board.all.count)") { path.append(.badges) }
                    tile("^", "brag") { path.append(.brag) }
                    tile("@", "account") { path.append(.account) }
                }
            }
            .background(alignment: .topLeading) {
                // 3XC as a faint signature, half peeking out above the buttons into the empty space.
                ThreeXCArt(size: 24, color: Veil.violet.opacity(0.1))
                    .offset(x: 2, y: -96)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            // The easter egg: tiny links most people only find by accident.
            HStack(spacing: 6) {
                Spacer()
                Button { Haptics.tap(); path.append(.about) } label: { Text("about").padding(.vertical, 2) }
                Text("·")
                Button { Haptics.tap(); path.append(.credits) } label: { Text("credits").padding(.vertical, 2) }
            }
            .buttonStyle(.plain)
            .font(Veil.label)
            .foregroundStyle(Veil.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .foregroundStyle(Veil.text)
        .font(Veil.bodyLarge)
        .background(VeilBackdrop())
        .dynamicTypeSize(...DynamicTypeSize.large)   // one screen, no scroll
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $wake) { WakeView() }   // full screen: no edge swipe can close it mid-run
    }

    /// One home destination: a glowing glyph over its name, in a pane (outlined in Terminal, glass in Glass).
    private func tile(_ glyph: String, _ name: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            VStack(spacing: 2) {
                Text(glyph).font(Veil.titleLarge.weight(.semibold)).foregroundStyle(Veil.violet).glow(Veil.violet, radius: 6)
                Text(name).font(Veil.small).foregroundStyle(Veil.text).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .veilPanel(outlined: true, outline: Veil.violet.opacity(0.45), padding: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}
