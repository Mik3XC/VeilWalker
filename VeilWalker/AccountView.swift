import SwiftUI
import UIKit
import VeilWalkerCore

/// Handle, clan, picture, recovery phrase, weather, hands-free walks, sync, restore, delete. Mirrors AccountScreen.kt.
struct AccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var phase
    @State private var words: [String]?
    @State private var status: String?
    @State private var busy = false
    @State private var clanText = ""
    @State private var claimText = ""
    @State private var restoreText = ""
    @State private var confirm = ""
    @State private var captured = UIScreen.main.isCaptured
    @AppStorage(Look.key) private var look = Look.terminal.rawValue

    var body: some View {
        VeilScreen(spacing: 12) {
            Text("Account").font(Veil.headline)
            Text("No email, no phone number. Your 24 words are your account.")

            Text("Clan").font(Veil.titleMedium)
            if let tag = app.clan {
                Text("[\(tag)] \(app.handle ?? "")").font(Veil.titleLarge).foregroundStyle(Veil.green)
                VeilButton(label: "Leave [\(tag)]", glyph: "x", enabled: !busy) { run { await app.clan(.leave) } }
            } else {
                Text("A 2–4 character tag shown before your name, like [ROX] \(app.handle ?? "HashCat").")
                TerminalField(label: "clan tag", text: $clanText) { String($0.filter { $0.isLetter || $0.isNumber }.prefix(4)).uppercased() }
                VeilButton(label: "Join [\(clanText)]", enabled: !busy && clanText.count >= 2) { run { await app.clan(.join, tag: clanText) } }
                VeilButton(label: "Create [\(clanText)]", glyph: "+", enabled: !busy && clanText.count >= 2) { run { await app.clan(.create, tag: clanText) } }
            }

            Text("Profile picture").font(Veil.titleMedium)
            AvatarPicker(selected: app.avatar) { app.pickAvatar($0) }
            Text("ID: \(app.publicKey.prefix(16))…").font(Veil.body)

            if let handle = app.handle {
                Text("@\(handle)").font(Veil.titleLarge)
            } else {
                Text("Claim your handle").font(Veil.titleMedium)
                Text("One name. Permanent. It can never be changed or freed. 5–20 letters, numbers or _. Don't use your real name.")
                TerminalField(label: "handle", prefix: "@", text: $claimText) { String($0.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }.prefix(20)) }
                VeilButton(label: "Claim @\(claimText) forever", glyph: "!", filled: true, enabled: !busy && claimText.count >= 5) {
                    run { await app.claimHandle(claimText) }
                }
            }

            VeilButton(label: words == nil ? "Show recovery phrase" : "Hide recovery phrase", glyph: "#") {
                words = words == nil ? app.recoveryWords() : nil
            }
            if let words {
                Text("Write these down in order and keep them offline. Anyone with them controls your points.")
                if phase == .active && !captured {
                    Text(stride(from: 0, to: words.count, by: 3).map { row in
                        (row..<min(row + 3, words.count)).map { "\($0 + 1). \(words[$0])" }.joined(separator: "   ")
                    }.joined(separator: "\n"))
                    .font(Veil.body)
                    .textSelection(.disabled)
                    .privacySensitive()
                } else {
                    Text("[hidden while the screen is recorded or the app is in the background]").font(Veil.small).foregroundStyle(Veil.muted)
                }
            }

            let weatherOn = app.weather.enabled
            VeilButton(label: weatherOn ? "Weather: on (tap to turn off)" : "Weather: off (tap to turn on)", glyph: weatherOn ? "*" : "o") {
                app.weather.setEnabled(!weatherOn)
            }
            Text("// what weather collects: your last known location, rounded to about 11 km, is sent straight from this phone to the US National Weather Service (api.weather.gov), over Tor when Tor is on. We never receive it, and only the temperature is kept. Weather is what powers the ❄ and Hidden Peaks, which count climb only on freezing walks. Turn it off and nothing is sent.")
                .font(Veil.small).foregroundStyle(Veil.muted)

            VeilButton(label: "Look: \(Look(rawValue: look)?.title ?? "terminal") (tap to switch)", glyph: "~") {
                withAnimation(.easeInOut(duration: 0.35)) { look = (Look(rawValue: look) ?? .terminal).next.rawValue }
            }
            Text("// terminal is the classic flat look. glass is iOS Liquid Glass over a drifting ASCII aurora. Tap the logo on the home screen to switch too.")
                .font(Veil.small).foregroundStyle(Veil.muted)

            if let walks = app.walks {
                let always = walks.alwaysEnabled
                VeilButton(label: always ? "Hands-free walks: on (tap to turn off)" : "Hands-free walks: off (tap to turn on)",
                           glyph: always ? "*" : "o") { walks.setAlways(!always) }
                Text("// iPhone only starts a walk by itself while VeilWalker is open. Turn this on and allow location \"Always\" so it can also notice a walk while the app is closed and record it with GPS and Tor. Locations stay on this phone. Off: walks taken with the app closed still count, from motion history, without GPS.")
                    .font(Veil.small).foregroundStyle(Veil.muted)
            }

            VeilButton(label: "Sync now", glyph: "~", enabled: !busy) { run { await app.syncNow() } }
            if let status { Text(status).font(Veil.body).accessibilityIdentifier("account-status") }

            Text("Restore from recovery phrase").font(Veil.titleMedium)
            TerminalField(label: "24 words, separated by spaces", text: $restoreText, secure: true) { $0 }
            VeilButton(label: "Restore (replaces this account)", glyph: "!",
                       enabled: !busy && restoreText.split(whereSeparator: \.isWhitespace).count == 24) {
                let phrase = restoreText
                restoreText = ""
                words = nil
                run { await app.restore(phrase: phrase) }
            }

            Text("Delete account").font(Veil.titleMedium)
            Text("Deletes your synced data from the server and wipes this phone's VeilWalker data. Your handle stays reserved. Can't be undone. Back up your 24 words first if you might come back.")
            TerminalField(label: "type DELETE", text: $confirm) { String($0.uppercased().prefix(6)) }
            VeilButton(label: "Delete account", glyph: "x", enabled: !busy && confirm == "DELETE") { run { await app.deleteAccount() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            captured = UIScreen.main.isCaptured
        }
        .onChange(of: phase) { _, now in if now == .background { words = nil } }
    }

    private func run(_ op: @escaping () async -> String) {
        busy = true
        status = nil
        Task {
            status = await op()
            busy = false
        }
    }
}

