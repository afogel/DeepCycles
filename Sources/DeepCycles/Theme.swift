import SwiftUI
import AppKit

/// A paper-planner look: warm-grey paper, ink for deep work, muted pigments for the rest.
/// Every colour adapts to dark mode via NSColor dynamic providers.
/// User-selectable appearance. "System" follows macOS; "Dark" is the calm night palette.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .system: return "circle.lefthalf.filled"; case .light: return "sun.max"; case .dark: return "moon" }
    }
    func apply() {
        switch self {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum Theme {
    private static func dyn(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
        })
    }

    // Surfaces — light: warm grey paper. dark: soft charcoal-blue, low contrast, nothing pure black or white.
    static let paper     = dyn((246, 244, 239), (31, 33, 38))
    static let paperDeep = dyn((236, 233, 226), (38, 41, 47))
    static let rule      = dyn((203, 199, 189), (66, 70, 78))
    static let ruleFaint = dyn((225, 222, 214), (48, 51, 58))
    static let ink       = dyn((31, 42, 61), (218, 216, 208))
    static let inkFaint  = dyn((122, 128, 140), (138, 143, 152))
    static let nowLine   = dyn((204, 68, 52), (214, 122, 106))

    // Block pigments — dark variants are desaturated and lifted so they sit quietly on the page.
    static let deep     = dyn((36, 66, 118), (128, 158, 204))
    static let shallow  = dyn((126, 132, 140), (138, 144, 152))
    static let meeting  = dyn((118, 72, 128), (168, 140, 180))
    static let tasks    = dyn((196, 122, 42), (208, 162, 108))
    static let breakC   = dyn((84, 128, 84), (132, 172, 140))
    static let overflow = dyn((178, 150, 46), (194, 176, 112))

    // Timer fields — in dark mode the field is only a shade deeper than the page and the digits are off-white.
    static let workField  = dyn((36, 66, 118), (38, 52, 78))
    static let breakField = dyn((84, 128, 84), (50, 74, 58))
    static let onField    = dyn((250, 250, 250), (222, 224, 228))

    // Type
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static let heading = Font.system(size: 15, weight: .semibold, design: .serif)
    static let body = Font.system(size: 13)
    static let small = Font.system(size: 11)
}

// MARK: - Tokens

/// 4-pt spacing scale. Nothing in the UI uses a spacing value outside this list.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Five-step type scale.
enum TypeScale {
    static let caption = Font.system(size: 11)
    static let body = Font.system(size: 13)
    static let label = Font.system(size: 13, weight: .medium)
    static let title = Font.system(size: 17, weight: .semibold, design: .serif)
    static let display = Font.system(size: 24, weight: .semibold, design: .serif)
}

enum Radius {
    static let s: CGFloat = 6
    static let m: CGFloat = 10
}

// MARK: - Reusable modifiers

/// A section: vertical rhythm only. Separation comes from whitespace, not boxes.
struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.vertical, Space.s)
    }
}

struct SectionHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.heading).foregroundColor(Theme.ink)
    }
}

extension View {
    func panel() -> some View { modifier(Panel()) }
}

/// Solid button used for the one primary action on a screen.
struct InkButtonStyle: ButtonStyle {
    var fill: Color = Theme.deep
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(fill.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(Capsule())
    }
}

/// Quiet outlined button for secondary actions.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.paper.opacity(configuration.isPressed ? 0.6 : 1))
            .overlay(Capsule().stroke(Theme.rule, lineWidth: 1))
            .clipShape(Capsule())
    }
}

/// A plain multi-line field that sits on the paper like a writing line.
struct WritingField: View {
    let prompt: String
    @Binding var text: String
    var lines: ClosedRange<Int> = 1...4
    init(_ prompt: String, _ text: Binding<String>, lines: ClosedRange<Int> = 1...4) {
        self.prompt = prompt; self._text = text; self.lines = lines
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(prompt).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink)
            TextField("", text: $text, axis: .vertical)
                .lineLimit(lines)
                .textFieldStyle(.plain)
                .font(Theme.body)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.paperDeep)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}


// MARK: - Wordmark

/// Typography-only logo: "deep" set bold, "cycles" set light, and the full stop
/// drawn as an open ring — a timer that hasn't closed yet.
struct Wordmark: View {
    var size: CGFloat = 16
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("deep").font(.system(size: size, weight: .bold, design: .serif)).foregroundColor(Theme.ink)
            Text("cycles").font(.system(size: size, weight: .light, design: .serif)).foregroundColor(Theme.ink)
            Circle().trim(from: 0.15, to: 1)
                .stroke(Theme.deep, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size * 0.3, height: size * 0.3)
                .padding(.leading, size * 0.12)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
        }
        .fixedSize()
        .accessibilityLabel("DeepCycles")
    }
}
