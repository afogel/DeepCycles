import SwiftUI

/// Seven compact day columns next to the weekly plan: the place where
/// Newport's weekly plan is written while looking at the week's calendar.
@MainActor
struct WeekView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var calendar: CalendarService
    @State private var events: [String: [TimeBlock]] = [:]   // day key -> calendar events

    private var days: [Date] {
        let c = Calendar(identifier: .iso8601)
        guard let start = c.dateInterval(of: .weekOfYear, for: store.selectedDate)?.start else { return [] }
        return (0..<7).compactMap { c.date(byAdding: .day, value: $0, to: start) }
    }
    private let startHour = 7, endHour = 20
    private let ptPerMinute: CGFloat = 0.62
    private var height: CGFloat { CGFloat((endHour - startHour) * 60) * ptPerMinute }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    HStack(alignment: .top, spacing: 6) {
                        hourLabels
                        ForEach(days, id: \.self) { d in dayColumn(d) }
                    }
                    .frame(height: height + 4)
                    totalsRow
                }
                .padding(20)
            }
            .background(Theme.paper)
            planSidebar.frame(width: 360).background(Theme.paperDeep)
        }
        .onAppear(perform: loadEvents)
        .onChange(of: store.selectedDate) { _ in loadEvents() }
        .onChange(of: calendar.authorized) { _ in loadEvents() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            Color.clear.frame(width: 30, height: 1)
            ForEach(days, id: \.self) { d in
                let isToday = Calendar.current.isDateInToday(d)
                let isSelected = Calendar.current.isDate(d, inSameDayAs: store.selectedDate)
                VStack(spacing: 1) {
                    Text(d.formatted(.dateTime.weekday(.abbreviated))).font(Theme.small).foregroundColor(Theme.inkFaint)
                    Text(d.formatted(.dateTime.day()))
                        .font(Theme.display(17)).foregroundColor(isToday ? Theme.nowLine : Theme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(isSelected ? Theme.paperDeep : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { store.selectedDate = Calendar.current.startOfDay(for: d) }
            }
        }
    }

    private var hourLabels: some View {
        Color.clear.frame(width: 30).frame(height: height)
            .overlay(alignment: .topTrailing) {
                ForEach(Array(stride(from: 0, to: endHour - startHour, by: 2)), id: \.self) { i in
                    Text(String(format: "%02d", startHour + i))
                        .font(.system(size: 10, design: .serif)).foregroundColor(Theme.inkFaint)
                        .frame(height: 12)
                        .offset(y: CGFloat(i * 60) * ptPerMinute - 6)
                }
            }
    }

    private func dayColumn(_ day: Date) -> some View {
        let plan = store.plan(for: day)
        let key = Store.key(for: day)
        let items = (events[key] ?? []).filter { e in !plan.blocks.contains { $0.eventID == e.eventID } } + plan.blocks
        let isSelected = Calendar.current.isDate(day, inSameDayAs: store.selectedDate)
        return Color.clear.frame(maxWidth: .infinity).frame(height: height)
            .background(isSelected ? Theme.paperDeep.opacity(0.7) : Theme.paperDeep.opacity(0.3))
            .overlay(alignment: .top) {
                Canvas { ctx, size in
                    for i in 0...(endHour - startHour) {
                        let y = CGFloat(i * 60) * ptPerMinute + 0.5
                        var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(p, with: .color(Theme.ruleFaint), lineWidth: 1)
                    }
                }
                .frame(height: height).allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                let placement = packOverlaps(items)
                GeometryReader { geo in
                ForEach(items) { b in
                    let p = placement[b.id] ?? LanePlacement(col: 0, cols: 1)
                    let w = (geo.size.width - 2 * CGFloat(p.cols - 1)) / CGFloat(p.cols)
                    let h = max(8, CGFloat(b.minutes) * ptPerMinute - 2)
                    HStack(spacing: 0) {
                        Rectangle().fill(b.kind.color).frame(width: 3)
                        Text(b.title).font(.system(size: 9.5, weight: .medium)).lineLimit(h > 22 ? 2 : 1)
                            .foregroundColor(b.fromCalendar ? Theme.inkFaint : Theme.ink)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                        Spacer(minLength: 0)
                    }
                    .frame(width: w, height: h, alignment: .leading)
                    .background(b.kind.color.opacity(b.fromCalendar ? 0.08 : 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .offset(x: CGFloat(p.col) * (w + 2), y: yOffset(b.start, on: day) + 1)
                }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { store.selectedDate = Calendar.current.startOfDay(for: day); store.tab = 0 }
            .onTapGesture { store.selectedDate = Calendar.current.startOfDay(for: day) }
    }

    private func yOffset(_ time: Date, on day: Date) -> CGFloat {
        let dayStart = Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: day) ?? day
        let mins = time.timeIntervalSince(dayStart) / 60
        return CGFloat(min(max(mins, 0), Double((endHour - startHour) * 60))) * ptPerMinute
    }

    private var totalsRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Color.clear.frame(width: 30, height: 1)
            ForEach(days, id: \.self) { d in
                let plan = store.plan(for: d)
                let deepPlanned = plan.blocks.filter { $0.kind == .deep }.reduce(0) { $0 + $1.minutes }
                let deepDone = plan.sessions.reduce(0) { $0 + $1.deepMinutes }
                VStack(spacing: 2) {
                    if deepPlanned > 0 || deepDone > 0 {
                        Text(String(format: "%.1fh deep", Double(max(deepPlanned, deepDone)) / 60))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundColor(Theme.deep)
                        if deepDone > 0 {
                            Text(String(format: "%.1fh done", Double(deepDone) / 60)).font(.system(size: 9.5)).foregroundColor(Theme.inkFaint)
                        }
                    } else {
                        Text("–").font(Theme.small).foregroundColor(Theme.inkFaint)
                    }
                    if plan.shutdownComplete { Image(systemName: "checkmark.seal.fill").font(.system(size: 9)).foregroundColor(Theme.breakC) }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private var planSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Week \(store.selectedWeekKey.suffix(2))").font(TypeScale.display).foregroundColor(Theme.ink)
                    Spacer()
                    Button("Copy last week") {
                        let prev = Store.weekKey(for: Calendar.current.date(byAdding: .day, value: -7, to: store.selectedDate) ?? store.selectedDate)
                        if let p = store.system.weeks[prev] {
                            var copy = p
                            copy.outcomes = p.outcomes.filter { !$0.done }.map { var t = $0; t.id = UUID(); return t }
                            copy.values = p.values.map { var t = $0; t.id = UUID(); t.done = false; return t }
                            store.thisWeek = copy
                        }
                    }.buttonStyle(QuietButtonStyle())
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Outcomes this week").font(TypeScale.title).foregroundColor(Theme.ink)
                        Spacer()
                        let w = store.thisWeek
                        if !w.outcomes.isEmpty {
                            Text("\(w.outcomes.filter { $0.done }.count) of \(w.outcomes.count)").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                        }
                    }
                    TaskList(items: Binding(get: { store.thisWeek.outcomes }, set: { store.thisWeek.outcomes = $0 }), placeholder: "Something that must get done this week")
                        .background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    Text("Pulled from the strategic plans and the task list. Schedule them into deep blocks on the Day page.")
                        .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                    TextField("How I'm attacking the week (optional note)", text: Binding(get: { store.thisWeek.weeklyPlan }, set: { store.thisWeek.weeklyPlan = $0 }), axis: .vertical)
                        .lineLimit(2...6).textFieldStyle(.plain).font(TypeScale.body)
                        .padding(Space.s).background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Values this week").font(TypeScale.title).foregroundColor(Theme.ink)
                    Text("Which values need emphasis, and a habit for each. Tick them per day.")
                        .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                    ValuesTracker(days: days)
                    TextField("Mental-health practices, reminders (optional note)", text: Binding(get: { store.thisWeek.valuesPlan }, set: { store.thisWeek.valuesPlan = $0 }), axis: .vertical)
                        .lineLimit(2...5).textFieldStyle(.plain).font(TypeScale.body)
                        .padding(Space.s).background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Open tasks").font(TypeScale.title).foregroundColor(Theme.ink)
                        Spacer()
                        Button("All tasks") { store.systemsPage = "tasks"; store.tab = 2 }.buttonStyle(QuietButtonStyle())
                    }
                    let open = store.openTasks
                    if open.isEmpty {
                        Text("Nothing captured yet.").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                    } else {
                        ForEach(open.prefix(8)) { t in
                            HStack(spacing: Space.s) {
                                Circle().stroke(Theme.inkFaint, lineWidth: 1).frame(width: 12, height: 12)
                                Text(t.text).font(TypeScale.body).foregroundColor(Theme.ink).lineLimit(1)
                                Spacer()
                                Button("↑ week") {
                                    var w = store.thisWeek; w.outcomes.append(t); store.thisWeek = w
                                    store.system.tasks.removeAll { $0.id == t.id }
                                }.buttonStyle(.plain).font(TypeScale.caption).foregroundColor(Theme.deep).help("Promote to this week's outcomes")
                            }
                        }
                        if open.count > 8 { Text("+\(open.count - 8) more").font(TypeScale.caption).foregroundColor(Theme.inkFaint) }
                    }
                }

                HStack {
                    Button("Strategic plans") { store.systemsPage = "career"; store.tab = 2 }.buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button("Block the selected day") { store.tab = 0 }.buttonStyle(InkButtonStyle())
                }
            }
            .padding(Space.l)
        }
    }

    private func weekEditor(_ text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 13)).lineSpacing(3)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: minHeight)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func loadEvents() {
        var map: [String: [TimeBlock]] = [:]
        for d in days {
            map[Store.key(for: d)] = calendar.ghosts(on: d)
        }
        events = map
    }
}


/// Values-plan habits with one tick per day of the week.
@MainActor
struct ValuesTracker: View {
    let days: [Date]
    @EnvironmentObject var store: Store

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
    @State private var newValue = ""
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
