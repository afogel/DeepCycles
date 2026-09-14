import SwiftUI
import AppKit

/// Whether the most recent input came from the keyboard. A click gives a control focus too, and a
/// ring left behind after a click reads as a stuck highlight, so the ring shows only while the
/// keyboard is driving, the way the web's `:focus-visible` and macOS's own controls behave.
final class InputSource: ObservableObject {
    static let shared = InputSource()
    @Published private(set) var keyboard = false
    private var monitor: Any?

    private init() {
        // Local monitors run on the main thread, before the event reaches the view.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            let fromKeyboard = event.type == .keyDown
            if let self, self.keyboard != fromKeyboard { self.keyboard = fromKeyboard }
            return event
        }
    }
}

private struct FocusRing<S: InsettableShape>: ViewModifier {
    let on: Bool
    let shape: S
    let color: Color
    let keyboardOnly: Bool
    @ObservedObject private var input: InputSource

    init(on: Bool, shape: S, color: Color, keyboardOnly: Bool) {
        self.on = on
        self.shape = shape
        self.color = color
        self.keyboardOnly = keyboardOnly
        _input = ObservedObject(wrappedValue: InputSource.shared)
    }

    func body(content: Content) -> some View {
        let shown = on && (!keyboardOnly || input.keyboard)
        content.overlay(
            ZStack {
                shape.inset(by: -3).stroke(color.opacity(0.22), lineWidth: 4)
                shape.inset(by: -2).stroke(color.opacity(0.7), lineWidth: 1.25)
            }
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: shown)
            .allowsHitTesting(false)
        )
    }
}

extension View {
    /// The app's focus ring: a faint halo with a thin line inside it, just outside `shape`, fading
    /// in while `on`. Shown only while the keyboard is driving, unless `keyboardOnly` is false:
    /// text fields show it whenever they are editing, since a caret alone is easy to lose on the page.
    func focusRing<S: InsettableShape>(_ on: Bool, shape: S, color: Color = Theme.focus, keyboardOnly: Bool = true) -> some View {
        modifier(FocusRing(on: on, shape: shape, color: color, keyboardOnly: keyboardOnly))
    }
}
