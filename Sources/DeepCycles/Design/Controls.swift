import SwiftUI
import DeepCyclesCore

// Keyboard-first controls. Everything here is a Tab stop whatever the system's "Keyboard
// navigation" setting says, shows the same focus ring (View.focusRing in Theme.swift), and is
// worked with Space / Return / arrows / digits. AppKit-backed controls (text fields, date
// pickers, menus) keep their native behaviour. Buttons are in Buttons.swift.

// MARK: - Switch

/// A switch that is always a Tab stop; Space or Return flips it.
struct KeySwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { KeySwitch(configuration: configuration) }
}

private struct KeySwitch: View {
    let configuration: ToggleStyleConfiguration
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.deep : Theme.rule)
                Circle().fill(Color.white).frame(width: 16, height: 16).padding(2)
            }
            .frame(width: 34, height: 20)
            .focusRing(focused, shape: Capsule())
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { configuration.isOn.toggle(); return .handled }
        .onKeyPress(.return) { configuration.isOn.toggle(); return .handled }
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

// MARK: - Segmented picker

/// Segmented control with keyboard: ← → move, 1–9 jump. One Tab stop.
struct SegmentPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]
    @FocusState private var focused: Bool

    init(selection: Binding<T>, options: [(value: T, label: String)]) {
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { opt in
                let on = opt.value == selection
                Text(opt.label)
                    .font(.system(size: 12, weight: on ? .semibold : .medium))
                    .foregroundColor(on ? Theme.ink : Theme.inkFaint)
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(on ? Theme.paper : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = opt.value }
            }
        }
        .padding(2)
        .background(Theme.paperDeep)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .focusRing(focused, shape: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let n = Int(press.characters), n >= 1, n <= options.count else { return .ignored }
            selection = options[n - 1].value
            return .handled
        }
    }

    private func step(_ d: Int) -> KeyPress.Result {
        guard !options.isEmpty else { return .ignored }
        let i = options.firstIndex { $0.value == selection } ?? 0
        selection = options[max(0, min(options.count - 1, i + d))].value
        return .handled
    }
}

// MARK: - Stepper

/// Integer stepper that is a Tab stop: ← ↓ decrease, → ↑ increase; − / + are clickable.
struct ValueStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let label: (Int) -> String
    @FocusState private var focused: Bool

    init(_ value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1, label: @escaping (Int) -> String) {
        self._value = value
        self.range = range
        self.step = step
        self.label = label
    }

    var body: some View {
        HStack(spacing: Space.s) {
            Text(label(value)).font(Theme.body).foregroundColor(Theme.ink).monospacedDigit()
            HStack(spacing: 0) {
                arrow("minus", -1)
                Rectangle().fill(Theme.rule).frame(width: 1, height: 12)
                arrow("plus", 1)
            }
            .background(Theme.paperDeep)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.vertical, 2)
        .focusRing(focused, shape: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { bump(1) }
        .onKeyPress(.rightArrow) { bump(1) }
        .onKeyPress(.downArrow) { bump(-1) }
        .onKeyPress(.leftArrow) { bump(-1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(value))
    }

    private func arrow(_ symbol: String, _ d: Int) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(Theme.ink)
            .frame(width: 20, height: 18)
            .contentShape(Rectangle())
            .onTapGesture { _ = bump(d) }
    }

    private func bump(_ d: Int) -> KeyPress.Result {
        value = max(range.lowerBound, min(range.upperBound, value + d * step))
        return .handled
    }
}

// MARK: - Rating and target

/// Five dots, 1–5. Keys: 1–5 set, ← → nudge.
struct Rating: View {
    let label: String
    @Binding var value: Int
    @FocusState private var focused: Bool
    init(_ label: String, _ value: Binding<Int>) { self.label = label; self._value = value }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink)
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= value ? Theme.deep : Theme.deep.opacity(0.18))
                    .frame(width: 14, height: 14)
                    .padding(2)
                    .contentShape(Rectangle())
                    .onTapGesture { value = i }
            }
        }
        .padding(.vertical, 2)
        .focusRing(focused, shape: Capsule())
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(characters: .decimalDigits) { press in
            guard let n = Int(press.characters), (1...5).contains(n) else { return .ignored }
            value = n
            return .handled
        }
        .onKeyPress(.leftArrow) { value = max(1, value - 1); return .handled }
        .onKeyPress(.rightArrow) { value = min(5, value + 1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) of 5")
    }
}

/// "Did you hit the target?" Yes / Half / No. Keys: Y H N, 1 2 3, ← →.
struct TargetPicker: View {
    @Binding var value: TargetOutcome?
    @FocusState private var focused: Bool
    private let options = TargetOutcome.allCases
    init(_ value: Binding<TargetOutcome?>) { self._value = value }

    var body: some View {
        HStack(spacing: 12) {
            Text("Completed the cycle's target?").font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink)
            ForEach(options) { v in
                Text(v.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(value == v ? .white : Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(value == v ? Theme.deep : Theme.paperDeep)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { value = v }
            }
            Text("Y · H · N").font(TypeScale.caption).foregroundColor(Theme.inkFaint).opacity(focused ? 1 : 0)
        }
        .padding(.vertical, 2)
        .focusRing(focused, shape: Capsule())
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(characters: CharacterSet(charactersIn: "yhnYHN123")) { press in
            switch press.characters.lowercased() {
            case "y", "1": value = .yes
            case "h", "2": value = .half
            case "n", "3": value = .no
            default: return .ignored
            }
            return .handled
        }
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Completed the cycle's target?")
        .accessibilityValue(value?.label ?? "Not answered")
    }

    private func step(_ d: Int) -> KeyPress.Result {
        let i = value.flatMap { options.firstIndex(of: $0) } ?? (d > 0 ? -1 : options.count)
        value = options[max(0, min(options.count - 1, i + d))]
        return .handled
    }
}

// MARK: - Check row

/// A checkbox row used by the pickers. Space or Return toggles; the whole row is clickable.
struct CheckRow: View {
    let text: String
    let on: Bool
    var tint: Color = Theme.deep
    let toggle: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: on ? "checkmark.square.fill" : "square").foregroundColor(on ? tint : Theme.inkFaint)
            Text(text).font(TypeScale.body).foregroundColor(Theme.ink).lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .focusRing(focused, shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { toggle(); return .handled }
        .onKeyPress(.return) { toggle(); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? "Checked" : "Unchecked")
    }
}

/// The tick in a task row: a Tab stop of its own, Space toggles.
struct TaskCheck: View {
    @Binding var done: Bool
    @FocusState private var focused: Bool

    var body: some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 14))
            .foregroundColor(done ? Theme.breakC : Theme.inkFaint)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onTapGesture { done.toggle() }
            .focusRing(focused, shape: Circle())
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.space) { done.toggle(); return .handled }
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(done ? "Done" : "Open")
    }
}
