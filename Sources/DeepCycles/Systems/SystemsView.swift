import SwiftUI
import DeepCyclesCore

/// Newport's "root document": core documents, weekly planning, disciplines.
/// Everything the daily time-block plan is supposed to descend from.
@MainActor
struct SystemsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
    @FocusState private var sidebarFocused: Bool

    private var page: SystemsPage { ui.systemsPage }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 250).background(Theme.paperDeep)
            ScrollView {
                content
                    .padding(28)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .background(Theme.paper)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            group("This week") {
                item("Weekly plan & values plan", .week, sub: store.selectedWeekKey)
            }
            group("Core documents") {
                item("Root document", .root, sub: "how the system works")
                ForEach(CoreDoc.Kind.allCases, id: \.self) { k in
                    if let d = store.system.doc(k) {
                        item(d.title, .doc(k), sub: "updated " + d.updated.formatted(.relative(presentation: .named)))
                    }
                }
            }
            group("Discipline") {
                item("Disciplines & metrics", .disciplines, sub: "\(store.system.disciplines.count) tracked daily")
            }
            group("Review") {
                item("Session log", .sessions, sub: "\(store.sessionLog().count) sessions, last 30 days")
            }
            Spacer()
            overhaulNudge
        }
        .padding(14)
        // One Tab stop; ↑ ↓ change the page.
        .focusable()
        .focused($sidebarFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.downArrow) { step(1) }
        .accessibilityLabel("Systems pages")
    }

    private func step(_ d: Int) -> KeyPress.Result {
        let pages = SystemsPage.all
        let i = pages.firstIndex(of: page) ?? 0
        ui.systemsPage = pages[max(0, min(pages.count - 1, i + d))]
        return .handled
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.inkFaint)
                .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
            content()
        }
    }

    private func item(_ title: String, _ p: SystemsPage, sub: String) -> some View {
        SidebarItem(title: title, sub: sub, selected: page == p, keyboard: sidebarFocused && page == p) {
            ui.systemsPage = p
            sidebarFocused = true
        }
    }

    private struct SidebarItem: View {
        let title: String
        let sub: String
        let selected: Bool
        let keyboard: Bool
        let action: () -> Void
        @State private var hover = false
        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).foregroundColor(Theme.ink)
                Text(sub).font(TypeScale.caption).foregroundColor(Theme.inkFaint).lineLimit(1)
            }
            .padding(.horizontal, Space.s).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.paper : (hover ? Theme.paper.opacity(0.5) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .focusRing(keyboard, shape: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .contentShape(Rectangle())          // the whole row is the target, not just the text
            .onTapGesture(perform: action)
            .onHover { hover = $0 }
        }
    }

    private var overhaulNudge: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let d = store.system.nextOverhaul {
                let due = d <= Date()
                Text(due ? "Strategic plans are due for a semester overhaul." : "Next strategic overhaul \(d.formatted(date: .abbreviated, time: .omitted)).")
                    .font(Theme.small).foregroundColor(due ? Theme.tasks : Theme.inkFaint)
            }
            DatePicker("Next overhaul", selection: Binding(
                get: { store.system.nextOverhaul ?? Calendar.current.date(byAdding: .month, value: 4, to: Date())! },
                set: { store.system.nextOverhaul = $0 }
            ), displayedComponents: .date)
            .font(Theme.small)
        }
        .padding(10)
        .background(Theme.paper.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Pages

    @ViewBuilder
    private var content: some View {
        switch page {
        case .root: rootPage
        case .week: weekPage
        case .disciplines: disciplinesPage
        case .sessions: sessionsPage
        case .doc(let k): docPage(k)
        }
    }

    private var rootPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Root document").font(Theme.display(24)).foregroundColor(Theme.ink)
            Text("One place that describes your whole system, so nothing lives only in your head. Write it for yourself; it doesn't need to be polished.")
                .foregroundColor(Theme.inkFaint)
            editor(Binding(get: { store.system.root }, set: { store.system.root = $0 }), placeholder: rootTemplate, minHeight: 420)
            Text("The app's pieces map onto it: Core documents → Values, Career, Personal, Ideas, Tasks. Productivity → this week's plan (Systems), the daily time-block grid (Plan), cycles (Cycles), the shutdown ritual with full capture (Shutdown). Discipline → the disciplines list, logged every day at shutdown.")
                .font(Theme.small).foregroundColor(Theme.inkFaint)
        }
    }

    private var rootTemplate: String {
        """
        Core systems

        Core documents
        · Values: my roles, and the values by which I try to live them.
        · Career and personal strategic plans: current thoughts, experiments and plans, true to my values. Rewritten each semester, tweaked any time.
        · Ideas notebook, checked at least each semester.
        Maintenance: weekly, read Values and write a values plan (what to emphasise this week, habits to help, mental-health practices). Weekly, review the strategic plans.

        Productivity
        · Weekly plan, built from the strategic plans, calendar, task list and values plan.
        · Daily: review the weekly plan, values plan and calendar, then time-block the day.
        · Clear shutdown with a "shutdown complete" ritual, and full capture of every task.

        Discipline
        · An evolving list of hard disciplines, tracked with metric codes in the daily planner.
        """
    }

    private var weekPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(store.selectedWeekKey.suffix(2))").font(Theme.display(24)).foregroundColor(Theme.ink)
                Text(weekRange).foregroundColor(Theme.inkFaint)
                Spacer()
                Button("Copy last week") {
                    if let p = store.lastWeek { store.thisWeek = p.carriedForward() }
                }.buttonStyle(QuietButtonStyle())
            }
            Text("Built once a week from the strategic plans, calendar, task list and values plan. There is no fixed format: an intricate week gets an intricate plan; a quiet one might be a single line.")
                .foregroundColor(Theme.inkFaint)

            SectionHeading("Weekly plan")
            editor(Binding(get: { store.thisWeek.weeklyPlan }, set: { store.thisWeek.weeklyPlan = $0 }),
                   placeholder: "What am I working on this week? What must get done? Any heuristics or habits to keep in mind? How am I attacking the week?",
                   minHeight: 220)

            SectionHeading("Values plan")
            editor(Binding(get: { store.thisWeek.valuesPlan }, set: { store.thisWeek.valuesPlan = $0 }),
                   placeholder: "Which values need emphasis this week, and where have I fallen off? Habits to support them (e.g. call someone every day). Practices that keep my mind healthy.",
                   minHeight: 160)

            HStack(spacing: 10) {
                Button("Read Values") { ui.systemsPage = .doc(.values) }.buttonStyle(QuietButtonStyle())
                Button("Read Career plan") { ui.systemsPage = .doc(.career) }.buttonStyle(QuietButtonStyle())
                Button("Read Personal plan") { ui.systemsPage = .doc(.personal) }.buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Time-block today") { ui.tab = .day }.buttonStyle(InkButtonStyle())
            }
        }
    }

    private var weekRange: String {
        let c = Calendar(identifier: .iso8601)
        guard let start = c.dateInterval(of: .weekOfYear, for: store.selectedDate)?.start,
              let end = c.date(byAdding: .day, value: 6, to: start) else { return "" }
        return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private func docPage(_ kind: CoreDoc.Kind) -> some View {
        let doc = store.system.doc(kind)
        return VStack(alignment: .leading, spacing: 14) {
            Text(doc?.title ?? "").font(Theme.display(24)).foregroundColor(Theme.ink)
            Text(docHint(kind)).foregroundColor(Theme.inkFaint)
            if kind == .tasks {
                HStack {
                    Text("\(store.openTasks.count) open").font(Theme.small).foregroundColor(Theme.inkFaint)
                    Spacer()
                    if store.system.tasks.contains(where: { $0.done }) {
                        Button("Clear done") { store.system.tasks.removeAll { $0.done } }.buttonStyle(QuietButtonStyle())
                    }
                }
                TaskList(items: $store.system.tasks, placeholder: "Add a task")
                    .padding(Space.xs)
                    .background(Theme.paperDeep)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                Text("Captured items land here at shutdown. Schedule them by ticking them into a task block on the Plan page.")
                    .font(Theme.small).foregroundColor(Theme.inkFaint)
            } else {
                editor(Binding(get: { store.docText(kind) }, set: { store.setDocText(kind, $0) }), placeholder: "", minHeight: 460)
            }
        }
    }

    private func docHint(_ kind: CoreDoc.Kind) -> String {
        switch kind {
        case .values: return "The roles you play and the values by which you try to live each one. Read once a week when writing the values plan."
        case .career: return "Current thoughts, experimental systems and plans for your working life. Overhauled each semester; tweak any time. Link out to extended plans for big projects."
        case .personal: return "Same as the career plan, for life outside work: relationships, health, interests, community."
        case .ideas: return "Ideas go here so they don't nag. Reviewed at least at each semester overhaul; act on the ones that still matter."
        case .tasks: return "Every captured task lands here and is trusted to be seen. Pull from it when writing the weekly plan."
        }
    }

    private var disciplinesPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Disciplines").font(Theme.display(24)).foregroundColor(Theme.ink)
            Text("Hard rules you follow to lay the foundation for a deeper life. Each gets a short metric code; you log it at shutdown and won't want to write a zero.")
                .foregroundColor(Theme.inkFaint)
            VStack(spacing: 8) {
                ForEach($store.system.disciplines) { $d in
                    HStack(spacing: 10) {
                        TextField("DW", text: $d.code)
                            .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundColor(Theme.deep)
                            .padding(7).frame(width: 60).background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        TextField("Discipline, e.g. Deep work hours", text: $d.name)
                            .textFieldStyle(.plain).font(Theme.body)
                            .padding(7).background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        SegmentPicker(selection: $d.isNumber, options: [(value: false, label: "Did it"), (value: true, label: "Number")])
                            .frame(width: 130)
                        if d.isNumber {
                            TextField("target", text: $d.target)
                                .textFieldStyle(.plain).font(Theme.body).multilineTextAlignment(.trailing)
                                .padding(7).frame(width: 64).background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        Button { store.system.disciplines.removeAll { $0.id == d.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(Theme.inkFaint)
                        }.buttonStyle(.borderless)
                    }
                }
                Button { store.system.disciplines.append(Discipline()) } label: { Label("Add discipline", systemImage: "plus") }
                    .buttonStyle(QuietButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .panel()

            SectionHeading("Last 14 days")
            streakTable
        }
    }

    private var streakTable: some View {
        let days: [Date] = (0..<14).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: store.selectedDate) }
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Text("").frame(width: 40)
                ForEach(days, id: \.self) { d in
                    Text(d.formatted(.dateTime.day())).font(.system(size: 10)).foregroundColor(Theme.inkFaint)
                }
            }
            ForEach(store.system.disciplines) { disc in
                GridRow {
                    Text(disc.code).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(Theme.deep)
                    ForEach(days, id: \.self) { d in
                        let v = store.plan(for: d).discipline(disc.id)
                        let hit = disc.isHit(v)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(v.isEmpty ? Theme.ruleFaint : (hit ? Theme.deep : Theme.deep.opacity(0.3)))
                            .frame(width: 18, height: 18)
                            .help(v.isEmpty ? "not logged" : v)
                    }
                }
            }
        }
        .panel()
    }

    // MARK: Session log — review past sessions by day

    private var sessionsPage: some View {
        let log = store.sessionLog()
        return VStack(alignment: .leading, spacing: Space.l) {
            Text("Session log").font(TypeScale.display).foregroundColor(Theme.ink)
            Text("Every Work Cycles session from the last 30 days, newest first: pulse, targets, minutes, and the debrief takeaways. Delete from here or from the day's session list.")
                .foregroundColor(Theme.inkFaint)
            if log.isEmpty {
                Text("No sessions yet.").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }
            let totalMin = log.reduce(0) { $0 + $1.session.deepMinutes }
            if !log.isEmpty {
                Text(String(format: "%.1f h of deep work across %d sessions", Double(totalMin) / 60, log.count)).font(TypeScale.label).foregroundColor(Theme.deep)
            }
            ForEach(Array(log.enumerated()), id: \.offset) { _, e in
                SessionLogRow(date: e.date, block: e.block, session: e.session) {
                    store.plans[DateKeys.day(e.date)]?.sessions.removeAll { $0.id == e.session.id }
                }
            }
        }
    }

    private struct SessionLogRow: View {
        let date: Date
        let block: TimeBlock?
        let session: CycleSession
        let onDelete: () -> Void
        @State private var open = false
        @State private var hover = false
        @FocusState private var focused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(TypeScale.caption.monospacedDigit()).foregroundColor(Theme.inkFaint).frame(width: 70, alignment: .leading)
                    Text(session.title).font(TypeScale.label).foregroundColor(Theme.ink)
                    if let b = block { Text("\(b.start.shortTime)–\(b.end.shortTime)").font(TypeScale.caption).foregroundColor(Theme.inkFaint) }
                    Spacer()
                    Text("\(session.cyclesDone)/\(session.cycleCount) cycles · \(session.deepMinutes) min").font(TypeScale.caption.monospacedDigit()).foregroundColor(Theme.inkFaint)
                    if session.finished { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.breakC).font(.system(size: 12)) }
                    if hover {
                        Button(action: onDelete) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.inkFaint) }.buttonStyle(.plain)
                    }
                }
                SessionPulse(session: session)
                if open {
                    VStack(alignment: .leading, spacing: 4) {
                        if !session.accomplish.isEmpty { note("Aimed for", session.accomplish) }
                        if !session.gotDone.isEmpty { note("Got done", session.gotDone) }
                        if !session.wentWell.isEmpty { note("Went well", session.wentWell) }
                        if !session.boggedDown.isEmpty { note("Bogged down", session.boggedDown) }
                        if !session.takeaways.isEmpty { note("Takeaways", session.takeaways) }
                        ForEach(Array(session.cycles.enumerated()), id: \.offset) { i, c in
                            if !c.goal.isEmpty {
                                note("Cycle \(i + 1)", c.goal + (c.completed.map { " — \($0.label)" } ?? "") + (c.improvements.isEmpty ? "" : " · improve: \(c.improvements)"))
                            }
                        }
                    }
                    .padding(.top, Space.xs)
                }
            }
            .padding(Space.m)
            .background(hover || open ? Theme.paperDeep : Theme.paperDeep.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .focusRing(focused, shape: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { open.toggle() }
            .onHover { hover = $0 }
            // A Tab stop: Space or Return opens / closes the details.
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.space) { open.toggle(); return .handled }
            .onKeyPress(.return) { open.toggle(); return .handled }
        }

        private func note(_ label: String, _ text: String) -> some View {
            HStack(alignment: .top, spacing: Space.s) {
                Text(label).font(TypeScale.caption).foregroundColor(Theme.inkFaint).frame(width: 80, alignment: .leading)
                Text(text).font(TypeScale.body).foregroundColor(Theme.ink)
            }
        }
    }

    private func editor(_ text: Binding<String>, placeholder: String, minHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder).font(Theme.body).foregroundColor(Theme.inkFaint.opacity(0.7))
                    .padding(.horizontal, 14).padding(.vertical, 12).allowsHitTesting(false)
            }
            TextEditor(text: text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .frame(minHeight: minHeight)
        .background(Theme.paperDeep)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
