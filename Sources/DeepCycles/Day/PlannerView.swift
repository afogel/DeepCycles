import SwiftUI
import DeepCyclesCore

/// The Day page: the time-block grid on the left, the inspector (this week, the block being
/// edited, Collection) on the right. Also where calendar sync is driven from.
@MainActor
struct PlannerView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
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
    @Environment(\.openSettings) private var openSettings
    /// Keyboard stops the planner places itself: the title field, and the grid (↑↓ select, ↩ edit, ⌫ delete).
    enum Field { case title, grid }

    private var flow: SessionFlow { SessionFlow(store: store, ui: ui, engine: engine) }

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
                focus: $focus,
                onTapBlock: { select($0) },
                onTapGhost: { adopt($0) },
                onCreate: { start, end in newDraft(start: start, end: end, placed: true); focus = .title },
                onMoveResize: { id, start, end in moveResize(id, start: start, end: end) },
                onMoveSelection: { moveSelection($0) },
                onEdit: { focus = .title },
                onDelete: { deleteEditing() }
            )
            inspector.frame(width: 320)
        }
        .onAppear { reloadCalendar(); newDraft(start: defaultStart(), end: nil); handlePending() }
        .onChange(of: store.selectedDate) { reloadCalendar(); editingID = nil; newDraft(start: defaultStart(), end: nil) }
        .onChange(of: draft) { if editingID == nil { draftPlaced = true } }
        .onChange(of: calendar.authorized) { reloadCalendar() }
        .onChange(of: ui.pending) { handlePending() }
    }

    /// Menu / palette commands this page carries out. Also run on appear, for a command
    /// posted while another page was showing.
    private func handlePending() {
        guard let cmd = ui.pending else { return }
        switch cmd {
        case .newBlock: editingID = nil; newDraft(start: defaultStart(), end: nil); draftPlaced = true; focus = .title
        case .deleteBlock: deleteEditing()
        case .focusCollection: captureFocus += 1
        case .importEvents: adoptAll()
        case .pushPlan: syncAll()
        case .reconcileCalendar: reconcile()
        default: return
        }
        ui.pending = nil
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
                Button("Write this week's plan") { ui.tab = .week }.buttonStyle(QuietButtonStyle())
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week").font(TypeScale.title).foregroundColor(Theme.ink)
                    Spacer()
                    Button("Open") { ui.tab = .week }.buttonStyle(QuietButtonStyle())
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
                    Button("Delete  ⌘⌫") { deleteEditing() }.buttonStyle(QuietButtonStyle())
                }
            }

            TextField("What will you do?", text: $draft.title)
                .focused($focus, equals: .title)
                .onSubmit(submitDraft)
                .textFieldStyle(.plain).font(.system(size: 15, weight: .medium))
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .stroke(focus == .title ? Theme.deep : Color.clear, lineWidth: 1.5))

            KindPicker(kind: $draft.kind)

            HStack(spacing: Space.s) {
                DatePicker("", selection: $draft.start, displayedComponents: .hourAndMinute).labelsHidden()
                Text("to").font(TypeScale.body).foregroundColor(Theme.inkFaint)
                Text(draft.end.shortTime).font(TypeScale.body.monospacedDigit()).foregroundColor(Theme.ink)
                Text("· \(draft.minutes) min").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                Spacer()
            }
            DurationPresets(draft: $draft)
            if draft.kind == .deep {
                let fit = CycleSession.fitting(block: draft)
                Text("\(fit.cycleCount) cycle\(fit.cycleCount == 1 ? "" : "s") of \(fit.cycleMinutes) min")
                    .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }

            if draft.kind == .tasks {
                taskPicker
            } else if draft.kind == .deep, !store.thisWeek.outcomes.filter({ !$0.done }).isEmpty {
                outcomePicker
                notesField(lines: 1...3)
            } else {
                notesField(lines: 1...4)
            }

            HStack(spacing: Space.m) {
                Button(editingID == nil ? "Add block" : "Save") { commitDraft() }
                    .buttonStyle(InkButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("↩").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }

            if let id = editingID, draft.kind == .deep {
                if let s = store.session(forBlock: id) {
                    Button("Cycles: \(s.cyclesDone) of \(s.cycleCount) done, \(s.deepMinutes) min") { flow.open(s) }
                        .buttonStyle(QuietButtonStyle())
                } else {
                    Button("Run work cycles on this block") { flow.runCycles(on: draft) }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private func notesField(lines: ClosedRange<Int>) -> some View {
        TextField("Notes", text: $draft.notes, axis: .vertical)
            .onSubmit(submitDraft)
            .lineLimit(lines).textFieldStyle(.plain).font(TypeScale.body)
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
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
                    CheckRow(text: t.text, on: draft.taskIDs.contains(t.id), tint: Theme.tasks) { toggleTask(t.id) }
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
                CheckRow(text: t.text, on: draft.taskIDs.contains(t.id)) { toggleTask(t.id) }
            }
        }
        .padding(.vertical, Space.xs)
    }

    private func toggleTask(_ id: UUID) {
        if draft.taskIDs.contains(id) { draft.taskIDs.removeAll { $0 == id } } else { draft.taskIDs.append(id) }
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
            let planned = store.today.plannedMinutes
            if planned > 0 {
                Text("\(hm(planned)) blocked · \(hm(store.today.deepMinutesPlanned)) deep")
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
            Button(store.today.shutdownComplete ? "Day closed" : "End day") { ui.showShutdown = true }
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

    /// This day's hours and calendar actions. Appearance, default hours and sync live in Settings (⌘,).
    private var settings: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("This day").font(TypeScale.title).foregroundColor(Theme.ink)
            HStack(spacing: Space.l) {
                ValueStepper($store.today.workStartHour, in: 0...22) { "From \($0):00" }
                ValueStepper($store.today.workEndHour, in: 1...23) { "to \($0):00" }
            }
            .onChange(of: store.today.workStartHour) {
                if store.today.workEndHour <= store.today.workStartHour { store.today.workEndHour = store.today.workStartHour + 1 }
            }
            .onChange(of: store.today.workEndHour) {
                if store.today.workStartHour >= store.today.workEndHour { store.today.workStartHour = store.today.workEndHour - 1 }
            }
            Text("New days use the hours from Settings.").font(TypeScale.caption).foregroundColor(Theme.inkFaint)

            Divider()
            Text(syncHelp).font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            if let err = calendar.lastError {
                Text(err).font(TypeScale.caption).foregroundColor(Theme.nowLine).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if calendar.authorized {
                    Button("Sync now") { syncAll() }.buttonStyle(QuietButtonStyle())
                    Button("Adopt all events") { adoptAll() }.buttonStyle(QuietButtonStyle())
                } else {
                    Button("Retry access") { Task { await calendar.requestAccess() } }.buttonStyle(QuietButtonStyle())
                }
                Spacer()
                Button("Settings…  ⌘,") { showSettings = false; openSettings() }.buttonStyle(QuietButtonStyle())
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
        focus = .grid          // the grid takes the keyboard: ⌫ deletes the block, ↑↓ move, ↩ edits the title
        editingID = block.id
        draft = block
    }

    /// ↑ / ↓ on the grid: step through the day's blocks in time order.
    private func moveSelection(_ d: Int) {
        let blocks = store.today.blocks.sorted { $0.start < $1.start }
        guard !blocks.isEmpty else { return }
        let i = blocks.firstIndex { $0.id == editingID } ?? (d > 0 ? -1 : blocks.count)
        select(blocks[max(0, min(blocks.count - 1, i + d))])
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
            if BlockKind.isOwnEvent(g.title) { continue }
            store.today.blocks.append(g)
        }
        store.today.blocks.sort { $0.start < $1.start }
    }

    /// Return in the title or notes field: add / save, and stay in the title for the next block.
    private func submitDraft() {
        guard !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        commitDraft()
        focus = .title
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

    // MARK: Calendar sync

    private func sync(_ block: TimeBlock) {
        guard calendar.autoSync, calendar.authorized, !block.fromCalendar else { return }
        do {
            let id = try calendar.push(block)
            if let i = store.today.blocks.firstIndex(where: { $0.id == block.id }) { store.today.blocks[i].eventID = id }
            flash("Synced")
        } catch {
            flash("Sync failed")
            calendar.lastError = error.localizedDescription
        }
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
        for e in calendar.events(on: store.selectedDate) where BlockKind.isOwnEvent(e.title) {
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
}
