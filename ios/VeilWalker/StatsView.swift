import SwiftUI
import VeilWalkerCore

/// Day sparkline, week bars with a 10k marker, month sparkline, year/all bars, each with km; then the summary
/// lines. All computed on the phone. Mirrors StatsScreen.kt.
struct StatsView: View {
    @Environment(AppModel.self) private var app
    @SceneStorage("statsRange") private var range = "week"
    private static let ranges = ["day", "week", "month", "year", "all"]

    var body: some View {
        let buckets = buckets(for: range)
        let total = buckets.reduce(0) { $0 + $1.steps }
        let active = app.days.filter { $0.steps > 0 }
        let avg = active.isEmpty ? 0 : active.reduce(0) { $0 + $1.steps } / Int64(active.count)
        let best = app.days.max { $0.steps < $1.steps }
        let goalDays = app.days.filter { $0.steps >= StepChart.goal }.count

        VeilScreen {
            Text("Stats").font(Veil.headline)
            HStack(spacing: 14) {
                ForEach(Self.ranges, id: \.self) { r in
                    Button { range = r } label: {
                        Text(r == range ? "[\(r)]" : r)
                            .fontWeight(r == range ? .bold : .regular)
                            .foregroundStyle(r == range ? Veil.violet : Veil.muted)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            Rectangle().fill(Veil.violet).frame(height: 1)

            Text("\(Fmt.grouped(total)) steps · \(km(total)) km").font(Veil.headlineSmall).foregroundStyle(Veil.violet)
            if range == "day" || range == "month" {
                // Sparkline view: one character per hour / day, labels underneath.
                let every = range == "day" ? 6 : 5
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(StepChart.spark(buckets)).font(Veil.art(22)).tracking(1).foregroundStyle(Veil.green)
                        Text(buckets.enumerated().map { i, b in
                            i % every == 0 ? b.label.padding(toLength: every, withPad: " ", startingAt: 0) : ""
                        }.joined())
                        .font(Veil.art(12)).foregroundStyle(Veil.dim)
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                ForEach(StepChart.bars(buckets, goal: range == "week" ? StepChart.goal : nil, strideM: app.strideM), id: \.self) {
                    Text($0).font(Veil.art(13)).foregroundStyle(Veil.green).lineLimit(1).minimumScaleFactor(0.7)
                }
                if range == "week" {
                    Text("| = 10,000 step goal").font(Veil.small).foregroundStyle(Veil.dim)
                }
            }

            SectionHeader(text: "how you're doing")
            Group {
                Text("avg day      \(Fmt.grouped(avg)) · \(km(avg)) km")
                Text("best day     \(Fmt.grouped(best?.steps ?? 0))" + (best.map { " (\($0.day.dropFirst(5)))" } ?? ""))
                Text("lifetime km  \(km(app.lifetimeSteps))")
                Text("10k days     \(goalDays)")
                Text("days walked  \(active.count)")
            }
            .font(Veil.bodyLarge)
            Text("km = your true steps x your stride (\(Fmt.fixed(app.strideM, 2)) m, calibrated from your GPS walks).")
                .font(Veil.small).foregroundStyle(Veil.muted)
            Text("All of this is computed on your phone.").font(Veil.small).foregroundStyle(Veil.muted)
        }
        .task(id: range) { if range == "day" { await app.loadHourly() } }
    }

    private func km(_ steps: Int64) -> String { Fmt.fixed(Stride.km(steps, strideM: app.strideM), 1) }

    private func buckets(for range: String) -> [Bucket] {
        switch range {
        case "day": StepChart.hourly(app.hourly)
        case "week": StepChart.lastDays(app.days, 7, today: Date())
        case "month": StepChart.lastDays(app.days, 30, today: Date())
        case "year": StepChart.months(app.days, today: Date())
        default: StepChart.years(app.days, today: Date())
        }
    }
}
