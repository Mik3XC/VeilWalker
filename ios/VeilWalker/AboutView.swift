import SwiftUI

/// 3XC, the pledge, Walk for Freedom, who built it. Mirrors AboutScreen.kt; adds this install's key prefix and last
/// sync, which Android shows on its account screen.
struct AboutView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        VeilScreen(spacing: 10) {
            ThreeXCArt(size: 15)
            Text("3 X C Y P H E R").font(Veil.titleMedium).foregroundStyle(Veil.green)
            Rectangle().fill(Veil.violet).frame(height: 1)

            Text("VeilWalker v\(version)").font(Veil.titleLarge)
            Text("A walking app that doesn't watch you walk.").foregroundStyle(Veil.dim)

            Text("// the pledge").foregroundStyle(Veil.green)
            ForEach([
                "no email, no phone number: 24 words are the account",
                "steps, motion and GPS stay on this phone",
                "tor on by default, never a quiet clearnet fallback",
                "no ads, no trackers, no data sold. ever",
                "points are signed, chained and yours to verify",
            ], id: \.self) { Text("[x] \($0)").font(Veil.body) }

            Text("// walk for freedom").foregroundStyle(Veil.green)
            Text("Every journey follows people who moved forward when it cost them: Tubman, Douglass, Lovelace, Turing, Zimmermann and the ones still walking.")
                .font(Veil.body).foregroundStyle(Veil.dim)

            Text("// built by 3XCypher").foregroundStyle(Veil.green)
            Text("Systems, privacy and Tor. Made to be walked, not watched.").font(Veil.body).foregroundStyle(Veil.dim)

            Text("// this phone").foregroundStyle(Veil.green)
            Text("key \(app.keyPrefix)…").font(Veil.body).foregroundStyle(Veil.dim)
            Text(app.syncNote).font(Veil.body).foregroundStyle(Veil.dim).accessibilityIdentifier("sync-note")
            if let e = app.startupError {
                Text("error · \(e)").font(Veil.body).foregroundStyle(.red)
            }
        }
    }
}
