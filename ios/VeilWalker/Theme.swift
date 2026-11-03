import SwiftUI
import UIKit

/// Always dark, always monospace: near-black with a violet "veil" accent and one green signal colour.
/// Same values as Android's Theme.kt. No light mode, on purpose: the look is part of the identity.
enum Veil {
    static let violet = Color(hex: 0x9D8CFF)
    static let onViolet = Color(hex: 0x0B0A12)
    static let green = Color(hex: 0x3DDC97)
    static let background = Color(hex: 0x07070A)
    static let text = Color(hex: 0xD8D6E0)
    static let surface = Color(hex: 0x101016)
    static let dim = Color(hex: 0x9A98A6)
    static let muted = Color(hex: 0x34333F)
    static let ice = Color(hex: 0x8FD3FF)

    // Material 3 type scale mapped onto Dynamic Type styles, all monospaced.
    static let headline = Font.system(.title, design: .monospaced)                       // headlineMedium 28
    static let headlineSmall = Font.system(.title2, design: .monospaced)                 // headlineSmall 24
    static let titleLarge = Font.system(.title2, design: .monospaced)                    // titleLarge 22
    static let titleMedium = Font.system(.callout, design: .monospaced).weight(.medium)  // titleMedium 16
    static let titleSmall = Font.system(.subheadline, design: .monospaced).weight(.medium)
    static let bodyLarge = Font.system(.callout, design: .monospaced)                    // bodyLarge 16 (Compose default)
    static let body = Font.system(.footnote, design: .monospaced)                        // bodyMedium 14 (13 so status lines fit)
    static let small = Font.system(.caption, design: .monospaced)                        // bodySmall 12
    static let label = Font.system(.caption2, design: .monospaced)                       // labelSmall 11

    /// Fixed-size monospace for ASCII art, which must not reflow.
    static func art(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Terminal-style action: just `> label` in violet monospace, no box. The whole row is the touch target and flashes
/// inverted while pressed. `filled` marks the main action (green). Mirrors VeilButton.kt.
struct VeilButton: View {
    let label: String
    var glyph = ">"
    var filled = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: { EmptyView() }
            .buttonStyle(Style(text: "\(glyph) \(label.lowercased())", accent: filled ? Veil.green : Veil.violet, filled: filled))
            .disabled(!enabled)
    }

    private struct Style: ButtonStyle {
        let text: String
        let accent: Color
        let filled: Bool
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed && isEnabled
            Text(text)
                .font(Veil.bodyLarge.weight(filled ? .bold : .regular))
                .tracking(0.5)
                .foregroundStyle(!isEnabled ? Veil.muted : pressed ? Veil.onViolet : accent)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(pressed ? accent : .clear)
                .contentShape(Rectangle())
        }
    }
}

/// Plain tappable text (`= journeys`, `~ stats`), no chrome. Muted and inert when `action` is nil (not built yet).
struct TextLink: View {
    let label: String
    var color = Veil.violet
    var font = Veil.bodyLarge
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button { Haptics.tap(); action() } label: {
                Text(label).font(font).foregroundStyle(color).padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(label).font(font).foregroundStyle(Veil.muted).padding(.vertical, 6)
        }
    }
}

/// A scrolling sub-screen with the standard padding and `< back` pinned top left, where iPhone users look for it
/// (Android has a system back button; iPhone doesn't). The edge swipe goes back too.
struct VeilScreen<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 4) { BackBar() }
        .background(VeilBackdrop())
        .foregroundStyle(Veil.text)
        .font(Veil.bodyLarge)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The top bar of every sub-screen: `< back`, top left. A plain terminal line over a solid strip in Terminal, a glass
/// capsule floating over the content in Glass.
struct BackBar: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Look.key) private var look = Look.terminal.rawValue

    var body: some View {
        HStack {
            Button { Haptics.tap(); dismiss() } label: {
                Text("< back").font(Veil.bodyLarge).foregroundStyle(Veil.violet)
                    .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(GlassCapsule(on: look == Look.glass.rawValue))
            .accessibilityLabel("back")
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
        .background(look == Look.glass.rawValue ? Color.clear : Veil.background.opacity(0.94))
    }
}

private struct GlassCapsule: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on, #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
        }
    }
}

/// Hiding the navigation bar also turns off iPhone's swipe-from-the-edge back gesture; this turns it back on.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

/// `// section` header in green, terminal comment style.
struct SectionHeader: View {
    let text: String
    var body: some View {
        Text("// \(text)").foregroundStyle(Veil.green).fontWeight(.bold).padding(.top, 8)
    }
}

