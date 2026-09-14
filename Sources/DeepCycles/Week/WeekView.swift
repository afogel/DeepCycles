import SwiftUI
import DeepCyclesCore

/// Seven compact day columns next to the weekly plan: the place where
/// Newport's weekly plan is written while looking at the week's calendar.
@MainActor
struct WeekView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
    @EnvironmentObject var calendar: CalendarService
    @State private var events: [String: [TimeBlock]] = [:]   // day key -> calendar events
    @State private var detailID: UUID? = nil                 // the entry whose details popover is open

    private var days: [Date] {
        let c = Calendar(identifier: .iso8601)
        guard let start = c.dateInterval(of: .weekOfYear, for: store.selectedDate)?.start else { return [] }
        return (0..<7).compactMap { c.date(byAdding: .day, value: $0, to: start) }
    }
    private let ptPerMinute: CGFloat = 0.62

    /// The grid spans the week's working hours (each day's own setting), stretched to fit anything
    /// scheduled outside them so nothing is clipped.
    private var hours: (start: Int, end: Int) {
        let c = Calendar.current
        var start = 23, end = 1
        for d in days {
            let plan = store.plan(for: d)
            start = min(start, plan.workStartHour)
            end = max(end, plan.workEndHour)
            for b in (events[DateKeys.day(d)] ?? []) + plan.blocks {
                start = min(start, c.component(.hour, from: b.start))
                if c.isDate(b.end, inSameDayAs: d) {
                    let m = c.component(.hour, from: b.end) * 60 + c.component(.minute, from: b.end)
                    end = max(end, (m + 59) / 60)
                } else {
                    end = 24
                }
            }
        }
        return (max(0, start), min(24, max(start + 1, end)))
    }
    private var startHour: Int { hours.start }
    private var endHour: Int { hours.end }
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
        .onChange(of: store.selectedDate) { loadEvents() }
        .onChange(of: calendar.authorized) { loadEvents() }
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
        let key = DateKeys.day(day)
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
                        .hoverTint(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { detailID = b.id }
                        .popover(isPresented: showingDetail(b.id), arrowEdge: .trailing) { EventDetail(block: b, day: day) }
                        .offset(x: CGFloat(p.col) * (w + 2), y: yOffset(b.start, on: day) + 1)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { store.selectedDate = Calendar.current.startOfDay(for: day); ui.tab = .day }
            .onTapGesture { store.selectedDate = Calendar.current.startOfDay(for: day) }
    }

    /// One popover at a time: open for the entry whose id is `detailID`, and closing it clears that.
    private func showingDetail(_ id: UUID) -> Binding<Bool> {
        Binding(get: { detailID == id }, set: { if !$0 && detailID == id { detailID = nil } })
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
                let deepPlanned = plan.deepMinutesPlanned
                let deepDone = plan.deepMinutesLogged
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
                        if let p = store.lastWeek { store.snapshotWeek(); store.thisWeek = p.carriedForward() }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(store.lastWeek == nil)
                    .help("Carries last week's open outcomes, habits and notes into this week, replacing what is here. ⌘Z undoes it.")
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
                        .lineLimit(2...6).font(TypeScale.body)
                        .inputChrome()
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Values this week").font(TypeScale.title).foregroundColor(Theme.ink)
                    Text("Which values need emphasis, and a habit for each. Tick them per day.")
                        .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                    ValuesTracker(days: days)
                    TextField("Mental-health practices, reminders (optional note)", text: Binding(get: { store.thisWeek.valuesPlan }, set: { store.thisWeek.valuesPlan = $0 }), axis: .vertical)
                        .lineLimit(2...5).font(TypeScale.body)
                        .inputChrome()
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Open tasks").font(TypeScale.title).foregroundColor(Theme.ink)
                        Spacer()
                        Button("All tasks") { ui.showSystems(.doc(.tasks)) }.buttonStyle(QuietButtonStyle())
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
                    Button("Strategic plans") { ui.showSystems(.doc(.career)) }.buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button("Block the selected day") { ui.tab = .day }.buttonStyle(InkButtonStyle())
                }
            }
            .padding(Space.l)
        }
    }

    private func loadEvents() {
        var map: [String: [TimeBlock]] = [:]
        for d in days {
            map[DateKeys.day(d)] = calendar.ghosts(on: d)
        }
        events = map
    }
}
