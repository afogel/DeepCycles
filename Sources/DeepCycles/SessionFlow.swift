import Foundation

/// The keyboard flow through a Work Cycles session: one primary action per step (⌘↩), shared
/// by the buttons in Focus, the Cycle menu and the command palette. Everything works on
/// `store.today` (the selected day), which is the day Focus shows.
enum SessionFlow {
    // MARK: Lookup

    static func selected(_ store: Store) -> CycleSession? {
        guard let id = store.focusSessionID else { return nil }
        return store.today.sessions.first { $0.id == id }
    }

    static func index(_ store: Store, _ id: UUID) -> Int? {
        store.today.sessions.firstIndex { $0.id == id }
    }

    static func isLast(_ s: CycleSession) -> Bool { s.currentCycle >= s.cycleCount - 1 }

    static func currentCycle(_ s: CycleSession) -> WorkCycle {
        s.cycles.indices.contains(s.currentCycle) ? s.cycles[s.currentCycle] : WorkCycle()
    }

    /// Pad or trim `cycles` to `cycleCount`, and keep `currentCycle` in range.
    static func ensureCycles(_ s: inout CycleSession) {
        while s.cycles.count < s.cycleCount { s.cycles.append(WorkCycle()) }
        if s.cycles.count > s.cycleCount { s.cycles.removeLast(s.cycles.count - s.cycleCount) }
        if s.currentCycle >= s.cycleCount { s.currentCycle = max(0, s.cycleCount - 1) }
    }

    static func ensureCycles(_ store: Store, _ id: UUID) {
        guard let i = index(store, id) else { return }
        ensureCycles(&store.today.sessions[i])
    }

    /// The deep block a new session should belong to: the first one without a session that
    /// hasn't ended yet, else the first free one, else nil (standalone).
    static func nextFreeDeepBlock(_ store: Store, now: Date = Date()) -> TimeBlock? {
        let free = store.today.blocks
            .filter { $0.kind == .deep && store.session(forBlock: $0.id) == nil }
            .sorted { $0.start < $1.start }
        return free.first { $0.end > now } ?? free.first
    }

    /// The step a session should open on: Debrief once finished, Work once anything has
    /// happened in it (or its timer is attached), otherwise Prepare.
    static func stage(for s: CycleSession, _ engine: CycleEngine) -> Int {
        if s.finished { return 2 }
        if engine.sessionID == s.id && engine.phase != .idle { return 1 }
        if !s.accomplish.isEmpty { return 1 }
        if s.cycles.contains(where: { !$0.goal.isEmpty || $0.workedSeconds > 0 || !$0.completed.isEmpty }) { return 1 }
        return 0
    }

    // MARK: Primary action (⌘↩)

    static func primaryTitle(_ store: Store, _ engine: CycleEngine) -> String {
        guard let s = selected(store) else { return "New Session" }
        switch store.focusStage {
        case 0: return "Plan the First Cycle"
        case 2: return s.finished ? "Session Finished" : "Finish Session"
        default:
            if engine.sessionID == s.id {
                switch engine.phase {
                case .reviewing: return isLast(s) ? "Finish and Debrief" : "Start Break"
                case .working: return "Cycle Running"
                case .breaking: return "Break Running"
                default: break
                }
            }
            return "Start Cycle"
        }
    }

    static func primaryEnabled(_ store: Store, _ engine: CycleEngine) -> Bool {
        guard let s = selected(store) else { return true }
        switch store.focusStage {
        case 0: return true
        case 2: return !s.finished
        default:
            if engine.isRunning { return false }
            if engine.sessionID == s.id, engine.phase == .reviewing { return !currentCycle(s).completed.isEmpty }
            return true
        }
    }

    static func performPrimary(_ store: Store, _ engine: CycleEngine) {
        guard let s = selected(store) else {
            newSession(store, from: nextFreeDeepBlock(store))
            return
        }
        switch store.focusStage {
        case 0:
            toPlan(store, s.id)
        case 2:
            setFinished(store, engine, s.id, true)
        default:
            guard !engine.isRunning else { return }
            if engine.sessionID == s.id, engine.phase == .reviewing {
                // Can't move on without answering the target question; send focus there.
                guard !currentCycle(s).completed.isEmpty else { store.requestFormFocus(); return }
                if isLast(s) { toDebrief(store, engine, s.id) } else { startBreak(store, engine, s.id) }
            } else {
                startCycle(store, engine, s.id)
            }
        }
    }

    // MARK: Steps

