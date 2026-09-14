import SwiftUI

/// A prompt over a growing text field: the writing surface of the Prepare, Plan, Review and
/// Debrief screens.
struct WritingField<F: Hashable>: View {
    let prompt: String
    @Binding var text: String
    var lines: ClosedRange<Int> = 1...4
    var focus: FocusState<F?>.Binding? = nil
    var tag: F? = nil

    init(_ prompt: String, _ text: Binding<String>, lines: ClosedRange<Int> = 1...4, focus: FocusState<F?>.Binding, tag: F) {
        self.prompt = prompt
        self._text = text
        self.lines = lines
        self.focus = focus
        self.tag = tag
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink)
            field
                .lineLimit(lines)
                .font(Theme.body)
                .inputChrome()
        }
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField("", text: $text, axis: .vertical)
        if let focus, let tag { base.focused(focus, equals: tag) } else { base }
    }
}

extension WritingField where F == Never {
    init(_ prompt: String, _ text: Binding<String>, lines: ClosedRange<Int> = 1...4) {
        self.prompt = prompt
        self._text = text
        self.lines = lines
    }
}

/// The look every text input shares: a field lifted off the paper by a hairline rule and a
/// whisper of shadow. While the caret is inside, the rule takes the focus colour and a soft halo,
/// whether the keyboard or the mouse put it there.
struct InputChrome: ViewModifier {
    var radius: CGFloat = Radius.input
    var horizontal: CGFloat = Space.m
    var vertical: CGFloat = 9
    @FocusState private var editing: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .textFieldStyle(.plain)
            .focused($editing)
            .padding(.horizontal, horizontal).padding(.vertical, vertical)
            .background(shape.fill(Theme.field).shadow(color: Color.black.opacity(0.05), radius: 1, y: 1))
            .overlay(shape.strokeBorder(editing ? Theme.focus : Theme.fieldRule, lineWidth: editing ? 1.5 : 1))
            .overlay(
                shape.inset(by: -2.5)
                    .stroke(Theme.focus.opacity(editing ? 0.16 : 0), lineWidth: 3)
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.12), value: editing)
    }
}

extension View {
    /// Dresses a plain `TextField` as one of the app's inputs. `vertical` is the field's inner
    /// vertical padding; single-line fields in tight places pass `Space.s`.
    func inputChrome(radius: CGFloat = Radius.input, horizontal: CGFloat = Space.m, vertical: CGFloat = 9) -> some View {
        modifier(InputChrome(radius: radius, horizontal: horizontal, vertical: vertical))
    }
}
