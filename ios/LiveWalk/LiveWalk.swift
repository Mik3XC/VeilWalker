import ActivityKit
import SwiftUI
import VeilWalkerActivity
import WidgetKit

/// The LiveWalk extension: draws the live walk on the lock screen and in the Dynamic Island, in the app's terminal
/// style. The app owns the walk and pushes updates; nothing here reads data or touches the network.
@main
struct LiveWalkBundle: WidgetBundle {
    var body: some Widget {
        LiveWalkActivity()
    }
}

private enum Ink {
    static let violet = Color(red: 0x9D / 255, green: 0x8C / 255, blue: 0xFF / 255)
    static let green = Color(red: 0x3D / 255, green: 0xDC / 255, blue: 0x97 / 255)
    static let dim = Color(red: 0x9A / 255, green: 0x98 / 255, blue: 0xA6 / 255)
    static let background = Color(red: 0x07 / 255, green: 0x07 / 255, blue: 0x0A / 255)
    static func mono(_ style: Font.TextStyle) -> Font { .system(style, design: .monospaced) }
}

/// End of the walk if the stillness continues: 4.5 min after it began.
private func endsAt(_ s: WalkActivityAttributes.ContentState) -> Date? {
    s.stillSince.map { $0.addingTimeInterval(270) }
}

private func title(_ a: WalkActivityAttributes) -> String {
    a.mode == "ONION" ? "Onion Walk · via Tor" : "VeilWalker walk"
}

private func tierGlyph(_ tier: String) -> String {
    switch tier {
    case "onion": "(%)"
    case "gps": "(+)"
    default: "(.)"
    }
}

struct LiveWalkActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Ink.background)
                .activitySystemActionForegroundColor(Ink.violet)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(tierGlyph(s.tier)).font(Ink.mono(.title3)).foregroundStyle(Ink.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(Ink.mono(.title3)).foregroundStyle(Ink.violet).monospacedDigit()
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(s.steps) steps · \(s.tier)").font(Ink.mono(.body)).foregroundStyle(.white)
                        StatusLine(state: s).font(Ink.mono(.caption))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Text(tierGlyph(s.tier)).font(Ink.mono(.caption)).foregroundStyle(s.phase == .redLight ? .red : Ink.green)
            } compactTrailing: {
                Text("\(s.steps)").font(Ink.mono(.caption)).foregroundStyle(Ink.violet).monospacedDigit()
            } minimal: {
                Text(tierGlyph(s.tier)).font(Ink.mono(.caption2)).foregroundStyle(Ink.green)
            }
        }
    }
}

private struct StatusLine: View {
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .walking:
            Text("walking · ends after 4.5 min still").foregroundStyle(Ink.dim)
        case .paused:
            Text("paused").foregroundStyle(Ink.dim)
        case .redLight:
            if let end = endsAt(state) {
                (Text("red light? ends in ") + Text(timerInterval: Date()...end, countsDown: true)).foregroundStyle(.red)
            } else {
                Text("red light?").foregroundStyle(.red)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: WalkActivityAttributes
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(tierGlyph(state.tier)) \(title(attributes))").font(Ink.mono(.subheadline)).foregroundStyle(Ink.green)
                Spacer()
                Text(attributes.startedAt, style: .timer)
                    .font(Ink.mono(.subheadline)).foregroundStyle(Ink.violet).monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            Text("\(state.steps) steps").font(Ink.mono(.title2)).foregroundStyle(Ink.violet)
            StatusLine(state: state).font(Ink.mono(.caption))
        }
        .padding(14)
    }
}
