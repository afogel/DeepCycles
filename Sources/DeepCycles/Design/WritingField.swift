import SwiftUI

/// A plain multi-line field that sits on the paper like a writing line.
/// Pass `focus`/`tag` when the owning form places focus programmatically.
struct WritingField<F: Hashable>: View {
    let prompt: String
    @Binding var text: String
    var lines: ClosedRange<Int> = 1...4
    var focus: FocusState<F?>.Binding? = nil
    var tag: F? = nil
    @FocusState private var editing: Bool

    init(_ prompt: String, _ text: Binding<String>, lines: ClosedRange<Int> = 1...4, focus: FocusState<F?>.Binding, tag: F) {
        self.prompt = prompt
        self._text = text
        self.lines = lines
        self.focus = focus
        self.tag = tag
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(prompt).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink)
            field
                .lineLimit(lines)
                .textFieldStyle(.plain)
                .font(Theme.body)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.paperDeep)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(editing ? Theme.focus.opacity(0.7) : Color.clear, lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField("", text: $text, axis: .vertical).focused($editing)
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
