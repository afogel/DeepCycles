import Foundation
import Combine

/// Everything that is saved: one `DayPlan` per day in plans.json and the `SystemDocs` in
/// system.json, under the data directory. Also the day being looked at (every "today" query is
/// relative to it) and the undo history for block edits. What the window is showing lives in
/// `AppState`, not here.
///
/// Writes are coalesced: a change schedules a save a few hundred milliseconds out, and later
/// changes in that window replace it. `flush()` writes at once; the app calls it when it resigns
/// active or quits.
@MainActor
package final class Store: ObservableObject {
    @Published package var plans: [String: DayPlan] = [:] { didSet { scheduleSave(.plans) } }
    @Published package var system: SystemDocs = SystemDocs() { didSet { scheduleSave(.system) } }
    @Published package var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// Where plans.json and system.json live.
    package let directory: URL

    private let saveDelay: Duration
    private var pendingSaves: [SaveTarget: Task<Void, Never>] = [:]
    private var loaded = false
    private var history = UndoHistory<DaySnapshot>(limit: 50)

    private enum SaveTarget { case plans, system }

    /// `directory` defaults to `$DEEPCYCLES_DATA_DIR`, else `~/Library/Application Support/DeepCycles`.
    package init(directory: URL? = nil, saveDelay: Duration = .milliseconds(400)) {
        let dir = directory
            ?? ProcessInfo.processInfo.environment["DEEPCYCLES_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DeepCycles", isDirectory: true)
        self.directory = dir
        self.saveDelay = saveDelay
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url(.plans)),
           let decoded = try? JSONDecoder().decode([String: DayPlan].self, from: data) {
            plans = decoded
        }
        if let data = try? Data(contentsOf: url(.system)),
           let decoded = try? JSONDecoder().decode(SystemDocs.self, from: data) {
            system = decoded
        }
        loaded = true
    }

    private func url(_ target: SaveTarget) -> URL {
        directory.appendingPathComponent(target == .plans ? "plans.json" : "system.json")
    }

    // MARK: Persistence

    private func scheduleSave(_ target: SaveTarget) {
        guard loaded else { return }
        pendingSaves[target]?.cancel()
        let delay = saveDelay
        pendingSaves[target] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.write(target)
        }
    }

    /// Write out anything not yet saved.
    package func flush() {
        let due = pendingSaves
        pendingSaves.removeAll()
        for (target, task) in due {
            task.cancel()
            write(target)
        }
    }

    /// True while a save is scheduled but not yet written.
    package var hasUnsavedChanges: Bool { !pendingSaves.isEmpty }

    private func write(_ target: SaveTarget) {
        pendingSaves[target] = nil
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data?
        switch target {
        case .plans: data = try? enc.encode(plans)
        case .system: data = try? enc.encode(system)
        }
        if let data { try? data.write(to: url(target), options: .atomic) }
    }

    // MARK: Undo (block edits; ⌘Z restores the whole day)

    package struct DaySnapshot {
        package let key: String
        package let plan: DayPlan
    }

    package var canUndo: Bool { history.canUndo }
    package var canRedo: Bool { history.canRedo }

    /// Call before any block edit.
    package func snapshot() {
        history.record(DaySnapshot(key: selectedKey, plan: today))
        objectWillChange.send()
    }

    /// Restores the previous state of the day it belongs to (switching to that day if needed).
    /// Returns false when there was nothing to undo.
    @discardableResult
    package func undo() -> Bool {
        restore(history.undo { self.current($0) })
    }

    @discardableResult
    package func redo() -> Bool {
        restore(history.redo { self.current($0) })
    }

    private func current(_ s: DaySnapshot) -> DaySnapshot {
        DaySnapshot(key: s.key, plan: plans[s.key] ?? DayPlan())
    }

    private func restore(_ s: DaySnapshot?) -> Bool {
        guard let s else { return false }
        plans[s.key] = s.plan
        if s.key != selectedKey, let d = DateKeys.date(fromDay: s.key) { selectedDate = d }
        return true
    }

    // MARK: Days

    package var selectedKey: String { DateKeys.day(selectedDate) }

    /// The plan for the selected day (created on first write).
    package var today: DayPlan {
        get { plans[selectedKey] ?? freshDay() }
        set { plans[selectedKey] = newValue }
    }

    package func plan(for date: Date) -> DayPlan { plans[DateKeys.day(date)] ?? freshDay() }

    /// An empty day with the hours from Settings.
    package func freshDay() -> DayPlan {
        var p = DayPlan()
        p.workStartHour = system.defaultWorkStartHour
        p.workEndHour = max(system.defaultWorkStartHour + 1, system.defaultWorkEndHour)
        return p
    }

    package func shiftDay(_ days: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
    }

    /// Combine the selected day with an hour/minute.
    package func time(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate) ?? selectedDate
    }

    package func session(forBlock id: UUID) -> CycleSession? { today.session(forBlock: id) }

    /// The deep-work block that contains `now` on the selected day, if any.
    package func currentDeepBlock(now: Date = Date()) -> TimeBlock? {
        guard Calendar.current.isDate(now, inSameDayAs: selectedDate) else { return nil }
        return today.blocks.first { $0.kind == .deep && $0.start <= now && now < $0.end }
    }

    // MARK: Sessions on any day (the timer may outlive the day being looked at)

    package func session(_ id: UUID, dateKey: String) -> CycleSession? {
        plans[dateKey]?.sessions.first { $0.id == id }
    }

    /// Edit one session in place, wherever it is. No-op if it no longer exists.
    package func updateSession(_ id: UUID, dateKey: String, _ change: (inout CycleSession) -> Void) {
        guard var plan = plans[dateKey], let i = plan.sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&plan.sessions[i])
        plans[dateKey] = plan
    }

    package struct SessionLogEntry {
        package let date: Date
        package let block: TimeBlock?
        package let session: CycleSession
    }

    /// All sessions across the last `days` days, newest first, for review.
    package func sessionLog(days: Int = 30, now: Date = Date()) -> [SessionLogEntry] {
        let since = now.addingTimeInterval(-Double(days) * 86400)
        var out: [SessionLogEntry] = []
        for (key, plan) in plans {
            guard let d = DateKeys.date(fromDay: key), d > since else { continue }
            for s in plan.orderedSessions {
                out.append(SessionLogEntry(date: d, block: plan.blocks.first { $0.id == s.blockID }, session: s))
            }
        }
        return out.sorted { $0.date == $1.date ? $0.session.created > $1.session.created : $0.date > $1.date }
    }

    // MARK: Weeks

    package var selectedWeekKey: String { DateKeys.week(selectedDate) }

    package var thisWeek: WeekPlan {
        get { system.weeks[selectedWeekKey] ?? WeekPlan() }
        set { system.weeks[selectedWeekKey] = newValue }
    }

    /// The week before the selected one, if it was planned.
    package var lastWeek: WeekPlan? {
        let d = Calendar.current.date(byAdding: .day, value: -7, to: selectedDate) ?? selectedDate
        return system.weeks[DateKeys.week(d)]
    }

    /// Daily tick for a values-plan habit.
    package func valueDone(_ id: UUID, on date: Date) -> Bool { plan(for: date).valueDone(id) }

    package func setValueDone(_ id: UUID, on date: Date, _ done: Bool) {
        var p = plan(for: date)
        p.setValueDone(id, done)
        plans[DateKeys.day(date)] = p
    }

    // MARK: Documents and tasks

    package func docText(_ kind: CoreDoc.Kind) -> String { system.doc(kind)?.text ?? "" }

    package func setDocText(_ kind: CoreDoc.Kind, _ text: String) {
        guard let i = system.docs.firstIndex(where: { $0.kind == kind }) else { return }
        system.docs[i].text = text
        system.docs[i].updated = Date()
    }

    /// Shutdown "full capture": move today's captured items into the task list.
    /// Items already ticked off are dropped; the rest are trusted to the list.
    package func processCollection() {
        let open = today.captured.filter { !$0.done && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        system.tasks.insert(contentsOf: open, at: 0)
        today.captured = []
    }

    package var openTasks: [TaskItem] { system.openTasks }

    /// Looks in the task list first, then in every week's outcomes.
    package func task(_ id: UUID) -> TaskItem? {
        if let t = system.tasks.first(where: { $0.id == id }) { return t }
        for w in system.weeks.values {
            if let t = w.outcomes.first(where: { $0.id == id }) { return t }
        }
        return nil
    }
}
