import Foundation
import SwiftUI

// MARK: - Time blocks (Cal Newport)

enum BlockKind: String, Codable, CaseIterable, Identifiable {
    case deep, shallow, meeting, tasks, breakTime, overflow
    var id: String { rawValue }

    var label: String {
        switch self {
        case .deep: return "Deep work"
        case .shallow: return "Shallow (email, admin)"
        case .meeting: return "Meeting / call"
        case .tasks: return "Task block"
        case .breakTime: return "Break / lunch"
        case .overflow: return "Overflow (conditional)"
        }
    }

    var emoji: String {
        switch self {
        case .deep: return "🔵"
        case .shallow: return "⚪️"
        case .meeting: return "🟣"
        case .tasks: return "🟠"
        case .breakTime: return "🟢"
        case .overflow: return "🟡"
        }
    }

    var color: Color {
        switch self {
        case .deep: return Theme.deep
        case .shallow: return Theme.shallow
        case .meeting: return Theme.meeting
        case .tasks: return Theme.tasks
        case .breakTime: return Theme.breakC
        case .overflow: return Theme.overflow
        }
    }
}

struct TimeBlock: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var start: Date = Date()
    var end: Date = Date().addingTimeInterval(3600)
    var kind: BlockKind = .deep
    var notes: String = ""
    var eventID: String? = nil      // EventKit identifier once pushed / imported
    var fromCalendar: Bool = false  // imported from the calendar, not created here
    var taskIDs: [UUID] = []        // tasks scheduled into this block

    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        kind = try c.decode(BlockKind.self, forKey: .kind)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        eventID = try c.decodeIfPresent(String.self, forKey: .eventID)
        fromCalendar = try c.decodeIfPresent(Bool.self, forKey: .fromCalendar) ?? false
        taskIDs = try c.decodeIfPresent([UUID].self, forKey: .taskIDs) ?? []
    }
}

/// One thing to do. Lives in the daily capture list until shutdown, then in the task list.
struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String = ""
    var done: Bool = false
    var created: Date = Date()
}

// MARK: - Work Cycles (Ultraworking)

struct WorkCycle: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    // PLAN
    var goal: String = ""
    var startPlan: String = ""
    var hazards: String = ""
    var energy: Int = 3
    var morale: Int = 3
    // REVIEW
    var completed: String = ""   // "Yes" / "Half" / "No"
    var noteworthy: String = ""
    var distractions: String = ""
    var improvements: String = ""
    var workedSeconds: Int = 0
}

struct CycleSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var blockID: UUID? = nil
    var title: String = "Work Cycles"
    var created: Date = Date()
    var cycleMinutes: Int = 30
    var breakMinutes: Int = 10
    var cycleCount: Int = 5
    // 1. Prepare
    var accomplish: String = ""
    var important: String = ""
    var complete: String = ""
    var risks: String = ""
    var measurable: String = ""
    var other: String = ""
    // 2. Work
    var cycles: [WorkCycle] = []
    var currentCycle: Int = 0
    // 3. Debrief
    var gotDone: String = ""
    var compare: String = ""
    var boggedDown: String = ""
    var wentWell: String = ""
    var takeaways: String = ""
    var finished: Bool = false

    var deepMinutes: Int { cycles.reduce(0) { $0 + $1.workedSeconds } / 60 }
    var cyclesDone: Int { cycles.filter { !$0.completed.isEmpty }.count }

    /// A session sized to fit inside a deep-work block: as many cycle+break
    /// pairs as fit, dropping the trailing break. Short blocks get shorter cycles.
    static func fitting(block: TimeBlock, cycleMinutes: Int = 30, breakMinutes: Int = 10) -> CycleSession {
        var s = CycleSession()
        s.blockID = block.id
        s.title = block.title
        var cycle = cycleMinutes
        if block.minutes < cycleMinutes + 10 { cycle = max(10, block.minutes - 5) }
        s.cycleMinutes = cycle
        s.breakMinutes = breakMinutes
        s.cycleCount = max(1, (block.minutes + breakMinutes) / (cycle + breakMinutes))
        return s
    }
}

struct Metric: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var value: String
}

struct DayPlan: Codable {
    var blocks: [TimeBlock] = []
    var sessions: [CycleSession] = []
    var metrics: [Metric] = []
    var disciplineLog: [String: String] = [:]   // discipline id -> value ("1" for done, or a number)
    var collection: String = ""          // legacy free text; migrated into `captured`
    var captured: [TaskItem] = []
    var shutdownComplete: Bool = false
    var workStartHour: Int = 8
    var workEndHour: Int = 18

