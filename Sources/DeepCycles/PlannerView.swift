import SwiftUI
import EventKit

@MainActor
struct PlannerView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var engine: CycleEngine

    @State private var calendarItems: [TimeBlock] = []
    @State private var draft = TimeBlock()
    @State private var editingID: UUID? = nil
    @State private var syncStatus: String = ""
    @State private var showSettings = false
    @FocusState private var focus: Field?
    @State private var captureFocus = 0
    @State private var draftPlaced = false      // the new-block slot is being configured, so show it on the grid
    enum Field { case title, collection }

    var body: some View {
        HStack(spacing: 0) {
            DayGrid(
                    startHour: store.today.workStartHour,
                    endHour: store.today.workEndHour,
                    date: store.selectedDate,
                    ghosts: calendarItems.filter { g in !store.today.blocks.contains { $0.eventID == g.eventID } },
                    blocks: store.today.blocks,
                    sessions: store.today.sessions,
                    selectedID: editingID,
                    draft: editingID != nil || draftPlaced ? draft : nil,
                    editingID: editingID,
                    onTapBlock: { select($0) },
                    onTapGhost: { adopt($0) },
                    onCreate: { start, end in newDraft(start: start, end: end, placed: true); focus = .title },
                    onMoveResize: { id, start, end in moveResize(id, start: start, end: end) },
                    onDelete: { deleteEditing() }
                )
                inspector.frame(width: 320)
        }
        .onAppear { reloadCalendar(); newDraft(start: defaultStart(), end: nil) }
        .onChange(of: store.selectedDate) { _ in reloadCalendar(); editingID = nil; newDraft(start: defaultStart(), end: nil) }
        .onChange(of: draft) { _ in if editingID == nil { draftPlaced = true } }
        .onChange(of: calendar.authorized) { _ in reloadCalendar() }
        .onChange(of: store.pending) { cmd in
            guard let cmd else { return }
            switch cmd {
            case .newBlock: editingID = nil; newDraft(start: defaultStart(), end: nil); draftPlaced = true; focus = .title
            case .deleteBlock: deleteEditing()
            case .focusCollection: captureFocus += 1
            case .importEvents: adoptAll()
            case .pushPlan: syncAll()
            case .reconcileCalendar: reconcile()
            default: return
            }
            store.pending = nil
        }
    }

    // MARK: Inspector (the sidebar is an inspector for the selected block, not a form)

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    thisWeek
                    blockEditor
                    collection
                }
                .padding(Space.xl)
            }
            footer
        }
        .background(Theme.paperDeep)
    }

    private var thisWeek: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            let w = store.thisWeek
            if w.outcomes.isEmpty && w.values.isEmpty {
                Button("Write this week's plan") { store.tab = 1 }.buttonStyle(QuietButtonStyle())
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week").font(TypeScale.title).foregroundColor(Theme.ink)
                    Spacer()
                    Button("Open") { store.tab = 1 }.buttonStyle(QuietButtonStyle())
                }
                ForEach(w.outcomes.filter { !$0.done }.prefix(6)) { t in
                    HStack(spacing: Space.s) {
                        Button {
                            var wk = store.thisWeek
                            if let i = wk.outcomes.firstIndex(where: { $0.id == t.id }) { wk.outcomes[i].done = true; store.thisWeek = wk }
                        } label: { Image(systemName: "circle").font(.system(size: 13)).foregroundColor(Theme.inkFaint) }.buttonStyle(.plain)
                        Text(t.text).font(TypeScale.body).foregroundColor(Theme.ink).lineLimit(1)
                    }
                }
                if !w.values.isEmpty {
                    let today = store.selectedDate
                    HStack(spacing: Space.s) {
                        ForEach(w.values) { v in
                            let on = store.valueDone(v.id, on: today)
                            Button { store.setValueDone(v.id, on: today, !on) } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(on ? Theme.breakC : Theme.ruleFaint).frame(width: 8, height: 8)
                                    Text(v.text).font(TypeScale.caption).foregroundColor(on ? Theme.inkFaint : Theme.ink).lineLimit(1)
                                }
                                .padding(.horizontal, Space.s).padding(.vertical, 3)
                                .background(Theme.paper).clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var blockEditor: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(editingID == nil ? "New block" : "Block").font(TypeScale.title).foregroundColor(Theme.ink)
                Spacer()
                if editingID != nil {
                    Button("Delete  ⌫") { deleteEditing() }.buttonStyle(QuietButtonStyle())
                }
            }

            TextField("What will you do?", text: $draft.title)
                .focused($focus, equals: .title)
                .textFieldStyle(.plain).font(.system(size: 15, weight: .medium))
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .stroke(focus == .title ? Theme.deep : Color.clear, lineWidth: 1.5))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 3), spacing: Space.s) {
                ForEach(BlockKind.allCases) { k in
                    KindChip(kind: k, selected: draft.kind == k) { draft.kind = k }
                }
            }

            HStack(spacing: Space.s) {
                DatePicker("", selection: $draft.start, displayedComponents: .hourAndMinute).labelsHidden()
                Text("to").font(TypeScale.body).foregroundColor(Theme.inkFaint)
                Text(draft.end.shortTime).font(TypeScale.body.monospacedDigit()).foregroundColor(Theme.ink)
                Text("· \(draft.minutes) min").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                Spacer()
            }
            HStack(spacing: Space.xs) {
                ForEach([30, 60, 90, 120, 150, 190], id: \.self) { m in
                    Button("\(m)") { draft.end = draft.start.addingTimeInterval(TimeInterval(m * 60)) }
                        .buttonStyle(PresetStyle(selected: draft.minutes == m))
                        .fixedSize()
                }
                Text("min").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }
            if draft.kind == .deep {
                let fit = CycleSession.fitting(block: draft)
                Text("\(fit.cycleCount) cycle\(fit.cycleCount == 1 ? "" : "s") of \(fit.cycleMinutes) min")
                    .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }

            if draft.kind == .tasks {
                taskPicker
            } else if draft.kind == .deep, !store.thisWeek.outcomes.filter({ !$0.done }).isEmpty {
                outcomePicker
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.plain).font(TypeScale.body)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .background(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            } else {
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.plain).font(TypeScale.body)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .background(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            }

            Button(editingID == nil ? "Add block" : "Save") { commitDraft() }
                .buttonStyle(InkButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)

            if let id = editingID, draft.kind == .deep {
                if let s = store.session(forBlock: id) {
                    Button("Cycles: \(s.cyclesDone) of \(s.cycleCount) done, \(s.deepMinutes) min") {
                        engine.attach(sessionID: s.id, dateKey: store.selectedKey); store.focusMode = true
                    }.buttonStyle(QuietButtonStyle())
                } else {
                    Button("Run work cycles on this block") { startCycles(on: draft) }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    /// For a task block: tick the open tasks that belong in it. Batching small
    /// things into one block is the whole point of a task block.
    private var taskPicker: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            let open = store.openTasks
            if open.isEmpty {
                Text("No open tasks. Capture some in Collection, or add them in Systems → Tasks.")
                    .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            } else {
                Text("Tasks in this block").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                ForEach(open) { t in
                    let on = draft.taskIDs.contains(t.id)
                    Button {
                        if on { draft.taskIDs.removeAll { $0 == t.id } } else { draft.taskIDs.append(t.id) }
                    } label: {
                        HStack(spacing: Space.s) {
                            Image(systemName: on ? "checkmark.square.fill" : "square").foregroundColor(on ? Theme.tasks : Theme.inkFaint)
                            Text(t.text).font(TypeScale.body).foregroundColor(Theme.ink).lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, Space.xs)
    }

    /// For a deep block: which of this week's outcomes it advances.
    private var outcomePicker: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Advances this week's outcome").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            ForEach(store.thisWeek.outcomes.filter { !$0.done }) { t in
                let on = draft.taskIDs.contains(t.id)
                Button {
                    if on { draft.taskIDs.removeAll { $0 == t.id } } else { draft.taskIDs.append(t.id) }
                } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: on ? "checkmark.square.fill" : "square").foregroundColor(on ? Theme.deep : Theme.inkFaint)
                        Text(t.text).font(TypeScale.body).foregroundColor(Theme.ink).lineLimit(1)
                        Spacer()
                    }
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Collection").font(TypeScale.title).foregroundColor(Theme.ink)
                Spacer()
                if !store.today.captured.isEmpty {
                    Button("Move to tasks") { store.processCollection() }.buttonStyle(QuietButtonStyle())
                }
            }
            TaskList(items: $store.today.captured, placeholder: "Capture a thought  ⌘K", focusRequest: captureFocus)
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            Text("Captured here so you can stay in the block. Processed into Tasks at shutdown.")
                .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
        }
    }

    private var footer: some View {
        HStack(spacing: Space.m) {
            let planned = store.today.blocks.reduce(0) { $0 + $1.minutes }
            let deep = store.today.blocks.filter { $0.kind == .deep }.reduce(0) { $0 + $1.minutes }
            if planned > 0 {
                Text("\(hm(planned)) blocked · \(hm(deep)) deep")
                    .font(TypeScale.caption.monospacedDigit()).foregroundColor(Theme.inkFaint).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            if !syncStatus.isEmpty {
                Text(syncStatus).font(TypeScale.caption).foregroundColor(Theme.inkFaint).lineLimit(1)
            }
            Button { showSettings.toggle() } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "gearshape").foregroundColor(Theme.inkFaint)
                    Circle().fill(syncDotColor).frame(width: 6, height: 6).offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.borderless)
            .help(syncHelp)
            .popover(isPresented: $showSettings) { settings }
            Button(store.today.shutdownComplete ? "Day closed" : "End day") { store.showShutdown = true }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }

    private func hm(_ m: Int) -> String { m % 60 == 0 ? "\(m / 60)h" : (m < 60 ? "\(m)m" : "\(m / 60)h \(m % 60)m") }
    private var syncDotColor: Color {
        !calendar.authorized ? Theme.nowLine : (calendar.autoSync ? Theme.breakC : Theme.inkFaint.opacity(0.5))
    }
    private var syncHelp: String {
        !calendar.authorized ? "No calendar access" :
        (calendar.autoSync ? "Syncing to \(calendar.targetCalendar?.title ?? "calendar")" : "Calendar sync is off")
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Day settings").font(TypeScale.title).foregroundColor(Theme.ink)
            HStack {
                Stepper("From \(store.today.workStartHour):00", value: $store.today.workStartHour, in: 0...22)
                Stepper("to \(store.today.workEndHour):00", value: $store.today.workEndHour, in: 1...23)
            }
            .font(TypeScale.body)
            .onChange(of: store.today.workStartHour) { v in if store.today.workEndHour <= v { store.today.workEndHour = v + 1 } }
            .onChange(of: store.today.workEndHour) { v in if store.today.workStartHour >= v { store.today.workStartHour = v - 1 } }

            Divider()
            Text("Calendar").font(TypeScale.label).foregroundColor(Theme.ink)
            if calendar.authorized {
                Toggle("Sync blocks to the calendar automatically", isOn: $calendar.autoSync).font(TypeScale.body)
                Picker("Write to", selection: $calendar.targetCalendarID) {
                    ForEach(calendar.calendars.filter { $0.allowsContentModifications }, id: \.calendarIdentifier) { c in
                        Text(c.title).tag(c.calendarIdentifier)
                    }
                }.font(TypeScale.body)
                if !calendar.calendars.contains(where: { $0.title == "Time Blocks" }) {
                    Button("Create a “Time Blocks” calendar") { calendar.createTimeBlocksCalendar() }.buttonStyle(QuietButtonStyle())
                }
                HStack {
                    Button("Sync now") { syncAll() }.buttonStyle(QuietButtonStyle())
                    Button("Adopt all events as blocks") { adoptAll() }.buttonStyle(QuietButtonStyle())
                }
                if let on = calendar.createdOn { Text("“Time Blocks” created on \(on).").font(TypeScale.caption).foregroundColor(Theme.breakC) }
                if let err = calendar.lastError {
                    Text(err).font(TypeScale.caption).foregroundColor(Theme.nowLine).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(calendar.lastError ?? "Requesting calendar access…").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                Button("Retry access") { Task { await calendar.requestAccess() } }.buttonStyle(QuietButtonStyle())
            }
        }
        .padding(Space.l).frame(width: 380).background(Theme.paper)
    }

    // MARK: Actions

    private func defaultStart() -> Date {
        let now = Date()
        if Calendar.current.isDate(now, inSameDayAs: store.selectedDate),
           Calendar.current.component(.hour, from: now) < store.today.workEndHour {
            return max(now.rounded(toMinutes: 15), store.time(hour: store.today.workStartHour))
        }
        return store.time(hour: store.today.workStartHour)
    }

    private func newDraft(start: Date, end: Date?, placed: Bool = false) {
        var b = TimeBlock()
        b.start = start
        b.end = end ?? start.addingTimeInterval(60 * 60)
        b.kind = draft.kind
        editingID = nil
        draft = b
        DispatchQueue.main.async { draftPlaced = placed }
    }

    private func select(_ block: TimeBlock) {
        focus = nil            // so ⌫ deletes the block, not the text in a field
        editingID = block.id
        draft = block
    }

    /// Turn a ghosted calendar event into a real block (a meeting) in one click.
    private func adopt(_ ghost: TimeBlock) {
        guard !store.today.blocks.contains(where: { $0.eventID == ghost.eventID }) else { return }
        store.snapshot()
        store.today.blocks.append(ghost)
        store.today.blocks.sort { $0.start < $1.start }
        select(ghost)
    }

    private func adoptAll() {
        store.snapshot()
        for g in calendarItems where !store.today.blocks.contains(where: { $0.eventID == g.eventID }) {
            if BlockKind.allCases.contains(where: { g.title.hasPrefix($0.emoji) }) { continue }
            store.today.blocks.append(g)
        }
        store.today.blocks.sort { $0.start < $1.start }
    }

    private func commitDraft() {
        var b = draft
        b.title = b.title.trimmingCharacters(in: .whitespaces)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: b.start)
        b.start = store.time(hour: comps.hour ?? 9, minute: comps.minute ?? 0)
        b.end = b.start.addingTimeInterval(TimeInterval(draft.minutes * 60))
        store.snapshot()
        if let id = editingID, let i = store.today.blocks.firstIndex(where: { $0.id == id }) {
            store.today.blocks[i] = b
        } else {
            store.today.blocks.append(b)
        }
        store.today.blocks.sort { $0.start < $1.start }
        sync(b)
        editingID = nil
        newDraft(start: b.end, end: nil)
    }

    private func deleteEditing() {
        guard let id = editingID, let i = store.today.blocks.firstIndex(where: { $0.id == id }) else { return }
        let b = store.today.blocks[i]
        store.snapshot()
        if let eid = b.eventID, !b.fromCalendar { calendar.remove(eventID: eid) }
        store.today.blocks.remove(at: i)
        editingID = nil
        newDraft(start: b.start, end: nil)
        reloadCalendar()
    }

    private func reloadCalendar() {
        calendarItems = calendar.ghosts(on: store.selectedDate)
    }

    private func moveResize(_ id: UUID, start: Date, end: Date) {
        guard let i = store.today.blocks.firstIndex(where: { $0.id == id }) else { return }
        store.snapshot()
        store.today.blocks[i].start = start
        store.today.blocks[i].end = end
        let b = store.today.blocks[i]
        store.today.blocks.sort { $0.start < $1.start }
        if editingID == id { draft = b }
        if b.fromCalendar { return }   // we don't move other people's meetings
        sync(b)
    }

    private func sync(_ block: TimeBlock) {
        guard calendar.autoSync, calendar.authorized, !block.fromCalendar else { return }
        do {
            let id = try calendar.push(block)
            if let i = store.today.blocks.firstIndex(where: { $0.id == block.id }) { store.today.blocks[i].eventID = id }
            flash("Synced")
        } catch { flash("Sync failed") ; calendar.lastError = error.localizedDescription }
    }

    private func syncAll() {
        var n = 0
        for i in store.today.blocks.indices where !store.today.blocks[i].fromCalendar {
            if let id = try? calendar.push(store.today.blocks[i]) { store.today.blocks[i].eventID = id; n += 1 }
        }
        flash("Synced \(n) block\(n == 1 ? "" : "s")")
        reloadCalendar()
    }

    /// After undo/redo: the calendar must match the restored day.
    private func reconcile() {
        guard calendar.autoSync, calendar.authorized else { reloadCalendar(); return }
        let ours = Set(store.today.blocks.compactMap { $0.fromCalendar ? nil : $0.eventID })
        // events we created earlier that no longer have a block
        for e in calendar.events(on: store.selectedDate) where BlockKind.allCases.contains(where: { e.title?.hasPrefix($0.emoji) ?? false }) {
            if !ours.contains(e.eventIdentifier) { calendar.remove(eventID: e.eventIdentifier) }
        }
        for i in store.today.blocks.indices where !store.today.blocks[i].fromCalendar {
            if let id = try? calendar.push(store.today.blocks[i]) { store.today.blocks[i].eventID = id }
        }
        if let id = editingID, let b = store.today.blocks.first(where: { $0.id == id }) { draft = b } else { editingID = nil }
        reloadCalendar()
        flash("Undone")
    }

    private func flash(_ text: String) {
        syncStatus = text
        Task { try? await Task.sleep(nanoseconds: 2_500_000_000); syncStatus = "" }
    }

    private func startCycles(on block: TimeBlock) {
        let s = CycleSession.fitting(block: block)
        store.today.sessions.append(s)
        engine.attach(sessionID: s.id, dateKey: store.selectedKey)
        store.focusMode = true
    }
}

