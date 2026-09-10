import SwiftUI
import DeepCyclesCore

/// Values-plan habits with one tick per day of the week.
@MainActor
struct ValuesTracker: View {
    let days: [Date]
    @EnvironmentObject var store: Store
    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.thisWeek.values) { v in
                HStack(spacing: Space.s) {
                    TextField("", text: Binding(
                        get: { v.text },
                        set: { new in var w = store.thisWeek; if let i = w.values.firstIndex(where: { $0.id == v.id }) { w.values[i].text = new; store.thisWeek = w } }
                    ))
                    .textFieldStyle(.plain).font(TypeScale.body).foregroundColor(Theme.ink)
                    DayDots(valueID: v.id, days: days)
                    Button { var w = store.thisWeek; w.values.removeAll { $0.id == v.id }; store.thisWeek = w } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.inkFaint)
                    }.buttonStyle(.plain)
                }
                .padding(.vertical, 5).padding(.horizontal, Space.s)
            }
            HStack(spacing: Space.s) {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.inkFaint).frame(width: 16)
                TextField("Value or habit, e.g. call one friend", text: $newValue)
                    .textFieldStyle(.plain).font(TypeScale.body)
                    .onSubmit {
                        let t = newValue.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        var w = store.thisWeek; w.values.append(TaskItem(text: t)); store.thisWeek = w
                        newValue = ""
                    }
            }
            .padding(.vertical, 5).padding(.horizontal, Space.s)
        }
        .background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
    }
}

/// One habit's seven day-dots. A Tab stop: ← → pick the day, Space ticks it; click works too.
@MainActor
private struct DayDots: View {
    let valueID: UUID
    let days: [Date]
    @EnvironmentObject var store: Store
    @FocusState private var focused: Bool
    @State private var cursor: Int = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let on = store.valueDone(valueID, on: d)
                let future = d > Date()
                Circle()
                    .fill(on ? Theme.breakC : Theme.ruleFaint)
                    .frame(width: 11, height: 11)
                    .opacity(future ? 0.4 : 1)
                    .overlay(Circle().stroke(Theme.focus, lineWidth: 1.5).opacity(focused && i == cursor ? 1 : 0))
                    .onTapGesture { if !future { store.setValueDone(valueID, on: d, !on) } }
                    .help(d.formatted(.dateTime.weekday(.abbreviated)))
            }
        }
        .padding(.horizontal, 3).padding(.vertical, 2)
        .focusRing(focused, shape: Capsule())
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { cursor = days.lastIndex(where: { $0 <= Date() }) ?? 0 }
        .onKeyPress(.leftArrow) { cursor = max(0, cursor - 1); return .handled }
        .onKeyPress(.rightArrow) { cursor = min(days.count - 1, cursor + 1); return .handled }
        .onKeyPress(.space) { tick() }
        .onKeyPress(.return) { tick() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Days ticked")
    }

    private func tick() -> KeyPress.Result {
        guard days.indices.contains(cursor), days[cursor] <= Date() else { return .ignored }
        store.setValueDone(valueID, on: days[cursor], !store.valueDone(valueID, on: days[cursor]))
        return .handled
    }
}