    init() {}

    // Tolerant decoding so older plans.json files keep loading as fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try c.decodeIfPresent([TimeBlock].self, forKey: .blocks) ?? []
        sessions = try c.decodeIfPresent([CycleSession].self, forKey: .sessions) ?? []
        metrics = try c.decodeIfPresent([Metric].self, forKey: .metrics) ?? []
        disciplineLog = try c.decodeIfPresent([String: String].self, forKey: .disciplineLog) ?? [:]
        collection = try c.decodeIfPresent(String.self, forKey: .collection) ?? ""
        captured = try c.decodeIfPresent([TaskItem].self, forKey: .captured) ?? []
        if !collection.isEmpty {   // migrate old free text into items
            captured += collection.split(whereSeparator: \.isNewline).map { TaskItem(text: String($0).trimmingCharacters(in: .whitespaces)) }.filter { !$0.text.isEmpty }
            collection = ""
        }
        shutdownComplete = try c.decodeIfPresent(Bool.self, forKey: .shutdownComplete) ?? false
        workStartHour = try c.decodeIfPresent(Int.self, forKey: .workStartHour) ?? 8
        workEndHour = try c.decodeIfPresent(Int.self, forKey: .workEndHour) ?? 18
    }
}

// MARK: - Core systems (Newport's root document)

/// A hard discipline tracked daily by a short metric code, e.g. DW = deep work hours.
struct Discipline: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var code: String = ""
    var name: String = ""
    var isNumber: Bool = false     // false = did / didn't, true = a count or hours
    var target: String = ""        // e.g. "3" hours, "1" call
}

struct WeekPlan: Codable, Hashable {
    var weeklyPlan: String = ""            // free note: how I'm attacking the week
    var valuesPlan: String = ""            // free note: mental-health practices etc.
    var outcomes: [TaskItem] = []          // the things that must get done this week
    var values: [TaskItem] = []            // value emphases / habits, ticked per day

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weeklyPlan = try c.decodeIfPresent(String.self, forKey: .weeklyPlan) ?? ""
        valuesPlan = try c.decodeIfPresent(String.self, forKey: .valuesPlan) ?? ""
        outcomes = try c.decodeIfPresent([TaskItem].self, forKey: .outcomes) ?? []
        values = try c.decodeIfPresent([TaskItem].self, forKey: .values) ?? []
    }
}

struct CoreDoc: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable { case values, career, personal, ideas, tasks }
    var id: UUID = UUID()
    var kind: Kind
    var title: String
    var text: String = ""
    var updated: Date = Date()
}

struct SystemDocs: Codable {
    var root: String = ""
    var docs: [CoreDoc] = [
        CoreDoc(kind: .values, title: "Values", text: "Roles I play, and the values by which I try to live each one.\n\n"),
        CoreDoc(kind: .career, title: "Career strategic plan", text: "Current thoughts, experimental systems and plans for my working life, true to my values.\n\n"),
        CoreDoc(kind: .personal, title: "Personal strategic plan", text: "Current thoughts and plans for life outside work, true to my values.\n\n"),
        CoreDoc(kind: .ideas, title: "Ideas", text: "Idea notebook. Reviewed at least once a semester.\n\n"),
        CoreDoc(kind: .tasks, title: "Tasks", text: "Captured tasks, processed from the daily Collection at shutdown.\n\n")
    ]
    var disciplines: [Discipline] = [
        Discipline(code: "DW", name: "Deep work hours", isNumber: true, target: "3")
    ]
    var weeks: [String: WeekPlan] = [:]
    var nextOverhaul: Date? = nil
    var tasks: [TaskItem] = []
    var defaultWorkStartHour: Int = 8    // the grid a fresh day starts with; any day can override (Settings, ⌘,)
    var defaultWorkEndHour: Int = 18

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = SystemDocs()
        root = try c.decodeIfPresent(String.self, forKey: .root) ?? ""
        docs = try c.decodeIfPresent([CoreDoc].self, forKey: .docs) ?? fresh.docs
        disciplines = try c.decodeIfPresent([Discipline].self, forKey: .disciplines) ?? fresh.disciplines
        weeks = try c.decodeIfPresent([String: WeekPlan].self, forKey: .weeks) ?? [:]
        nextOverhaul = try c.decodeIfPresent(Date.self, forKey: .nextOverhaul)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        defaultWorkStartHour = try c.decodeIfPresent(Int.self, forKey: .defaultWorkStartHour) ?? 8
        defaultWorkEndHour = try c.decodeIfPresent(Int.self, forKey: .defaultWorkEndHour) ?? 18
        // migrate the old free-text Tasks document into items, once
        if tasks.isEmpty, let i = docs.firstIndex(where: { $0.kind == .tasks }) {
            let lines = docs[i].text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            tasks = lines.filter { !$0.isEmpty && !$0.hasPrefix("—") && !$0.hasPrefix("Captured tasks,") }.map { TaskItem(text: $0) }
            docs[i].text = ""
        }
    }
}

