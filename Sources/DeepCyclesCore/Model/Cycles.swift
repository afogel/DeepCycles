import Foundation

// MARK: - Work Cycles (Ultraworking)

/// The REVIEW question "did you hit the target?". An unanswered cycle has none.
package enum TargetOutcome: String, Codable, CaseIterable, Identifiable {
    case yes = "Yes", half = "Half", no = "No"
    package var id: String { rawValue }
    package var label: String { rawValue }
}

package struct WorkCycle: Identifiable, Codable, Hashable {
    package var id: UUID = UUID()
    // PLAN
    package var goal: String = ""
    package var startPlan: String = ""
    package var hazards: String = ""
    package var energy: Int = 3
    package var morale: Int = 3
    // REVIEW
    package var completed: TargetOutcome? = nil
    package var noteworthy: String = ""
    package var distractions: String = ""
    package var improvements: String = ""
    package var workedSeconds: Int = 0

    package init() {}

    private enum CodingKeys: String, CodingKey {
        case id, goal, startPlan, hazards, energy, morale, completed, noteworthy, distractions, improvements, workedSeconds
    }

    // `completed` is stored as "Yes" / "Half" / "No" / "" so existing files keep their shape.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        startPlan = try c.decodeIfPresent(String.self, forKey: .startPlan) ?? ""
        hazards = try c.decodeIfPresent(String.self, forKey: .hazards) ?? ""
        energy = try c.decodeIfPresent(Int.self, forKey: .energy) ?? 3
        morale = try c.decodeIfPresent(Int.self, forKey: .morale) ?? 3
        completed = TargetOutcome(rawValue: try c.decodeIfPresent(String.self, forKey: .completed) ?? "")
        noteworthy = try c.decodeIfPresent(String.self, forKey: .noteworthy) ?? ""
        distractions = try c.decodeIfPresent(String.self, forKey: .distractions) ?? ""
        improvements = try c.decodeIfPresent(String.self, forKey: .improvements) ?? ""
        workedSeconds = try c.decodeIfPresent(Int.self, forKey: .workedSeconds) ?? 0
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(goal, forKey: .goal)
        try c.encode(startPlan, forKey: .startPlan)
        try c.encode(hazards, forKey: .hazards)
        try c.encode(energy, forKey: .energy)
        try c.encode(morale, forKey: .morale)
        try c.encode(completed?.rawValue ?? "", forKey: .completed)
        try c.encode(noteworthy, forKey: .noteworthy)
        try c.encode(distractions, forKey: .distractions)
        try c.encode(improvements, forKey: .improvements)
        try c.encode(workedSeconds, forKey: .workedSeconds)
    }
}

package struct CycleSession: Identifiable, Codable, Hashable {
    package var id: UUID = UUID()
    package var blockID: UUID? = nil
    package var title: String = "Work Cycles"
    package var created: Date = Date()
    package var cycleMinutes: Int = 30
    package var breakMinutes: Int = 10
    package var cycleCount: Int = 5
    // 1. Prepare
    package var accomplish: String = ""
    package var important: String = ""
    package var complete: String = ""
    package var risks: String = ""
    package var measurable: String = ""
    package var other: String = ""
    // 2. Work
    package var cycles: [WorkCycle] = []
    package var currentCycle: Int = 0
    // 3. Debrief
    package var gotDone: String = ""
    package var compare: String = ""
    package var boggedDown: String = ""
    package var wentWell: String = ""
    package var takeaways: String = ""
    package var finished: Bool = false

    package init() {}

    package var deepMinutes: Int { cycles.reduce(0) { $0 + $1.workedSeconds } / 60 }
    package var cyclesDone: Int { cycles.filter { $0.completed != nil }.count }
    package var isLastCycle: Bool { currentCycle >= cycleCount - 1 }

    /// The cycle being planned, worked or reviewed (an empty one if `cycles` is short).
    package var current: WorkCycle {
        cycles.indices.contains(currentCycle) ? cycles[currentCycle] : WorkCycle()
    }

    /// Anything happened in it yet: prepared, a cycle planned, worked or reviewed.
    package var hasStarted: Bool {
        !accomplish.isEmpty || cycles.contains { !$0.goal.isEmpty || $0.workedSeconds > 0 || $0.completed != nil }
    }

    /// Pad or trim `cycles` to `cycleCount`, and keep `currentCycle` in range.
    package mutating func ensureCycles() {
        while cycles.count < cycleCount { cycles.append(WorkCycle()) }
        if cycles.count > cycleCount { cycles.removeLast(cycles.count - cycleCount) }
        if currentCycle >= cycleCount { currentCycle = max(0, cycleCount - 1) }
    }

    /// Move on to the next cycle, if there is one.
    package mutating func advance() {
        if currentCycle < cycleCount - 1 { currentCycle += 1 }
    }

    /// A session sized to fit inside a deep-work block: as many cycle+break
    /// pairs as fit, dropping the trailing break. Short blocks get shorter cycles.
    package static func fitting(block: TimeBlock, cycleMinutes: Int = 30, breakMinutes: Int = 10) -> CycleSession {
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
