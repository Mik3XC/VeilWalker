import SwiftUI

/// Separate, affirmative consent for consumer health data before anything is collected (Washington My Health My Data
/// Act and similar state laws). Nothing runs (no identity, no step counting, no permission prompts) until this is
/// accepted. Same text as Android's ConsentScreen.kt.
struct ConsentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var health = false
    @State private var terms = false

    static let privacyURL = URL(string: "https://sites.google.com/view/veilwalker-app/privacy")!
    static let healthURL = URL(string: "https://sites.google.com/view/veilwalker-app/health-data")!
    static let termsURL = URL(string: "https://sites.google.com/view/veilwalker-app/terms")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("VeilWalker").font(Veil.headline)
                Rectangle().fill(Veil.violet).frame(height: 1)
                Text("Before you walk").font(Veil.titleLarge)

                Text("// what we collect").foregroundStyle(Veil.green)
                Text("Step counts, motion-sensor readings and, during walks, GPS location. These are consumer health data. They're processed on this phone. Raw motion and GPS data never leave it and are deleted after 30 days.")
                    .foregroundStyle(Veil.dim)
                Text("// what leaves your phone").foregroundStyle(Veil.green)
                Text("Only daily step totals by type and an anti-cheat score, signed by your device key, so points can be issued. No name, email, phone number, contacts or precise location. Sent over Tor by default.")
                    .foregroundStyle(Veil.dim)
                Text("// what we never do").foregroundStyle(Veil.green)
                Text("Sell, share or rent your data. No ads, no trackers, no analytics SDKs.").foregroundStyle(Veil.dim)
                Text("// your control").foregroundStyle(Veil.green)
                Text("Withdraw consent and delete your account any time in @ account. Deletion removes your synced data.").foregroundStyle(Veil.dim)

                TextLink(label: "> read the consumer health data policy") { openURL(Self.healthURL) }
                TextLink(label: "> read the privacy policy") { openURL(Self.privacyURL) }
                TextLink(label: "> read the terms") { openURL(Self.termsURL) }

                checkbox(health, "I consent to VeilWalker collecting and processing my step, motion and location data as described above.") { health.toggle() }
                checkbox(terms, "I'm 13 or older and agree to the terms.") { terms.toggle() }
                VeilButton(label: "Start walking", filled: true, enabled: health && terms) { app.acceptConsent() }
            }
            .padding(16)
        }
        .background(VeilBackdrop())
        .foregroundStyle(Veil.text)
        .font(Veil.bodyLarge)
    }

    private func checkbox(_ on: Bool, _ text: String, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            Text((on ? "[x] " : "[ ] ") + text)
                .foregroundStyle(on ? Veil.green : Veil.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