    /// Prepare → Work: make sure the cycles exist and land in the first PLAN field.
    static func toPlan(_ store: Store, _ id: UUID) {
        ensureCycles(store, id)
        store.focusStage = 1
        store.requestFormFocus()
    }

    static func startCycle(_ store: Store, _ engine: CycleEngine, _ id: UUID) {
        guard !engine.isRunning, let i = index(store, id) else { return }
        ensureCycles(store, id)
        store.focusStage = 1
        engine.attach(sessionID: id, dateKey: store.selectedKey)
        engine.startWork(minutes: store.today.sessions[i].cycleMinutes)
    }

    /// After REVIEW: move to the next cycle and run the break timer.
    static func startBreak(_ store: Store, _ engine: CycleEngine, _ id: UUID) {
        guard let i = index(store, id) else { return }
        advance(store, i)
        engine.attach(sessionID: id, dateKey: store.selectedKey)
        engine.startBreak(minutes: store.today.sessions[i].breakMinutes)
    }

    /// After REVIEW: straight on to planning the next cycle.
    static func skipBreak(_ store: Store, _ engine: CycleEngine, _ id: UUID) {
        guard let i = index(store, id) else { return }
        advance(store, i)
        engine.stop()
        engine.attach(sessionID: id, dateKey: store.selectedKey)
        store.requestFormFocus()
    }

    /// Stop the timer and open the debrief.
    static func toDebrief(_ store: Store, _ engine: CycleEngine, _ id: UUID) {
        if engine.sessionID == id { engine.stop() }
        store.focusStage = 2
        store.requestFormFocus()
    }

    /// The debrief's "Session finished" switch. Finishing stops the timer and leaves Focus.
    static func setFinished(_ store: Store, _ engine: CycleEngine, _ id: UUID, _ finished: Bool) {
        guard let i = index(store, id) else { return }
        store.today.sessions[i].finished = finished
        guard finished else { return }
        if engine.sessionID == id { engine.stop() }
        store.focusMode = false
    }

    private static func advance(_ store: Store, _ i: Int) {
        if store.today.sessions[i].currentCycle < store.today.sessions[i].cycleCount - 1 {
            store.today.sessions[i].currentCycle += 1
        }
    }

    // MARK: Sessions

    /// Create a session (sized to `block` if given), select it and start at Prepare.
    static func newSession(_ store: Store, from block: TimeBlock?) {
        let s = block.map { CycleSession.fitting(block: $0) } ?? CycleSession()
        store.today.sessions.append(s)
        store.focusSessionID = s.id
        store.focusStage = 0
        store.requestFormFocus()
    }

    /// From the Day page or the top bar: a session for this block, on the timer, in Focus.
    static func runCycles(on block: TimeBlock, _ store: Store, _ engine: CycleEngine) {
        let s = CycleSession.fitting(block: block)
        store.today.sessions.append(s)
        store.focusSessionID = s.id
        store.focusStage = 0
        engine.attach(sessionID: s.id, dateKey: store.selectedKey)
        store.focusMode = true
        store.requestFormFocus()
    }

    /// Open an existing session in Focus with the timer attached to it.
    static func open(_ store: Store, _ engine: CycleEngine, _ s: CycleSession) {
        engine.attach(sessionID: s.id, dateKey: store.selectedKey)
        select(store, engine, s)
        store.focusMode = true
    }

    static func select(_ store: Store, _ engine: CycleEngine, _ s: CycleSession) {
        store.focusSessionID = s.id
        store.focusStage = stage(for: s, engine)
    }

    /// Sessions as the list shows them: live ones in day order, then the finished ones.
    static func listOrder(_ store: Store) -> [CycleSession] {
        let ordered = store.orderedSessions(store.today)
        return ordered.filter { !$0.finished } + ordered.filter { $0.finished }
    }

    static func selectAdjacent(_ store: Store, _ engine: CycleEngine, _ delta: Int) {
        let list = listOrder(store)
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == store.focusSessionID } ?? (delta > 0 ? -1 : list.count)
        select(store, engine, list[max(0, min(list.count - 1, i + delta))])
    }

    /// Undoable (⌘Z restores the day, sessions included).
    static func delete(_ store: Store, _ engine: CycleEngine, _ id: UUID) {
        store.snapshot()
        if engine.sessionID == id { engine.stop() }
        store.today.sessions.removeAll { $0.id == id }
        if store.focusSessionID == id { store.focusSessionID = nil }
    }
}
