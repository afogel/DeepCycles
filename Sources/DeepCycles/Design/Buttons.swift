import SwiftUI

// The app's button styles. Every one is a Tab stop whatever the system's "Keyboard navigation"
// setting says, shows the shared focus ring, and is pressed with Space or Return.

/// Body shared by the button styles: clickable, a Tab stop, pressed with Space or Return.
/// (Return still goes to the window's default button when a screen has one.)
struct KeyButton<Label: View, S: InsettableShape>: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let shape: S
    var ring: Color = Theme.focus
    @ViewBuilder let label: (_ pressed: Bool) -> Label
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    @State private var pressed = false

    var body: some View {
        label(pressed)
            .contentShape(shape)
            .focusRing(focused, shape: shape, color: ring)
            .opacity(enabled ? 1 : 0.45)
            .focusable(enabled)
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.space) { fire() }
            .onKeyPress(.return) { fire() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
            .onTapGesture { if enabled { configuration.trigger() } }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { configuration.trigger() } }
    }

    private func fire() -> KeyPress.Result {
        guard enabled else { return .ignored }
        configuration.trigger()
        return .handled
    }
}

/// Solid button used for the one primary action on a screen.
struct InkButtonStyle: PrimitiveButtonStyle {
    var fill: Color = Theme.deep
    func makeBody(configuration: Configuration) -> some View {
        KeyButton(configuration: configuration, shape: Capsule()) { pressed in
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(fill.opacity(pressed ? 0.75 : 1))
                .clipShape(Capsule())
        }
    }
}

/// Quiet outlined button for secondary actions.
struct QuietButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KeyButton(configuration: configuration, shape: Capsule()) { pressed in
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.paper.opacity(pressed ? 0.6 : 1))
                .overlay(Capsule().stroke(Theme.rule, lineWidth: 1))
                .clipShape(Capsule())
        }
    }
}

/// Outlined button that sits on a timer field (pale on the work / break colour).
struct FieldButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KeyButton(configuration: configuration, shape: Capsule(), ring: Theme.onField) { pressed in
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.onField)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Theme.onField.opacity(pressed ? 0.18 : 0))
                .overlay(Capsule().stroke(Theme.onField.opacity(0.5), lineWidth: 1))
                .clipShape(Capsule())
        }
    }
}
