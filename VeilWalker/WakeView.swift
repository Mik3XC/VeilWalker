import SwiftUI
import UIKit
import VeilWalkerCore
import VeilWalkerTor

/// Snowflake hosting in Wake Mode. Opt-in (as on Android), and only while Wake Mode is on screen: iPhone allows
/// foreground work, not a proxy kept alive in the background. Its one public number is traffic shared; nothing else is
/// kept (no peers, addresses, countries or session log), so there's nothing to learn about who was helped.
/// Data caps as on Android: a prompt at 50 MB per session (continue to 150 MB), and never more than 500 MB a day.
@MainActor @Observable
final class SnowflakeStats {
    static let softCapBytes: Int64 = 50_000_000
    static let extendedCapBytes: Int64 = 150_000_000
    static let dailyCapBytes: Int64 = 500_000_000

    private static let totalKey = "snowflakeBytesShared"
    private static let todayKey = "snowflakeBytesToday"
    private static let dayKey = "snowflakeDay"
    private static let enabledKey = "snowflakeHostInWake"

    let engineAvailable = true
    private(set) var bytesShared = Int64(UserDefaults.standard.integer(forKey: SnowflakeStats.totalKey))
    private(set) var bytesToday: Int64 = 0
    private(set) var sessionBytes: Int64 = 0
    private(set) var enabled = UserDefaults.standard.bool(forKey: SnowflakeStats.enabledKey)
    private(set) var running = false
    /// The 50 MB prompt is showing; hosting is paused until the user answers.
    private(set) var askToContinue = false
    /// Stopped by a cap: "session" (150 MB) or "today" (500 MB).
    private(set) var cappedBy: String?
    private(set) var lastError: String?

    private var sessionLimit = SnowflakeStats.softCapBytes
    private var minuteTicker: Task<Void, Never>?
    private var onMinute: (@MainActor () -> Void)?
    private let days = LocalDays()

    init() {
        rollDay()
    }

    func setEnabled(_ on: Bool, onMinute: @escaping @MainActor () -> Void) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { start(onMinute: onMinute) } else { stop() }
    }

    /// Wake Mode on screen: host if the user opted in and no cap is hit.
    func start(onMinute: @escaping @MainActor () -> Void) {
        rollDay()
        guard enabled, !running, !askToContinue, cappedBy == nil else { return }
        guard bytesToday < Self.dailyCapBytes else { cappedBy = "today"; return }
        self.onMinute = onMinute
        SnowflakeHost.shared.start(capacity: 2) { bytes in
            Task { @MainActor [weak self] in self?.record(bytes) }
        }
        running = true
        lastError = nil
        minuteTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, self.running else { return }
                if let e = SnowflakeHost.shared.lastError { self.lastError = e; self.stop(); return }
                self.onMinute?()   // a minute hosted: frost, if a walk is on
            }
        }
    }

    /// Wake Mode left the screen (or the app left the foreground): stop at once.
    func stop() {
        minuteTicker?.cancel()
        minuteTicker = nil
        if running { SnowflakeHost.shared.stop() }
        running = false
    }

    /// Wake Mode closed: the next session starts fresh (caps per session, the daily cap carries over).
    func endSession() {
        stop()
        sessionBytes = 0
        sessionLimit = Self.softCapBytes
        askToContinue = false
        if cappedBy == "session" { cappedBy = nil }
    }

    func continuePastSoftCap(onMinute: @escaping @MainActor () -> Void) {
        askToContinue = false
        sessionLimit = Self.extendedCapBytes
        start(onMinute: onMinute)
    }

    func declineSoftCap() {
        askToContinue = false
        cappedBy = "session"
    }

    private func record(_ bytes: Int64) {
        rollDay()
        bytesShared += bytes
        bytesToday += bytes
        sessionBytes += bytes
        UserDefaults.standard.set(Int(bytesShared), forKey: Self.totalKey)
        UserDefaults.standard.set(Int(bytesToday), forKey: Self.todayKey)
        if bytesToday >= Self.dailyCapBytes {
            stop()
            cappedBy = "today"
        } else if sessionBytes >= sessionLimit {
            stop()
            if sessionLimit == Self.softCapBytes { askToContinue = true } else { cappedBy = "session" }
        }
    }

    private func rollDay() {
        let today = days.day(Date())
        if UserDefaults.standard.string(forKey: Self.dayKey) != today {
            UserDefaults.standard.set(today, forKey: Self.dayKey)
            UserDefaults.standard.set(0, forKey: Self.todayKey)
            if cappedBy == "today" { cappedBy = nil }
        }
        bytesToday = Int64(UserDefaults.standard.integer(forKey: Self.todayKey))
    }

    /// The one-line status under the counter.
    var statusLine: String {
        if let e = lastError { return "[x] snowflake stopped: \(e.prefix(60))" }
        if cappedBy == "today" { return "[-] 500 MB shared today: resting until tomorrow" }
        if cappedBy == "session" { return "[-] session cap reached · see you next run" }
        if askToContinue { return "[?] 50 MB shared this run" }
        if running { return "(*) hosting · only traffic shared is kept · stops when you leave" }
        return "[ ] tap to host a snowflake while this screen is open"
    }

    /// 0 B, 512 KB, 41.2 MB, 1.30 GB.
    static func format(_ b: Int64) -> String {
        let d = Double(b)
        if d >= 1e9 { return Fmt.fixed(d / 1e9, 2) + " GB" }
        if d >= 1e6 { return Fmt.fixed(d / 1e6, 1) + " MB" }
        if d >= 1e3 { return Fmt.fixed(d / 1e3, 0) + " KB" }
        return "\(b) B"
    }
}