extension BlockKind {
    var shortLabel: String {
        switch self {
        case .deep: return "Deep"
        case .shallow: return "Shallow"
        case .meeting: return "Meeting"
        case .tasks: return "Tasks"
        case .breakTime: return "Break"
        case .overflow: return "Overflow"
        }
    }
}

// MARK: - Controls with states

struct KindChip: View {
    let kind: BlockKind
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(selected ? Color.white : kind.color).frame(width: 6, height: 6)
                Text(kind.shortLabel).font(TypeScale.caption.weight(.medium)).lineLimit(1)
            }
            .foregroundColor(selected ? .white : Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? kind.color : kind.color.opacity(hover ? 0.22 : 0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(kind.label)
    }
}

struct PresetStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.caption.weight(selected ? .semibold : .regular).monospacedDigit())
            .foregroundColor(selected ? Theme.ink : Theme.inkFaint)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(selected ? Theme.paper : (configuration.isPressed ? Theme.paper.opacity(0.5) : Color.clear))
            .clipShape(Capsule())
    }
}

// MARK: - Day grid: one timeline, ghosts, drag to create, move, resize, side-by-side conflicts

struct DayGrid: View {
    let startHour: Int
    let endHour: Int
    let date: Date
    let ghosts: [TimeBlock]
    let blocks: [TimeBlock]
    let sessions: [CycleSession]
    let selectedID: UUID?
    let draft: TimeBlock?
    let editingID: UUID?
    let onTapBlock: (TimeBlock) -> Void
    let onTapGhost: (TimeBlock) -> Void
    let onCreate: (Date, Date) -> Void
    let onMoveResize: (UUID, Date, Date) -> Void
    let onDelete: () -> Void

