import SwiftUI
import VeilWalkerCore

/// Rank, outlaw rank and frost, then every badge family with its rank-framed glyph. Secret badges stay "?????"
/// until earned. Mirrors BadgesScreen.kt.
struct BadgesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let b = app.board
        let nextRank = Rank.allCases.first { $0.minBadges > b.unlockedCount }
        let nextFrost = Frost.allCases.first { $0.minMinutes > b.snowflakeMinutes }

        VeilScreen(spacing: 6) {
            Text("Badges").font(Veil.headline)
            Text("rank: \(b.rank.title)").foregroundStyle(Veil.green).fontWeight(.bold)
            Text(Ascii.barOnly(Double(b.unlockedCount) / Double(max(b.all.count, 1))) + "  \(b.unlockedCount)/\(b.all.count)")
                .foregroundStyle(Veil.violet)
            if let nextRank {
                Text("\(nextRank.minBadges - b.unlockedCount) more for \(nextRank.title)").foregroundStyle(Veil.dim)
            }
            Text("outlaw rank: \(b.outlawRank)").foregroundStyle(Veil.green).fontWeight(.bold)
            Text(b.nextOutlaw.map { "walk \(AchievementRules.compact($0.threshold)) lifetime steps to make \($0.name.uppercased())" }
                 ?? "KINGPIN. the whole smuggler army answers to you")
                .font(Veil.small).foregroundStyle(Veil.dim)
            Text("frost: \(b.frost.title)" + (b.frost == .none ? "" : " · \(b.snowflakeMinutes) min hosted"))
                .foregroundStyle(b.frost == .none ? Veil.muted : Veil.green).fontWeight(.bold)
            Text(nextFrost.map { "host Snowflake on walks: \($0.minMinutes - b.snowflakeMinutes) more min for \($0.title), frosts every badge" }
                 ?? "max frost. every badge is aurora")
                .font(Veil.small).foregroundStyle(Veil.dim)

            ForEach(families(b.all), id: \.first!.family) { family in
                Text(" ")   // spacer line, terminal style
                ForEach(family) { a in row(a, board: b) }
            }
            Text(" ")
        }
    }

    private func row(_ a: Achievement, board b: BadgeBoard) -> some View {
        let got = b.unlockedAt[a.id] != nil
        let hidden = a.secret && !got
        return HStack(alignment: .top, spacing: 0) {
            Text(got ? b.frost.apply(b.rank.frame(a.glyph)) : " \(a.glyph) ")
                .foregroundStyle(got ? Veil.violet : Veil.muted)
                .frame(width: 104, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text((got ? "[x] " : "[ ] ") + (hidden ? "?????" : a.name.uppercased()))
                    .foregroundStyle(got ? Veil.violet : Veil.dim)
                    .fontWeight(got ? .bold : .regular)
                Text(hidden ? "secret" : a.description).font(Veil.small).foregroundStyle(got ? Veil.dim : Veil.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Families in file order.
    private func families(_ all: [Achievement]) -> [[Achievement]] {
        var out: [[Achievement]] = []
        for a in all {
            if out.last?.first?.family == a.family { out[out.count - 1].append(a) } else { out.append([a]) }
        }
        return out
    }
}
