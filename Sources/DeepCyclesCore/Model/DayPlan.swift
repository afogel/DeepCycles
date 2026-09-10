import Foundation

package struct Metric: Identifiable, Codable, Hashable {
    package var id: UUID = UUID()
    package var name: String
    package var value: String

    package init(id: UUID = UUID(), name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }
}

/// One day: its blocks, its cycle sessions, the shutdown metrics and the thoughts captured
/// during the day. Keyed by "yyyy-MM-dd" in plans.json (see `DateKeys`).
package struct DayPlan: Codable {
    package var blocks: [TimeBlock] = []
    package var sessions: [CycleSession] = []
    package var metrics: [Metric] = []
    /// Discipline id → logged value: "1" / "0" for did-it disciplines, a number for the others;
    /// values-plan habits under "v:<id>". Read and written through the accessors below.
    package var disciplineLog: [String: String] = [:]
    package var collection: String = ""          // legacy free text; migrated into `captured`
    package var captured: [TaskItem] = []
    package var shutdownComplete: Bool = false
    package var workStartHour: Int = 8
    package var workEndHour: Int = 18

    package init() {}

    // Tolerant decoding so older plans.json files keep loading as fields are added.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try c.decodeIfPresent([TimeBlock].self, forKey: .blocks) ?? []
        sessions = try c.decodeIfPresent([CycleSession].self, forKey: .sessions) ?? []
        metrics = try c.decodeIfPresent([Metric].self, forKey: .metrics) ?? []
        disciplineLog = try c.decodeIfPresent([String: String].self, forKey: .disciplineLog) ?? [:]
        collection = try c.decodeIfPresent(String.self, forKey: .collection) ?? ""
        captured = try c.decodeIfPresent([TaskItem].self, forKey: .captured) ?? []
        if !collection.isEmpty {   // migrate old free text into items
            captured += collection.split(whereSeparator: \.isNewline)
                .map { TaskItem(text: String($0).trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.text.isEmpty }
            collection = ""
        }
        shutdownComplete = try c.decodeIfPresent(Bool.self, forKey: .shutdownComplete) ?? false
        workStartHour = try c.decodeIfPresent(Int.self, forKey: .workStartHour) ?? 8
        workEndHour = try c.decodeIfPresent(Int.self, forKey: .workEndHour) ?? 18
    }

    // MARK: Derived

    package var plannedMinutes: Int { blocks.reduce(0) { $0 + $1.minutes } }
    package var deepMinutesPlanned: Int { blocks.filter { $0.kind == .deep }.reduce(0) { $0 + $1.minutes } }
    /// Minutes actually worked, from the cycle timers.
    package var deepMinutesLogged: Int { sessions.reduce(0) { $0 + $1.deepMinutes } }

    package func session(forBlock id: UUID) -> CycleSession? {
        sessions.last { $0.blockID == id }
    }

    /// Sessions in the order of the day: by their block's start, else creation time.
    package var orderedSessions: [CycleSession] {
        sessions.sorted { a, b in
            let ta = blocks.first { $0.id == a.blockID }?.start ?? a.created
            let tb = blocks.first { $0.id == b.blockID }?.start ?? b.created
            return ta < tb
        }
    }

    // MARK: Disciplines and values

    /// The value logged for a discipline today, "" if none.
    package func discipline(_ id: UUID) -> String { disciplineLog[id.uuidString] ?? "" }
    package mutating func logDiscipline(_ id: UUID, _ value: String) { disciplineLog[id.uuidString] = value }

    package func disciplineDone(_ id: UUID) -> Bool { discipline(id) == "1" }
    package mutating func setDisciplineDone(_ id: UUID, _ done: Bool) { logDiscipline(id, done ? "1" : "0") }

    /// Daily tick for a values-plan habit.
    package func valueDone(_ id: UUID) -> Bool { disciplineLog["v:\(id.uuidString)"] == "1" }
    package mutating func setValueDone(_ id: UUID, _ done: Bool) { disciplineLog["v:\(id.uuidString)"] = done ? "1" : "0" }
}