    @State private var dragRange: (start: Date, end: Date)? = nil
    @State private var adjust: (id: UUID, dStart: Int, dEnd: Int)? = nil   // live move/resize, in minutes

    private let ptPerMinute: CGFloat = 1.5
    private let gap: CGFloat = 3
    private var totalMinutes: Int { max(60, (endHour - startHour) * 60) }
    private var height: CGFloat { CGFloat(totalMinutes) * ptPerMinute }
    private var dayStart: Date { Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: date) ?? date }
    private var dayEnd: Date { dayStart.addingTimeInterval(TimeInterval(totalMinutes * 60)) }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: Space.m) {
                hourLabels
                timeline
            }
            .frame(height: height + Space.m)
            .padding(Space.xl)
        }
        .background(Theme.paper)
    }

    private var base: some View { Color.clear.frame(maxWidth: .infinity).frame(height: height) }

    private var hourLabels: some View {
        base.frame(width: 40)
            .overlay(alignment: .topTrailing) {
                ForEach(0..<(totalMinutes / 60), id: \.self) { i in
                    Text(String(format: "%02d", startHour + i))
                        .font(.system(size: 12, weight: .medium, design: .serif))
                        .foregroundColor(Theme.inkFaint)
                        .frame(height: 14)
                        .offset(y: CGFloat(i * 60) * ptPerMinute - 7)
                }
            }
    }

    /// Blocks with any in-progress move/resize applied, and the inspector's
    /// unsaved edits shown in place of the block being edited.
    private var liveBlocks: [TimeBlock] {
        blocks.map { b in
            if let e = editingID, e == b.id, let d = draft, adjust == nil {
                var m = b; m.title = d.title; m.kind = d.kind; m.start = d.start; m.end = d.end; return m
            }
            guard let a = adjust, a.id == b.id else { return b }
            var m = b
            m.start = b.start.addingTimeInterval(TimeInterval(a.dStart * 60))
            m.end = b.end.addingTimeInterval(TimeInterval(a.dEnd * 60))
            return m
        }
    }

    private var timeline: some View {
        let live = liveBlocks
        let placement = packOverlaps(ghosts + live)
        return base
            .overlay(alignment: .top) { rules }
            .overlay(alignment: .top) {
                if blocks.isEmpty && draft == nil && dragRange == nil {
                    Text("Drag across the hours you want to block, or press ⌘N.")
                        .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                        .padding(.top, Space.l)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .local)
                    .onChanged { g in
                        let a = time(at: g.startLocation.y), b = time(at: g.location.y)
                        let lo = min(a, b), hi = max(a, b)
                        dragRange = (lo, max(hi, lo.addingTimeInterval(15 * 60)))
                    }
                    .onEnded { _ in
                        if let r = dragRange { onCreate(r.start, r.end) }
                        dragRange = nil
                    }
            )
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    ForEach(ghosts) { g in
                        let p = placement[g.id] ?? LanePlacement(col: 0, cols: 1)
                        GhostCard(block: g)
                            .frame(width: colWidth(geo.size.width, p), height: cardHeight(g))
                            .offset(x: colX(geo.size.width, p), y: yOffset(g.start) + 1)
                            .onTapGesture { onTapGhost(g) }
                    }
                    ForEach(live) { item in
                        let p = placement[item.id] ?? LanePlacement(col: 0, cols: 1)
                        BlockCard(block: item, selected: item.id == selectedID, session: sessions.last { $0.blockID == item.id })
                            .frame(width: colWidth(geo.size.width, p), height: cardHeight(item))
                            .overlay(alignment: .bottom) { resizeHandle(for: item) }
                            .offset(x: colX(geo.size.width, p), y: yOffset(item.start) + 1)
                            .onTapGesture { onTapBlock(item) }
                            .gesture(moveGesture(for: item))
                            .zIndex(adjust?.id == item.id ? 2 : 1)
                    }
                }
            }
            .overlay(alignment: .top) {
                if let r = dragRange {
                    preview(title: nil, kind: .deep, start: r.start, end: r.end)
                } else if let d = draft, editingID == nil {
                    preview(title: d.title, kind: d.kind, start: d.start, end: d.end)
                }
            }
            .overlay(alignment: .top) { nowLine }
            .clipped()
            .onDeleteCommand { if selectedID != nil { onDelete() } }
    }

    // MARK: Move & resize

    private func moveGesture(for item: TimeBlock) -> some Gesture {
        let original = blocks.first { $0.id == item.id } ?? item
        return DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { g in
                var d = snap(g.translation.height)
                // keep the block inside the working day
                let lo = Int(dayStart.timeIntervalSince(original.start) / 60)
                let hi = Int(dayEnd.timeIntervalSince(original.end) / 60)
                d = max(lo, min(hi, d))
                adjust = (item.id, d, d)
            }
            .onEnded { _ in commitAdjust(original) }
    }

    private func resizeHandle(for item: TimeBlock) -> some View {
        let original = blocks.first { $0.id == item.id } ?? item
        return Rectangle().fill(Color.clear)
            .frame(height: 10)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { g in
                        var d = snap(g.translation.height)
                        let minEnd = -(original.minutes - 15)
                        let maxEnd = Int(dayEnd.timeIntervalSince(original.end) / 60)
                        d = max(minEnd, min(maxEnd, d))
                        adjust = (item.id, 0, d)
                    }
                    .onEnded { _ in commitAdjust(original) }
            )
    }

    private func commitAdjust(_ original: TimeBlock) {
        if let a = adjust, a.dStart != 0 || a.dEnd != 0 {
            onMoveResize(original.id,
                         original.start.addingTimeInterval(TimeInterval(a.dStart * 60)),
                         original.end.addingTimeInterval(TimeInterval(a.dEnd * 60)))
        }
        adjust = nil
    }

    private func snap(_ dy: CGFloat) -> Int { Int((dy / ptPerMinute / 15).rounded()) * 15 }

    // MARK: Geometry

    private func colWidth(_ total: CGFloat, _ p: LanePlacement) -> CGFloat { (total - gap * CGFloat(p.cols - 1)) / CGFloat(p.cols) }
    private func colX(_ total: CGFloat, _ p: LanePlacement) -> CGFloat { CGFloat(p.col) * (colWidth(total, p) + gap) }
    private func cardHeight(_ b: TimeBlock) -> CGFloat { max(20, CGFloat(b.minutes) * ptPerMinute - 3) }

    private func preview(title: String?, kind: BlockKind, start: Date, end: Date) -> some View {
        let mins = max(15, Int(end.timeIntervalSince(start) / 60))
        return VStack(alignment: .leading, spacing: 2) {
            Text(title?.isEmpty == false ? title! : "\(start.shortTime) – \(end.shortTime)")
                .font(TypeScale.label).foregroundColor(kind.color)
            if title?.isEmpty == false {
                Text("\(start.shortTime) – \(end.shortTime)").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(20, CGFloat(mins) * ptPerMinute - 3))
        .background(kind.color.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundColor(kind.color))
        .offset(y: yOffset(start) + 1)
        .allowsHitTesting(false)
    }

    private var rules: some View {
        Canvas { ctx, size in
            for i in 0...(totalMinutes / 30) {
                let y = CGFloat(i * 30) * ptPerMinute + 0.5
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                if i % 2 == 0 {
                    ctx.stroke(p, with: .color(Theme.rule), lineWidth: 1)
                } else {
                    ctx.stroke(p, with: .color(Theme.ruleFaint), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var nowLine: some View {
        if Calendar.current.isDateInToday(date) {
            let y = yOffset(Date())
            if y > 0 && y < height {
                HStack(spacing: Space.xs) {
                    Text(Date().shortTime).font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundColor(Theme.nowLine)
                    Circle().fill(Theme.nowLine).frame(width: 6, height: 6)
                    Rectangle().fill(Theme.nowLine).frame(height: 1.5)
                }
                .frame(height: 12)
                .offset(y: y - 6)
                .allowsHitTesting(false)
            }
        }
    }

    private func time(at y: CGFloat) -> Date {
        let mins = Int((max(0, min(y, height)) / ptPerMinute / 15).rounded()) * 15
        return dayStart.addingTimeInterval(TimeInterval(mins * 60))
    }

    private func yOffset(_ time: Date) -> CGFloat {
        let mins = time.timeIntervalSince(dayStart) / 60
        return CGFloat(min(max(mins, 0), Double(totalMinutes))) * ptPerMinute
    }
}

/// A calendar event that isn't a block yet: outlined, quiet, one click to adopt.
struct GhostCard: View {
    let block: TimeBlock
    @State private var hover = false
    var body: some View {
        HStack(alignment: .top) {
            Text(block.title).font(TypeScale.body).foregroundColor(Theme.inkFaint).lineLimit(1)
            Spacer(minLength: 0)
            Text(hover ? "Add as block" : "\(block.start.shortTime)–\(block.end.shortTime)")
                .font(TypeScale.caption.monospacedDigit()).foregroundColor(hover ? Theme.ink : Theme.inkFaint)
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.meeting.opacity(hover ? 0.10 : 0.04))
        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundColor(Theme.meeting.opacity(0.6)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct BlockCard: View {
    let block: TimeBlock
    let selected: Bool
    let session: CycleSession?
    @EnvironmentObject var store: Store
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(block.kind.color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(block.title).font(TypeScale.label).foregroundColor(Theme.ink).lineLimit(2)
                    Spacer(minLength: 0)
                    Text("\(block.start.shortTime)–\(block.end.shortTime)")
                        .font(TypeScale.caption.monospacedDigit()).foregroundColor(Theme.inkFaint)
                }
                if !block.taskIDs.isEmpty, block.minutes >= 30 {
                    let tasks = block.taskIDs.compactMap { store.task($0) }
                    ForEach(tasks.prefix(max(1, block.minutes / 20))) { t in
                        HStack(spacing: 4) {
                            Image(systemName: t.done ? "checkmark.circle.fill" : "circle").font(.system(size: 9))
                                .foregroundColor(t.done ? Theme.breakC : Theme.inkFaint)
                            Text(t.text).font(TypeScale.caption).foregroundColor(t.done ? Theme.inkFaint : Theme.ink).lineLimit(1)
                        }
                    }
                } else if block.minutes >= 45, !block.notes.isEmpty {
                    Text(block.notes).font(TypeScale.caption).foregroundColor(Theme.inkFaint).lineLimit(block.minutes >= 90 ? 4 : 1)
                }
                if let s = session, block.minutes >= 40 {
                    HStack(spacing: 3) {
                        ForEach(0..<s.cycleCount, id: \.self) { i in
                            let c = i < s.cycles.count ? s.cycles[i] : WorkCycle()
                            Capsule()
                                .fill(c.completed.isEmpty ? Theme.deep.opacity(0.25) : (c.completed == "Yes" ? Theme.deep : Theme.deep.opacity(0.6)))
                                .frame(width: 14, height: 4)
                        }
                        Text("\(s.deepMinutes) min").font(.system(size: 10)).foregroundColor(Theme.inkFaint)
                    }
                }
            }
            .padding(.vertical, Space.xs).padding(.horizontal, Space.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(block.kind.color.opacity(selected ? 0.24 : (hover ? 0.20 : 0.15)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            .stroke(selected ? block.kind.color : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