/// Runners Wake Mode: for the phone in an arm band. The screen stays on (which is also what lets an iPhone host a
/// snowflake within Apple's rules: foreground only), a walk starts if one isn't running, and everything is big
/// enough to read mid-stride. Exit is a 1-second hold so a sweaty arm or a raindrop can't end it.
/// The backdrop is the "WakeTerminal" / "WakeGlass" image when the app has one, otherwise the live backdrop.
struct WakeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Look.key) private var look = Look.terminal.rawValue
    @State private var holding = false
    @State private var spin = false
    @State private var explainHosting = false
    @Environment(\.scenePhase) private var phase
    @AppStorage("snowflakeHostExplained") private var explained = false

    private var glass: Bool { look == Look.glass.rawValue }
    private var artImage: UIImage? { UIImage(named: glass ? "WakeGlass" : "WakeTerminal") }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 14) {
                HStack {
                    Text("WAKE MODE").font(Veil.label.weight(.bold)).tracking(3).foregroundStyle(Veil.green).glow(Veil.green, radius: 6)
                    Spacer()
                    Text(app.tor.line).font(Veil.label).foregroundStyle(app.tor.enabled ? Veil.green : Veil.muted).lineLimit(1)
                }

                // The walk: the one number a runner glances at, huge.
                VStack(spacing: 2) {
                    Text(walkClock).font(.system(size: 64, weight: .semibold, design: .monospaced)).foregroundStyle(Veil.violet)
                        .glow(Veil.violet, radius: 14).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    Text(app.walks?.line ?? "walk: starting…").font(Veil.small).foregroundStyle(Veil.dim).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .modifier(WakePane(art: artImage != nil, glass: glass, outline: Veil.violet.opacity(0.4), padding: 16))

                if artImage != nil {
                    // With the art behind, the numbers stay up top in one row and the runner gets the lower half.
                    HStack(spacing: 8) {
                        stat(Fmt.grouped(app.todaySteps), "steps", art: true)
                        stat(Fmt.fixed(app.todayKm, 2), "km", art: true)
                        stat(SnowflakeStats.format(app.snowflake.bytesShared), "shared", art: true, color: Veil.ice)
                    }
                    hostSwitch(art: true)
                } else {
                HStack(spacing: 10) {
                    stat(Fmt.grouped(app.todaySteps), "steps today")
                    stat(Fmt.fixed(app.todayKm, 2), "km today")
                }

                // Snowflake: traffic shared, and nothing else.
                VStack(spacing: 8) {
                    Text(SnowflakeArt.flake)
                        .font(Veil.art(14)).lineSpacing(1).foregroundStyle(Veil.ice).glow(Veil.ice, radius: 10)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .fixedSize()
                    Text(SnowflakeStats.format(app.snowflake.bytesShared))
                        .font(.system(size: 34, weight: .semibold, design: .monospaced)).foregroundStyle(Veil.ice).monospacedDigit()
                    Text("shared through snowflake").font(Veil.small).foregroundStyle(Veil.dim)
                    hostSwitch(art: false)
                }
                .frame(maxWidth: .infinity)
                .veilPanel(outlined: true, outline: Veil.ice.opacity(0.45), padding: 16)
                }

                Spacer(minLength: 0)

                // Hold to exit: an accidental brush can't end the session.
                Text(holding ? "keep holding…" : "hold to exit")
                    .font(Veil.bodyLarge).foregroundStyle(holding ? Veil.green : Veil.violet)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .modifier(WakePane(art: artImage != nil, glass: glass, outline: Veil.violet.opacity(0.5), padding: 0))
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 1, pressing: { holding = $0 }) {
                        Haptics.tap()
                        dismiss()
                    }
                    .accessibilityLabel("Exit wake mode")
                    .accessibilityAction { dismiss() }
            }
            .padding(16)
        }
        .foregroundStyle(Veil.text)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // the point of wake mode: the screen stays on
            if app.walks?.status.isIdle ?? false { app.startWalk() }
            withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) { spin = true }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            app.snowflake.endSession()   // hosting never outlives the screen
        }
        .task { app.snowflake.start(onMinute: creditMinute) }
        // Foreground only: the moment the app isn't on screen, the snowflake stops; it resumes when it's back.
        .onChange(of: phase) { _, now in
            if now == .active { app.snowflake.start(onMinute: creditMinute) } else { app.snowflake.stop() }
        }
        .alert("Host a snowflake?", isPresented: $explainHosting) {
            Button("Host") {
                explained = true
                app.snowflake.setEnabled(true, onMinute: creditMinute)
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("While this screen is open, your phone relays already-encrypted Tor traffic for people in censored countries. They can see your phone's IP address, as with any snowflake, but not what you do; you can't see what they do either. It uses mobile data (capped at 500 MB a day) and stops the moment you leave this screen. Only the amount shared is kept.")
        }
        .alert("50 MB shared this run", isPresented: Binding(get: { app.snowflake.askToContinue }, set: { _ in })) {
            Button("Keep going to 150 MB") { app.snowflake.continuePastSoftCap(onMinute: creditMinute) }
            Button("Stop hosting", role: .cancel) { app.snowflake.declineSoftCap() }
        } message: {
            Text("Keep helping people reach Tor on this run, up to 150 MB?")
        }
    }

    /// The snowflake on/off switch: its status line, tappable. Turning it on the first time explains what it does.
    private func hostSwitch(art: Bool) -> some View {
        let s = app.snowflake
        return Button {
            Haptics.tap()
            if s.enabled {
                s.setEnabled(false, onMinute: creditMinute)
            } else if explained {
                s.setEnabled(true, onMinute: creditMinute)
            } else {
                explainHosting = true
            }
        } label: {
            // A real button: the first version was a thin line of text that was easy to miss.
            VStack(spacing: 4) {
                Text(s.enabled ? (s.running ? "(*) HOSTING A SNOWFLAKE" : "(*) HOSTING PAUSED") : "[ ] HOST A SNOWFLAKE")
                    .font(Veil.bodyLarge.weight(.bold)).tracking(1)
                    .foregroundStyle(s.running ? Veil.green : Veil.ice)
                    .glow(s.running ? Veil.green : Veil.ice, radius: 6)
                Text(s.enabled ? s.statusLine : "help people past censorship while this screen is on")
                    .font(Veil.label).foregroundStyle(Veil.dim)
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .modifier(WakePane(art: art, glass: glass, outline: (s.running ? Veil.green : Veil.ice).opacity(0.6), padding: 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.enabled ? "Snowflake hosting on. Tap to stop." : "Host a snowflake while this screen is open")
    }

    /// A minute hosted while walking frosts the badge frames.
    private func creditMinute() {
        app.walks?.creditSnowflakeMinute()
        app.refresh()
    }

    /// The walk's elapsed time from the status line ("walk: 7:05 · 812 steps" → "7:05").
    private var walkClock: String {
        let line = app.walks?.line ?? ""
        guard line.hasPrefix("walk: "), let part = line.dropFirst(6).split(separator: " ").first, part.contains(":") else { return "0:00" }
        return String(part)
    }

    private func stat(_ value: String, _ label: String, art: Bool = false, color: Color = Veil.text) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: art ? 22 : 30, weight: .semibold, design: .monospaced)).foregroundStyle(color)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(Veil.small).foregroundStyle(Veil.dim)
        }
        .frame(maxWidth: .infinity)
        .modifier(WakePane(art: art, glass: glass, outline: Veil.muted, padding: art ? 10 : 12))
    }

    @ViewBuilder private var backdrop: some View {
        if let image = artImage {
            // Anchored to the bottom so the runner and the wall stay in view on any screen shape.
            GeometryReader { g in
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height, alignment: .bottom).clipped()
            }
            .ignoresSafeArea()
        } else {
            VeilBackdrop()
        }
    }
}

enum SnowflakeArt {
    static let flake = [
        #"    \  |  /    "#,
        #"  -- \ | / --  "#,
        #"  ____\|/____  "#,
        #"      /|\      "#,
        #"  -- / | \ --  "#,
        #"    /  |  \    "#,
    ].joined(separator: "\n")
}

/// A Wake Mode pane. Over the art it's see-through (dark tint, or glass in the Glass look) so the picture shows;
/// without art it's the normal panel.
private struct WakePane: ViewModifier {
    let art: Bool
    let glass: Bool
    let outline: Color
    let padding: CGFloat

    func body(content: Content) -> some View {
        if art && !glass {
            content.padding(padding).frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.45))
                .overlay(Rectangle().stroke(outline, lineWidth: 1))
        } else {
            content.veilPanel(outlined: true, outline: outline, padding: padding)
        }
    }
}
