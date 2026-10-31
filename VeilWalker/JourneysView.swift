import SwiftUI
import VeilWalkerCore

/// Every journey: the live one first, then the locked ones, then Outlaws on Foot and the Hidden Peaks. Cards load in
/// one at a time, like lines arriving in a terminal. Mirrors JourneyViews.kt.
struct JourneysView: View {
    @Environment(AppModel.self) private var app
    @Binding var path: [Screen]
    @State private var shown = 0
    private static let revealMs = 220

    var body: some View {
        let all = app.content.all
        let outlaws = app.content.outlaws
        let collected = outlaws.filter { app.lifetimeSteps >= ($0.card?.steps ?? .max) }.count

        VeilScreen(spacing: 12) {
            Text("Journeys").font(Veil.headline)
            Text("Walk for Freedom · \(all.count - outlaws.count) journeys · 1 open").foregroundStyle(Veil.dim)
            Text("Outlaws on Foot · \(collected)/\(outlaws.count) cards collected").foregroundStyle(Veil.dim)

            ForEach(Array(all.enumerated()), id: \.element.id) { i, j in
                if i < shown {
                    VStack(alignment: .leading, spacing: 12) {
                        if let collection = j.card?.collection, collection != (i > 0 ? all[i - 1].card?.collection : nil) {
                            SectionHeader(text: collection).padding(.top, 4)
                        }
                        if j.route != nil {
                            RouteCardView(progress: app.route)
                            VeilButton(label: "Learn more: \(j.title)") { path.append(.journey(j.id)) }
                        } else if j.card != nil {
                            OutlawCardView(journey: j, lifetime: app.lifetimeSteps) { path.append(.journey(j.id)) }
                        } else {
                            LockedJourneyCard(journey: j) { path.append(.journey(j.id)) }
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 12)))
                }
            }
            if shown < all.count {
                Text("loading \(shown + 1)/\(all.count)_").foregroundStyle(Veil.green)
            } else {
                SectionHeader(text: app.content.peaksTitle).padding(.top, 4)
                let climbed = app.coldClimbM
                let next = app.content.peaks.first { climbed < Double($0.heightM) }
                ForEach(app.content.peaks) { p in
                    PeakCardView(peak: p, climbedM: climbed, isNext: p.id == next?.id) { path.append(.peak(p.id)) }
                }
            }
        }
        .task {
            while shown < all.count {
                try? await Task.sleep(for: .milliseconds(Self.revealMs))
                withAnimation(.easeOut(duration: 0.3)) { shown += 1 }
            }
        }
    }
}

/// A journey you can't walk yet: same frame as the live card, everything dimmed, with a lock.
struct LockedJourneyCard: View {
    let journey: Journey
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                (Text("[#] ").foregroundStyle(Veil.muted) + Text(journey.title.uppercased()).foregroundStyle(Veil.dim)).fontWeight(.bold)
                Text(journey.subtitle).font(Veil.small).foregroundStyle(Veil.muted)
                Text("[..........] ~\(Fmt.grouped(journey.km)) km · \(journey.postcards) cards").font(Veil.small).foregroundStyle(Veil.muted)
                Text(journey.teaser).font(Veil.body).foregroundStyle(Veil.dim)
                Text((journey.unlock == "coming soon" ? "// coming soon" : "// unlock: \(journey.unlock)") + "   > learn more")
                    .font(Veil.small).foregroundStyle(Veil.green.opacity(0.6))
            }
            .cardFrame(color: Veil.muted)
        }
        .buttonStyle(.plain)
    }
}

/// An Outlaws on Foot collectible: rarity, the quote, and a progress bar toward its step target.
struct OutlawCardView: View {
    let journey: Journey
    let lifetime: Int64
    let onOpen: () -> Void

    var body: some View {
        if let c = journey.card {
            let got = lifetime >= c.steps
            let high = c.rarity >= .legendary
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    (Text(got ? "[+] " : "[#] ").foregroundStyle(got ? Veil.green : Veil.muted)
                     + Text(journey.title.uppercased()).foregroundStyle(got ? Veil.green : Veil.dim)).fontWeight(.bold)
                    Text("\(c.rarity.label) · \(journey.subtitle)").font(Veil.small).foregroundStyle(high ? Veil.violet : Veil.muted)
                    Text("“\(c.quote)”").font(Veil.body).foregroundStyle(Veil.dim)
                    Text(Ascii.barOnly(Double(lifetime) / Double(c.steps)) + " "
                         + (got ? "collected" : "\(AchievementRules.compact(min(lifetime, c.steps))) / \(AchievementRules.compact(c.steps))"))
                        .font(Veil.small).foregroundStyle(got ? Veil.green : Veil.muted)
                    Text("> learn more").font(Veil.small).foregroundStyle(Veil.green.opacity(0.6))
                }
                .cardFrame(color: got ? Veil.green : c.rarity == .boss ? Veil.violet : Veil.muted, width: high ? 2 : 1)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A Hidden Peaks card: climbed peaks in full (K2 as the Demon), the next one as a progress bar, the rest "???".
struct PeakCardView: View {
    let peak: Peak
    let climbedM: Double
    let isNext: Bool
    let onOpen: () -> Void

    var body: some View {
        let got = climbedM >= Double(peak.heightM)
        let accent = peak.demon ? Veil.violet : Veil.ice
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                if !got {
                    Text("[?] HIDDEN PEAK").fontWeight(.bold).foregroundStyle(Veil.muted)
                    if isNext {
                        Text(Ascii.barOnly(climbedM / Double(peak.heightM)) + " \(Fmt.grouped(Int64(climbedM))) m cold climb")
                            .font(Veil.small).foregroundStyle(Veil.muted)
                        Text("walk when you see the ❄ (hills count extra)").font(Veil.small).foregroundStyle(Veil.dim)
                    } else {
                        Text("??? · ?,??? m").font(Veil.small).foregroundStyle(Veil.muted)
                    }
                } else {
                    if peak.demon { AvatarArt(index: 3, size: 10) }
                    (Text("[^] ") + Text(peak.name.uppercased())).fontWeight(.bold).foregroundStyle(accent)
                    Text("\(peak.region) · \(Fmt.grouped(peak.heightM)) m / \(Fmt.grouped(peak.heightFt)) ft").font(Veil.small).foregroundStyle(Veil.dim)
                    Text("“\(peak.quote)”").font(Veil.body).foregroundStyle(Veil.dim)
                    if peak.demon { Text("[)v(] THE CROWLEY AWARD").fontWeight(.bold).foregroundStyle(Veil.violet) }
                    Text("> learn more").font(Veil.small).foregroundStyle(Veil.green.opacity(0.6))
                }
            }
            .cardFrame(color: got ? accent : Veil.muted, width: peak.demon && got ? 2 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!got)
    }
}

/// Everything we know about one journey: the teaser, a timeline of facts, and why it's in VeilWalker.
struct JourneyDetailView: View {
    @Environment(AppModel.self) private var app
    let id: String

