import SwiftUI

// The app's button styles. Every one is a Tab stop whatever the system's "Keyboard navigation"
// setting says, shows the shared focus ring while the keyboard is driving, and is pressed with
// Space or Return. The pointer gets AppKit's rules: the action fires on release, and dragging off
// the button before letting go cancels it.

/// The shell every button style shares: one view that is the click target, the Tab stop, and the
/// hover / press state.
///
/// A Tab stop that works with Full Keyboard Access off has to be `.focusable()` with the default
/// interactions, and on macOS that makes the view click-to-focus. The focus click is recognised on
/// mouse-down and wins over ordinary gestures on the same view or on an ancestor: a tap gesture
/// here never completes, and a real `Button` wrapped around it never fires. So the press is a
/// *simultaneous* drag gesture that starts on mouse-down, which the focus click cannot cancel.
struct KeyButton<Label: View, S: InsettableShape>: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let shape: S
    var ring: Color = Theme.focus
    @ViewBuilder let label: (_ pressed: Bool, _ hover: Bool) -> Label
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    @State private var pressed = false
    @State private var hover = false
    @State private var size: CGSize = .zero

    var body: some View {
        label(pressed, hover && enabled)
            .contentShape(shape)
            .background(GeometryReader { geo in
                Color.clear.onChange(of: geo.size, initial: true) { _, new in size = new }
            })
            .focusRing(focused, shape: shape, color: ring)
            .opacity(enabled ? 1 : 0.45)
            .simultaneousGesture(press)
            .focusable(enabled)
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.space) { fire() }
            .onKeyPress(.return) { fire() }
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { configuration.trigger() } }
    }

    /// From mouse-down: `pressed` follows whether the pointer is still over the button, and the
    /// action fires only if it is there on release.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let inside = enabled && over(v.location)
                if pressed != inside { pressed = inside }
            }
            .onEnded { v in
                let hit = pressed && enabled && over(v.location)
                pressed = false
                if hit { configuration.trigger() }
            }
    }

    private func over(_ p: CGPoint) -> Bool {
        CGRect(origin: .zero, size: size).insetBy(dx: -2, dy: -2).contains(p)
    }

    private func fire() -> KeyPress.Result {
        guard enabled else { return .ignored }
        configuration.trigger()
        return .handled
    }
}

/// Primary: an ink capsule with white text. Hover lifts it a shade, a press darkens it.
struct InkButtonStyle: PrimitiveButtonStyle {
    var fill: Color = Theme.deep
    func makeBody(configuration: Configuration) -> some View {
        KeyButton(configuration: configuration, shape: Capsule()) { pressed, hover in
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(fill)
                .overlay(Capsule().fill(pressed ? Color.black.opacity(0.16) : Color.white.opacity(hover ? 0.10 : 0)))
                .clipShape(Capsule())
        }
    }
}

/// Secondary: an outlined capsule on the paper. Hover tints it and darkens the outline, a press tints it more.
struct QuietButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KeyButton(configuration: configuration, shape: Capsule()) { pressed, hover in
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.paper)
                .overlay(Capsule().fill(Theme.ink.opacity(pressed ? 0.12 : hover ? 0.06 : 0)))
                .overlay(Capsule().stroke(hover || pressed ? Theme.inkFaint : Theme.rule, lineWidth: 1))
                .clipShape(Capsule())
        }
    }
}

/// On the timer field: an outlined capsule in the field's off-white.
struct FieldButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KeyButton(configuration: configuration, shape: Capsule(), ring: Theme.onField) { pressed, hover in
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.onField)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Theme.onField.opacity(pressed ? 0.22 : hover ? 0.10 : 0))
                .overlay(Capsule().stroke(Theme.onField.opacity(hover || pressed ? 0.8 : 0.5), lineWidth: 1))
                .clipShape(Capsule())
        }
    }
}

/// A bare symbol that shows it is a button on hover: the bar's chevrons, tray and keyboard icons.
/// Not a Tab stop; each of them has a shortcut and a palette entry.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Icon(configuration: configuration) }

    private struct Icon: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label
                .foregroundColor(hover || configuration.isPressed ? Theme.ink : Theme.inkFaint)
                .frame(minWidth: 24, minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                        .fill(Theme.ink.opacity(configuration.isPressed ? 0.12 : hover ? 0.06 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.12), value: hover)
        }
    }
}

/// A hover tint for a clickable target inside a keyboard control: a segment, a preset, an answer.
private struct HoverTint<S: Shape>: ViewModifier {
    let shape: S
    let active: Bool
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .overlay(shape.fill(Theme.ink.opacity(hover && active ? 0.06 : 0)).allowsHitTesting(false))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

extension View {
    /// Tints the view on hover; pass `active: false` for the already-selected option, which needs no invitation.
    func hoverTint<S: Shape>(_ shape: S, active: Bool = true) -> some View {
        modifier(HoverTint(shape: shape, active: active))
    }
}