// MARK: - Store

/// Commands issued from menus / hotkeys that a specific page has to carry out.
enum PendingCommand: Equatable {
    case newBlock, deleteBlock, importEvents, pushPlan, focusCollection, reconcileCalendar
    case primaryAction      // ⌘↩ in Focus: the next step of the selected session
    case newSession         // ⇧⌘N: a session for the next free deep block, or standalone
}

final class Store: ObservableObject {
    @Published var plans: [String: DayPlan] = [:] { didSet { save() } }
    @Published var system: SystemDocs = SystemDocs() { didSet { saveSystem() } }
    @Published var pending: PendingCommand? = nil
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var tab: Int = 0          // 0 Day, 1 Week, 2 Systems — ordered by time horizon
    @Published var focusMode = false     // a Work Cycles session has taken over the window
    @Published var showShutdown = false  // the end-of-day sheet
    @Published var showPalette = false   // command palette (⌘P)
    @Published var focusSessionID: UUID? = nil   // the session Focus shows (menus and the palette drive it too)
    @Published var focusStage: Int = 0           // 0 Prepare, 1 Work, 2 Debrief
    @Published var formFocusTick: Int = 0        // bumped to put keyboard focus in the current step's first field

    /// Ask the Focus form to take keyboard focus once the next step has rendered.
    func requestFormFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.formFocusTick += 1 }
    }
    private var undoStack: [(key: String, plan: DayPlan)] = []
    private var redoStack: [(key: String, plan: DayPlan)] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Call before any block edit. Keeps the last 50 states of the day.
    func snapshot() {
        undoStack.append((selectedKey, today))
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
        objectWillChange.send()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append((last.key, plans[last.key] ?? DayPlan()))
        plans[last.key] = last.plan
        if last.key != selectedKey, let d = Store.keyFormatter.date(from: last.key) { selectedDate = d }
        pending = .reconcileCalendar
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((next.key, plans[next.key] ?? DayPlan()))
        plans[next.key] = next.plan
        if next.key != selectedKey, let d = Store.keyFormatter.date(from: next.key) { selectedDate = d }
        pending = .reconcileCalendar
    }
    @Published var systemsPage: String = "week"   // which Systems page to open (set by palette / links)
    @Published var appearance: Appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance"); appearance.apply() }
    }

    private let fileURL: URL
    private let systemURL: URL
    private var loaded = false

    init() {
        // DEEPCYCLES_DATA_DIR points a test run at a scratch folder instead of the real data.
        let dir = ProcessInfo.processInfo.environment["DEEPCYCLES_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DeepCycles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("plans.json")
        systemURL = dir.appendingPathComponent("system.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: DayPlan].self, from: data) {
            plans = decoded
        }
        if let data = try? Data(contentsOf: systemURL),
           let decoded = try? JSONDecoder().decode(SystemDocs.self, from: data) {
            system = decoded
        }
        loaded = true
    }

    // MARK: Weeks

    static func weekKey(for date: Date) -> String {
        let c = Calendar(identifier: .iso8601)
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
    }

    var selectedWeekKey: String { Store.weekKey(for: selectedDate) }

    var thisWeek: WeekPlan {
        get { system.weeks[selectedWeekKey] ?? WeekPlan() }
        set { system.weeks[selectedWeekKey] = newValue }
    }

    func doc(_ kind: CoreDoc.Kind) -> Binding<String> {
        Binding(
            get: { self.system.docs.first { $0.kind == kind }?.text ?? "" },
            set: { new in
                if let i = self.system.docs.firstIndex(where: { $0.kind == kind }) {
                    self.system.docs[i].text = new
                    self.system.docs[i].updated = Date()
                }
            }
        )
    }

    /// Shutdown "full capture": move today's captured items into the task list.
    /// Items already ticked off are dropped; the rest are trusted to the list.
    func processCollection() {
        let open = today.captured.filter { !$0.done && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        system.tasks.insert(contentsOf: open, at: 0)
        today.captured = []
    }

    var openTasks: [TaskItem] { system.tasks.filter { !$0.done } }

    /// Looks in the task list first, then in every week's outcomes.
    func task(_ id: UUID) -> TaskItem? {
        if let t = system.tasks.first(where: { $0.id == id }) { return t }
        for w in system.weeks.values { if let t = w.outcomes.first(where: { $0.id == id }) { return t } }
        return nil
    }

    /// Daily tick for a values-plan habit, stored alongside disciplines under a "v:" key.
    func valueDone(_ id: UUID, on date: Date) -> Bool { plan(for: date).disciplineLog["v:\(id.uuidString)"] == "1" }
    func setValueDone(_ id: UUID, on date: Date, _ done: Bool) {
        var p = plan(for: date)
        p.disciplineLog["v:\(id.uuidString)"] = done ? "1" : "0"
        plans[Store.key(for: date)] = p
    }

    /// Sessions in the order of the day: by their block's start, else creation time.
    func orderedSessions(_ plan: DayPlan) -> [CycleSession] {
        plan.sessions.sorted { a, b in
            let ta = plan.blocks.first { $0.id == a.blockID }?.start ?? a.created
            let tb = plan.blocks.first { $0.id == b.blockID }?.start ?? b.created
            return ta < tb
        }
    }

    /// All sessions across the last `days` days, newest first, for review.
    func sessionLog(days: Int = 30) -> [(date: Date, block: TimeBlock?, session: CycleSession)] {
        var out: [(Date, TimeBlock?, CycleSession)] = []
        for (key, plan) in plans {
            guard let d = Store.keyFormatter.date(from: key), d > Date().addingTimeInterval(-Double(days) * 86400) else { continue }
            for s in orderedSessions(plan) { out.append((d, plan.blocks.first { $0.id == s.blockID }, s)) }
        }
        return out.sorted { $0.0 == $1.0 ? $0.2.created > $1.2.created : $0.0 > $1.0 }.map { (date: $0.0, block: $0.1, session: $0.2) }
    }

    /// Arrow navigation: a week at a time in week view, otherwise a day.
    func shiftPeriod(_ direction: Int) {
        shiftDay(direction * (tab == 1 ? 7 : 1))
    }

    func shiftDay(_ days: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
    }

    private func saveSystem() {
        guard loaded else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(system) { try? data.write(to: systemURL, options: .atomic) }
    }

    static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String { keyFormatter.string(from: date) }

    var selectedKey: String { Store.key(for: selectedDate) }

    /// The plan for the selected day (created on first write).
    var today: DayPlan {
        get { plans[selectedKey] ?? freshDay() }
        set { plans[selectedKey] = newValue }
    }

    func plan(for date: Date) -> DayPlan { plans[Store.key(for: date)] ?? freshDay() }

    /// An empty day with the hours from Settings.
    func freshDay() -> DayPlan {
        var p = DayPlan()
        p.workStartHour = system.defaultWorkStartHour
        p.workEndHour = max(system.defaultWorkStartHour + 1, system.defaultWorkEndHour)
        return p
    }

    func session(forBlock id: UUID) -> CycleSession? {
        today.sessions.last { $0.blockID == id }
    }

    /// The deep-work block that contains `now` on the selected day, if any.
    func currentDeepBlock(now: Date = Date()) -> TimeBlock? {
        guard Calendar.current.isDate(now, inSameDayAs: selectedDate) else { return nil }
        return today.blocks.first { $0.kind == .deep && $0.start <= now && now < $0.end }
    }

    private func save() {
        guard loaded else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(plans) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// Combine the selected day with an hour/minute.
    func time(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate) ?? selectedDate
    }
}

// MARK: - Helpers

func mmss(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%02d:%02d", s / 60, s % 60)
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
    func rounded(toMinutes m: Int) -> Date {
        let interval = TimeInterval(m * 60)
        return Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / interval).rounded() * interval)
    }
}
