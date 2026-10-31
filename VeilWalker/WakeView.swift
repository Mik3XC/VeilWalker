import SwiftUI
import UIKit
import VeilWalkerCore

/// Snowflake's one public number: traffic shared. Nothing else is kept: no peers, no addresses, no countries, no
/// session log, so there's nothing to learn about who was helped. The hosting engine (not built yet on either
/// platform) adds bytes through `record(_:)`.
@MainActor @Observable
final class SnowflakeStats {
    private static let key = "snowflakeBytesShared"
    private(set) var bytesShared: Int64 = Int64(UserDefaults.standard.integer(forKey: SnowflakeStats.key))
    /// True once a hosting engine is wired in. Until then the screen says so instead of pretending.
    let engineAvailable = false

    func record(_ bytes: Int64) {
        bytesShared += bytes
        UserDefaults.standard.set(Int(bytesShared), forKey: Self.key)
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

    private var glass: Bool { look == Look.glass.rawValue }

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
                .veilPanel(outlined: true, outline: Veil.violet.opacity(0.4), padding: 16)

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
                    Text(app.snowflake.engineAvailable
                         ? "only this number is kept: no peers, no addresses, no places"
                         : "[-] hosting engine not built yet · Android first · counter ready")
                        .font(Veil.label).foregroundStyle(Veil.dim).multilineTextAlignment(.center)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .veilPanel(outlined: true, outline: Veil.ice.opacity(0.45), padding: 16)

                Spacer(minLength: 0)

                // Hold to exit: an accidental brush can't end the session.
                Text(holding ? "keep holding…" : "hold to exit")
                    .font(Veil.bodyLarge).foregroundStyle(holding ? Veil.green : Veil.violet)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .veilPanel(outlined: true, outline: Veil.violet.opacity(0.5), padding: 0)
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
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// The walk's elapsed time from the status line ("walk: 7:05 · 812 steps" → "7:05").
    private var walkClock: String {
        let line = app.walks?.line ?? ""
        guard line.hasPrefix("walk: "), let part = line.dropFirst(6).split(separator: " ").first, part.contains(":") else { return "0:00" }
        return String(part)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 30, weight: .semibold, design: .monospaced)).foregroundStyle(Veil.text)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(Veil.small).foregroundStyle(Veil.dim)
        }
        .frame(maxWidth: .infinity)
        .veilPanel(outlined: true, padding: 12)
    }

    @ViewBuilder private var backdrop: some View {
        if let image = UIImage(named: glass ? "WakeGlass" : "WakeTerminal") {
            Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea()
                .overlay(Color.black.opacity(0.35).ignoresSafeArea())   // keeps the numbers readable on any art
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
