import SwiftUI

/// The four ASCII profile pictures, all 5 lines × 9 columns. Same art and order as Android's Avatars.kt;
/// the index is what /v1/me returns.
enum Avatars {
    static let all: [(name: String, art: String)] = [
        ("GHOST", [
            #"  .---.  "#,
            #" ( o o ) "#,
            #" |  O  | "#,
            #" |     | "#,
            #" '^^^^^' "#,
        ].joined(separator: "\n")),
        ("ABYSS", [
            #"  _/^\_  "#,
            #" / .-. \ "#,
            #"| ( * ) |"#,
            #" \ '-' / "#,
            #" /|||||\ "#,
        ].joined(separator: "\n")),
        ("CAT", [
            #"  /\_/\  "#,
            #" ( o.o ) "#,
            #"  > ^ <  "#,
            #" /     \ "#,
            #"(_)---(_)"#,
        ].joined(separator: "\n")),
        ("DEMON", [
            #" /)   (\ "#,
            #"( \___/ )"#,
            #" \ >v< / "#,
            #"  )   (  "#,
            #" / | | \ "#,
        ].joined(separator: "\n")),
    ]

    static func clamp(_ index: Int) -> Int { min(max(index, 0), all.count - 1) }
}

struct AvatarArt: View {
    let index: Int
    var size: CGFloat = 13
    var color = Veil.violet

    var body: some View {
        Text(Avatars.all[Avatars.clamp(index)].art)
            .font(Veil.art(size))
            .lineSpacing(size * 0.1)
            .foregroundStyle(color)
            .fixedSize()
            .accessibilityLabel("avatar \(Avatars.all[Avatars.clamp(index)].name.lowercased())")
    }
}

/// 3XC in figlet "standard" letters. Plain ASCII, 20 columns, so it fits at small sizes. Same as AboutScreen.kt.
struct ThreeXCArt: View {
    static let art = [
        #" _____ __  __  ____ "#,
        #"|___ / \ \/ / / ___|"#,
        #"  |_ \  \  / | |    "#,
        #" ___) | /  \ | |___ "#,
        #"|____/ /_/\_\ \____|"#,
    ].joined(separator: "\n")

    let size: CGFloat
    var color = Veil.violet

    var body: some View {
        Text(Self.art)
            .font(Veil.art(size))
            .lineSpacing(size * 0.3)
            .foregroundStyle(color)
            .fixedSize()
            .accessibilityLabel("3XC")
    }
}

/// Signature in the home screen's spare space; taps through to About.
struct ThreeXCFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ThreeXCArt(size: 9, color: Veil.violet.opacity(0.6))
            Text("// 3XCypher · walk unseen").font(Veil.label).foregroundStyle(Veil.muted)
        }
    }
}
