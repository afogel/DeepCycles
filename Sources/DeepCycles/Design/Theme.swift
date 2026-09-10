import SwiftUI
import AppKit
import DeepCyclesCore

/// A paper-planner look: warm-grey paper, ink for deep work, muted pigments for the rest.
/// Every colour adapts to dark mode via NSColor dynamic providers.
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

    /// Focus ring colour for the keyboard controls (Controls.swift).
    static let focus = deep

    // Type
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static let heading = Font.system(size: 15, weight: .semibold, design: .serif)
    static let body = Font.system(size: 13)
    static let small = Font.system(size: 11)
}

extension Appearance {
    /// "System" follows macOS; "Dark" is the calm night palette.
    func apply() {
        switch self {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension BlockKind {
    var color: Color {
        switch self {
        case .deep: return Theme.deep
        case .shallow: return Theme.shallow
        case .meeting: return Theme.meeting
        case .tasks: return Theme.tasks
        case .breakTime: return Theme.breakC
        case .overflow: return Theme.overflow
        }
    }
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

    /// The app's keyboard-focus ring, drawn just outside `shape` while `on`.
    func focusRing<S: InsettableShape>(_ on: Bool, shape: S, color: Color = Theme.focus) -> some View {
        overlay(
            shape.inset(by: -3)
                .stroke(color, lineWidth: 2)
                .opacity(on ? 1 : 0)
                .allowsHitTesting(false)
        )
    }
}
