import SwiftUI
import DeepCyclesCore

// The block editor's two custom pickers. Both are single Tab stops worked with the arrows.

/// The six block kinds as chips in a 3×2 grid: one Tab stop, ← → ↑ ↓ move, 1–6 jump.
struct KindPicker: View {
    @Binding var kind: BlockKind
    @FocusState private var focused: Bool
    private let kinds = BlockKind.allCases

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 3), spacing: Space.s) {
            ForEach(kinds) { k in
                KindChip(kind: k, selected: kind == k) { kind = k }
            }
        }
        .focusRing(focused, shape: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-3) }
        .onKeyPress(.downArrow) { move(3) }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let n = Int(press.characters), n >= 1, n <= kinds.count else { return .ignored }
            kind = kinds[n - 1]
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Block kind")
        .accessibilityValue(kind.label)
    }

    private func move(_ d: Int) -> KeyPress.Result {
        let j = (kinds.firstIndex(of: kind) ?? 0) + d
        if kinds.indices.contains(j) { kind = kinds[j] }
        return .handled
    }
}

struct KindChip: View {
    let kind: BlockKind
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(selected ? Color.white : kind.color).frame(width: 6, height: 6)
            Text(kind.shortLabel).font(TypeScale.caption.weight(.medium)).lineLimit(1)
        }
        .foregroundColor(selected ? .white : Theme.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(selected ? kind.color : kind.color.opacity(hover ? 0.22 : 0.12))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onHover { hover = $0 }
        .help(kind.label)
    }
}

/// Quick lengths for the block. One Tab stop: ← → step through the presets.
struct DurationPresets: View {
    @Binding var draft: TimeBlock
    @FocusState private var focused: Bool
    private let presets = [30, 60, 90, 120, 150, 190]

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(presets, id: \.self) { m in
                let on = draft.minutes == m
                Text("\(m)")
                    .font(TypeScale.caption.weight(on ? .semibold : .regular).monospacedDigit())
                    .foregroundColor(on ? Theme.ink : Theme.inkFaint)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(on ? Theme.paper : Color.clear)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { set(m) }
            }
            Text("min").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
        }
        .focusRing(focused, shape: Capsule())
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Length")
        .accessibilityValue("\(draft.minutes) minutes")
    }

    private func set(_ m: Int) { draft.end = draft.start.addingTimeInterval(TimeInterval(m * 60)) }

    private func step(_ d: Int) -> KeyPress.Result {
        let cur = draft.minutes
        if d > 0, let next = presets.first(where: { $0 > cur }) { set(next) }
        if d < 0, let prev = presets.last(where: { $0 < cur }) { set(prev) }
        return .handled
    }
}
