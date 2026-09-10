import Foundation

/// The keyboard flow through a Work Cycles session: one primary action per step (⌘↩), shared
/// by the buttons in Focus, the Cycle menu and the command palette. Works on `store.today`
/// (the selected day), which is the day Focus shows; the selection itself is in `ui`.
@MainActor
package struct SessionFlow {
    package let store: Store
    package let ui: AppState
    package let engine: CycleEngine

    package init(store: Store, ui: AppState, engine: CycleEngine) {
        self.store = store
        self.ui = ui
        self.engine = engine
    }

    // MARK: Lookup

    package var selected: CycleSession? {
        guard let id = ui.focusSessionID else { return nil }
        return store.today.sessions.first { $0.id == id }
    }

    package func index(_ id: UUID) -> Int? {
        store.today.sessions.firstIndex { $0.id == id }
    }

    /// The deep block a new session should belong to: the first one without a session that
    /// hasn't ended yet, else the first free one, else nil (standalone).
    package func nextFreeDeepBlock(now: Date = Date()) -> TimeBlock? {
        let free = store.today.blocks
            .filter { $0.kind == .deep && store.session(forBlock: $0.id) == nil }
            .sorted { $0.start < $1.start }
        return free.first { $0.end > now } ?? free.first
    }

    /// The step a session should open on: Debrief once finished, Work once anything has
    /// happened in it (or its timer is attached), otherwise Prepare.
    package func stage(for s: CycleSession) -> SessionStage {
        if s.finished { return .debrief }
        if engine.sessionID == s.id && engine.phase != .idle { return .work }
        return s.hasStarted ? .work : .prepare
    }

    /// The timer belongs to this session and is waiting for the REVIEW answers.
    package func isReviewing(_ s: CycleSession) -> Bool {
        engine.sessionID == s.id && engine.phase == .reviewing
    }

    // MARK: Primary action (⌘↩)

    package var primaryTitle: String {
        guard let s = selected else { return "New Session" }
        switch ui.focusStage {
        case .prepare:
            return "Plan the First Cycle"
        case .debrief:
            return s.finished ? "Session Finished" : "Finish Session"
        case .work:
            if engine.sessionID == s.id {
                switch engine.phase {
                case .reviewing: return s.isLastCycle ? "Finish and Debrief" : "Start Break"
                case .working: return "Cycle Running"
                case .breaking: return "Break Running"
                default: break
                }
            }
            return "Start Cycle"
        }
    }

    package var primaryEnabled: Bool {
        guard let s = selected else { return true }
        switch ui.focusStage {
        case .prepare: return true
        case .debrief: return !s.finished
        case .work:
            if engine.isRunning { return false }
            if isReviewing(s) { return s.current.completed != nil }
            return true
        }
    }

    package func performPrimary() {
        guard let s = selected else {
            newSession(from: nextFreeDeepBlock())
            return
        }
        switch ui.focusStage {
        case .prepare:
            toPlan(s.id)
        case .debrief:
            setFinished(s.id, true)
        case .work:
            guard !engine.isRunning else { return }
            if isReviewing(s) {
                // Can't move on without answering the target question; send focus there.
                guard s.current.completed != nil else { ui.requestFormFocus(); return }
                if s.isLastCycle { toDebrief(s.id) } else { startBreak(s.id) }
            } else {
                startCycle(s.id)
            }
        }
    }

    // MARK: Steps

    package func ensureCycles(_ id: UUID) {
        guard let i = index(id) else { return }
        store.today.sessions[i].ensureCycles()
    }

    /// Prepare → Work: make sure the cycles exist and land in the first PLAN field.
    package func toPlan(_ id: UUID) {
        ensureCycles(id)
        ui.focusStage = .work
        ui.requestFormFocus()
    }

    package func startCycle(_ id: UUID) {
        guard !engine.isRunning, let i = index(id) else { return }
        ensureCycles(id)
        ui.focusStage = .work
        engine.attach(sessionID: id, dateKey: store.selectedKey)
        engine.startWork(minutes: store.today.sessions[i].cycleMinutes)
    }

    /// After REVIEW: move to the next cycle and run the break timer.
    package func startBreak(_ id: UUID) {
        guard let i = index(id) else { return }
        store.today.sessions[i].advance()
        engine.attach(sessionID: id, dateKey: store.selectedKey)
        engine.startBreak(minutes: store.today.sessions[i].breakMinutes)
    }

    /// After REVIEW: straight on to planning the next cycle.
    package func skipBreak(_ id: UUID) {
        guard let i = index(id) else { return }
        store.today.sessions[i].advance()
        engine.stop()
        engine.attach(sessionID: id, dateKey: store.selectedKey)
        ui.requestFormFocus()
    }

    /// Stop the timer and open the debrief.
    package func toDebrief(_ id: UUID) {
        if engine.sessionID == id { engine.stop() }
        ui.focusStage = .debrief
        ui.requestFormFocus()
    }

    /// The debrief's "Session finished" switch. Finishing stops the timer and leaves Focus.
    package func setFinished(_ id: UUID, _ finished: Bool) {
        guard let i = index(id) else { return }
        store.today.sessions[i].finished = finished
        guard finished else { return }
        if engine.sessionID == id { engine.stop() }
        ui.focusMode = false
    }

    // MARK: Sessions

    /// Create a session (sized to `block` if given), select it and start at Prepare.
    package func newSession(from block: TimeBlock?) {
        let s = block.map { CycleSession.fitting(block: $0) } ?? CycleSession()
        store.today.sessions.append(s)
        ui.focusSessionID = s.id
        ui.focusStage = .prepare
        ui.requestFormFocus()
    }

    /// From the Day page or the top bar: a session for this block, on the timer, in Focus.
    package func runCycles(on block: TimeBlock) {
        let s = CycleSession.fitting(block: block)
        store.today.sessions.append(s)
        ui.focusSessionID = s.id
        ui.focusStage = .prepare
        engine.attach(sessionID: s.id, dateKey: store.selectedKey)
        ui.focusMode = true
        ui.requestFormFocus()
    }

    /// Open an existing session in Focus with the timer attached to it.
    package func open(_ s: CycleSession) {
        engine.attach(sessionID: s.id, dateKey: store.selectedKey)
        select(s)
        ui.focusMode = true
    }

    package func select(_ s: CycleSession) {
        ui.focusSessionID = s.id
        ui.focusStage = stage(for: s)
    }

    /// Sessions as the list shows them: live ones in day order, then the finished ones.
    package var listOrder: [CycleSession] {
        let ordered = store.today.orderedSessions
        return ordered.filter { !$0.finished } + ordered.filter { $0.finished }
    }

    package func selectAdjacent(_ delta: Int) {
        let list = listOrder
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == ui.focusSessionID } ?? (delta > 0 ? -1 : list.count)
        select(list[max(0, min(list.count - 1, i + delta))])
    }

    /// Undoable (⌘Z restores the day, sessions included).
    package func delete(_ id: UUID) {
        store.snapshot()
        if engine.sessionID == id { engine.stop() }
        store.today.sessions.removeAll { $0.id == id }
        if ui.focusSessionID == id { ui.focusSessionID = nil }
    }
}