/// The VeilWalker mark: a framed V with a green dot and a soft glow. Same paths as Android's ic_logo.xml.
struct LogoMark: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 48, y: size.height / 48)
            var frame = Path()
            frame.addRect(CGRect(x: 4, y: 4, width: 40, height: 40))
            var v = Path()
            v.move(to: CGPoint(x: 11, y: 12))
            v.addLine(to: CGPoint(x: 24, y: 37))
            v.addLine(to: CGPoint(x: 37, y: 12))
            ctx.stroke(frame, with: .color(Veil.violet.opacity(0.25)), lineWidth: 6)
            ctx.stroke(v, with: .color(Veil.violet.opacity(0.25)), style: StrokeStyle(lineWidth: 8, lineJoin: .miter))
            ctx.stroke(frame, with: .color(Color(hex: 0xB4A4FF)), lineWidth: 2.8)
            ctx.stroke(v, with: .color(Color(hex: 0xA796FF)), style: StrokeStyle(lineWidth: 4.4, lineCap: .butt, lineJoin: .miter))
            ctx.fill(Path(ellipseIn: CGRect(x: 20.4, y: 13.4, width: 7.2, height: 7.2)), with: .color(Color(hex: 0x3DF0A8)))
        }
        .accessibilityHidden(true)
    }
}

// MARK: Looks

/// Two looks, same content: Terminal (the Android look: flat near-black, thin rules) and Glass (iOS 26 Liquid Glass
/// panels over a drifting aurora and an ASCII field, still all monospace). Switch on the account screen or by
/// tapping the logo on the home screen.
enum Look: String {
    case terminal, glass
    static let key = "look"

    var next: Look { self == .terminal ? .glass : .terminal }
    var title: String { self == .terminal ? "terminal" : "glass" }
}

/// The full-screen backdrop behind every screen. Everything here is drawn once and moved by Core Animation on the
/// GPU: a per-frame redraw on the main thread (the first version) starved taps on a real iPhone.
struct VeilBackdrop: View {
    @AppStorage(Look.key) private var look = Look.terminal.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            Veil.background
            if look == Look.glass.rawValue {
                GeometryReader { g in
                    ZStack {
                        AsciiField()
                            .frame(width: g.size.width + 120, height: g.size.height + 120)
                            .offset(x: drift ? -50 : 10, y: drift ? -40 : 10)
                            .opacity(0.11)
                        blob(Veil.violet, 420).position(x: g.size.width * (drift ? 0.35 : 0.15), y: g.size.height * (drift ? 0.38 : 0.22))
                        blob(Veil.green, 300).position(x: g.size.width * (drift ? 0.72 : 0.92), y: g.size.height * (drift ? 0.82 : 0.68))
                        blob(Color(hex: 0x4B3BD6), 380).position(x: g.size.width * (drift ? 0.62 : 0.4), y: g.size.height * (drift ? 1.0 : 1.08))
                    }
                    .drawingGroup()   // one GPU layer
                }
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
                }
            } else {
                Scanlines().opacity(0.05)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func blob(_ c: Color, _ size: CGFloat) -> some View {
        Circle().fill(c.opacity(0.45)).frame(width: size, height: size).blur(radius: 90)
    }
}

/// A fixed field of ASCII characters, drawn once: what the glass refracts. Each glyph is laid out once and stamped.
private struct AsciiField: View {
    private static let glyphs = Array(" .:-=+*#%@")

    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 14
            let resolved = Self.glyphs.map {
                ctx.resolve(Text(String($0)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Veil.violet))
            }
            let cols = Int(size.width / cell) + 1, rows = Int(size.height / cell) + 1
            for r in 0..<rows {
                for c in 0..<cols {
                    let v = sin(Double(c) * 0.35) + cos(Double(r) * 0.28) + sin(Double(c + r) * 0.15)
                    let i = min(max(Int((v + 3) / 6 * Double(Self.glyphs.count - 1)), 0), Self.glyphs.count - 1)
                    if i > 0 { ctx.draw(resolved[i], at: CGPoint(x: CGFloat(c) * cell, y: CGFloat(r) * cell)) }
                }
            }
        }
    }
}

/// Faint CRT scanlines for the Terminal look.
private struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white))
                y += 3
            }
        }
    }
}

/// A content panel: nothing extra in Terminal (or an outline when `outlined`), Liquid Glass in Glass.
struct VeilPanel: ViewModifier {
    var outlined = false
    var outline = Veil.muted
    var lineWidth: CGFloat = 1
    var padding: CGFloat = 12
    @AppStorage(Look.key) private var look = Look.terminal.rawValue

    func body(content: Content) -> some View {
        if look == Look.glass.rawValue {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            if #available(iOS 26.0, *) {
                content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular.tint(Veil.violet.opacity(0.06)), in: shape)
                    .overlay(shape.stroke(outline == Veil.muted ? Color.white.opacity(0.08) : outline.opacity(0.7), lineWidth: lineWidth))
            } else {
                content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: lineWidth))
            }
        } else if outlined {
            content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
                .background(Veil.surface)
                .overlay(Rectangle().stroke(outline, lineWidth: lineWidth))
        } else {
            content
        }
    }
}

extension View {
    func veilPanel(outlined: Bool = false, outline: Color = Veil.muted, lineWidth: CGFloat = 1, padding: CGFloat = 12) -> some View {
        modifier(VeilPanel(outlined: outlined, outline: outline, lineWidth: lineWidth, padding: padding))
    }

    /// Phosphor glow for the numbers and signals that matter.
    func glow(_ c: Color, radius: CGFloat = 8) -> some View {
        shadow(color: c.opacity(0.55), radius: radius)
    }
}

enum Haptics {
    @MainActor static func tap() { UISelectionFeedbackGenerator().selectionChanged() }
}