    var body: some View {
        if let j = app.content.journey(id: id) {
            let card = j.card
            let got = card.map { app.lifetimeSteps >= $0.steps } ?? false
            VeilScreen(spacing: 10) {
                Text(j.route != nil ? "[>] WALKING NOW" : got ? "[+] COLLECTED" : card.map { "[#] \($0.rarity.label) · LOCKED" } ?? "[#] LOCKED")
                    .fontWeight(.bold).foregroundStyle(j.route != nil || got ? Veil.green : Veil.muted)
                Text(j.title).font(Veil.headline)
                Text(j.subtitle).foregroundStyle(Veil.dim)
                if let card {
                    Text("“\(card.quote)”").font(Veil.titleMedium).foregroundStyle(Veil.violet)
                    Text("\(Fmt.grouped(min(app.lifetimeSteps, card.steps))) / \(Fmt.grouped(card.steps)) steps (~\(Fmt.grouped(j.km)) km)")
                        .foregroundStyle(Veil.violet)
                    Text(card.collection).font(Veil.small).foregroundStyle(Veil.dim)
                } else {
                    Text("~\(Fmt.grouped(j.km)) km · \(j.postcards) postcards").foregroundStyle(Veil.violet)
                }
                Text(j.teaser)
                SectionHeader(text: "timeline")
                Timeline(facts: j.facts)
                if !j.why.isEmpty {
                    SectionHeader(text: "why it's here")
                    Text(j.why).font(Veil.body).foregroundStyle(Veil.dim)
                }
                Text(j.route != nil ? "// you're on it" : got ? "// in your collection"
                     : j.unlock == "coming soon" ? "// coming soon" : "// unlock: \(j.unlock)")
                    .foregroundStyle(Veil.green.opacity(0.7))
                if card != nil {
                    Text("History is real; the step target and rarity are game mechanics.").font(Veil.small).foregroundStyle(Veil.muted)
                }
                Text("Draft history, pending review. Spotted an error? premiselayer@gmail.com").font(Veil.small).foregroundStyle(Veil.muted)
            }
        }
    }
}

/// A climbed peak's story. Only reachable once climbed, so the deck stays hidden.
struct PeakDetailView: View {
    @Environment(AppModel.self) private var app
    let id: String

    var body: some View {
        if let p = app.content.peak(id: id) {
            VeilScreen(spacing: 10) {
                Text(p.demon ? "[)v(] SUMMITED · THE CROWLEY AWARD" : "[^] SUMMITED").fontWeight(.bold)
                    .foregroundStyle(p.demon ? Veil.violet : Veil.green)
                if p.demon { AvatarArt(index: 3, size: 12) }
                Text(p.name).font(Veil.headline)
                Text(p.region).foregroundStyle(Veil.dim)
                Text("\(Fmt.grouped(p.heightM)) m · \(Fmt.grouped(p.heightFt)) ft").foregroundStyle(Veil.violet)
                Text("“\(p.quote)”").font(Veil.titleMedium).foregroundStyle(Veil.violet)
                SectionHeader(text: "timeline")
                Timeline(facts: p.facts)
                Text("You climbed its full height on freezing walks: every cold step is 7 cm of mountain trail, and real hills, measured by your barometer, count on top.")
                    .font(Veil.small).foregroundStyle(Veil.muted)
            }
        }
    }
}

private struct Timeline: View {
    let facts: [String]
    var body: some View {
        ForEach(facts, id: \.self) { f in
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("▸ ").foregroundStyle(Veil.violet)
                Text(f).font(Veil.body)
            }
        }
    }
}

extension View {
    /// The square, outlined card frame every journey, outlaw and peak card uses.
    func cardFrame(color: Color, width: CGFloat = 1) -> some View {
        veilPanel(outlined: true, outline: color, lineWidth: width, padding: 16).contentShape(Rectangle())
    }
}
