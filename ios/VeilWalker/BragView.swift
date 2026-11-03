import SwiftUI
import UIKit
import VeilWalkerCore

/// The brag engine: a 1080×1350 (4:5) JPEG of avatar, handle and today's steps, the shape X, Instagram, Facebook,
/// Bluesky and Threads all accept. Rendered from a SwiftUI view, so the file carries no EXIF, no location and nothing
/// about where you walked. Same layout as Android's BragCard.kt.
struct BragCard: View {
    static let size = CGSize(width: 1080, height: 1350)
    static let goal: Int64 = 10_000

    let avatar: Int
    let handle: String?
    let clan: String?
    let rank: String
    let today: Int64
    let km: Double
    let lifetime: Int64
    let date: Date

    var body: some View {
        let cells = 20
        let filled = Int(min(max(today * Int64(cells) / Self.goal, 0), Int64(cells)))
        ZStack(alignment: .topLeading) {
            Veil.background
            // Header: logo + name, violet rule underneath (same as the home screen).
            LogoMark().frame(width: 96, height: 96).offset(x: 80, y: 70)
            Text("VeilWalker").font(.system(size: 60, weight: .bold, design: .monospaced)).foregroundStyle(Veil.text)
                .offset(x: 200, y: 82)
            Rectangle().fill(Veil.violet).frame(width: 920, height: 4).offset(x: 80, y: 200)

            VStack(spacing: 0) {
                Text(Avatars.all[Avatars.clamp(avatar)].art)
                    .font(.system(size: 54, weight: .bold, design: .monospaced)).lineSpacing(12).foregroundStyle(Veil.violet)
                    .fixedSize()
                    .frame(height: 350)
                    .padding(.top, 262)
                Text((clan.map { "[\($0)] " } ?? "") + (handle ?? "anon"))
                    .font(.system(size: 58, weight: .bold, design: .monospaced)).foregroundStyle(Veil.text).padding(.top, 50)
                Text("// \(rank)").font(.system(size: 34, design: .monospaced)).foregroundStyle(Veil.green).padding(.top, 8)
                Text(Fmt.grouped(today)).font(.system(size: 170, weight: .bold, design: .monospaced)).foregroundStyle(Veil.violet)
                    .minimumScaleFactor(0.5).lineLimit(1).padding(.top, 10)
                Text("steps today · \(Fmt.fixed(km, 1)) km").font(.system(size: 44, design: .monospaced)).foregroundStyle(Veil.dim)
                Text("[" + String(repeating: "#", count: filled) + String(repeating: ".", count: cells - filled) + "]")
                    .font(.system(size: 50, weight: .bold, design: .monospaced)).foregroundStyle(Veil.green).padding(.top, 36)
                Text(today >= Self.goal ? "10k goal smashed" : "\(today * 100 / Self.goal)% of 10k")
                    .font(.system(size: 36, design: .monospaced)).foregroundStyle(Veil.green)
            }
            .frame(width: Self.size.width)

            Rectangle().fill(Veil.muted).frame(width: 920, height: 2).offset(x: 80, y: 1170)
            HStack {
                Text("lifetime \(Fmt.grouped(lifetime))").foregroundStyle(Veil.text)
                Spacer()
                Text(Self.dateText(date)).foregroundStyle(Veil.dim)
            }
            .font(.system(size: 36, design: .monospaced))
            .frame(width: 920)
            .offset(x: 80, y: 1192)
            Text("walk the world. leave no trace.").font(.system(size: 34, design: .monospaced)).foregroundStyle(Veil.violet)
                .frame(width: Self.size.width).offset(y: 1262)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }

    /// JPEG bytes at 92%, like Android. ImageRenderer output has no metadata to strip.
    @MainActor func jpeg() -> Data? {
        let r = ImageRenderer(content: self)
        r.scale = 1
        r.proposedSize = ProposedViewSize(Self.size)
        return r.uiImage?.jpegData(compressionQuality: 0.92)
    }
}

struct BragView: View {
    @Environment(AppModel.self) private var app
    @State private var file: URL?
    @State private var image: UIImage?
    @State private var note: String?

    var body: some View {
        VeilScreen {
            Text("Brag").font(Veil.headline)
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                    .accessibilityLabel("Brag card: \(app.todaySteps) steps today")
            }
            Text("No location, no map, no metadata: just the picture.").font(Veil.small).foregroundStyle(Veil.muted)
            if let file {
                ShareLink(item: file) { Text("> share").foregroundStyle(Veil.violet).padding(.vertical, 6) }
            }
            VeilButton(label: "Save JPG", glyph: "v", enabled: image != nil) { save() }
            if let note { Text(note).font(Veil.small).foregroundStyle(Veil.green) }
        }
        .task { render() }
    }

    private func render() {
        let card = BragCard(avatar: app.avatar, handle: app.handle, clan: app.clan, rank: app.outlawRank, today: app.todaySteps,
                            km: app.todayKm, lifetime: app.lifetimeSteps, date: Date())
        guard let data = card.jpeg() else { return }
        image = UIImage(data: data)
        // Shared as a file named like Android's (veilwalker-2026-10-30.jpg); old ones are cleared first.
        let dir = FileManager.default.temporaryDirectory.appending(path: "brag", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "veilwalker-\(LocalDays().day(Date())).jpg")
        if (try? data.write(to: url)) != nil { file = url }
    }

    /// Add-only Photos access: VeilWalker can save the card but never read your library.
    private func save() {
        guard let image else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        note = "saved to Photos"
    }
}