/// Four framed tiles; the chosen one gets the violet frame. Mirrors AvatarViews.kt.
struct AvatarPicker: View {
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Avatars.all.indices, id: \.self) { i in
                let on = i == selected
                Button { onSelect(i) } label: {
                    VStack(spacing: 4) {
                        AvatarArt(index: i, size: 9, color: on ? Veil.violet : Veil.dim)
                        Text(on ? "[\(Avatars.all[i].name)]" : Avatars.all[i].name).font(Veil.label)
                            .foregroundStyle(on ? Veil.violet : Veil.muted)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .overlay(Rectangle().stroke(on ? Veil.violet : Veil.muted, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("avatar \(Avatars.all[i].name.lowercased())\(on ? ", selected" : "")")
            }
        }
    }
}

/// A terminal-style text field: `label` above, a violet underline, no rounded chrome. `filter` cleans each edit.
struct TerminalField: View {
    let label: String
    var prefix: String?
    @Binding var text: String
    var secure = false
    let filter: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Veil.label).foregroundStyle(Veil.dim)
            HStack(spacing: 0) {
                if let prefix { Text(prefix).foregroundStyle(Veil.violet) }
                Group {
                    if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Veil.text)
                .tint(Veil.violet)
            }
            .font(Veil.bodyLarge)
            Rectangle().fill(Veil.violet).frame(height: 1)
        }
        .onChange(of: text) { _, new in
            let clean = filter(new)
            if clean != new { text = clean }
        }
    }
}
