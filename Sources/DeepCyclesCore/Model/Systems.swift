import Foundation

// MARK: - Core systems (Newport's root document)

/// A hard discipline tracked daily by a short metric code, e.g. DW = deep work hours.
package struct Discipline: Identifiable, Codable, Hashable {
    package var id: UUID = UUID()
    package var code: String = ""
    package var name: String = ""
    package var isNumber: Bool = false     // false = did / didn't, true = a count or hours
    package var target: String = ""        // e.g. "3" hours, "1" call

    package init(id: UUID = UUID(), code: String = "", name: String = "", isNumber: Bool = false, target: String = "") {
        self.id = id
        self.code = code
        self.name = name
        self.isNumber = isNumber
        self.target = target
    }

    /// Did a logged value meet the discipline: a number at or above the target (and above zero),
    /// or "1" for a did-it discipline.
    package func isHit(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if isNumber {
            let v = Double(value) ?? 0
            return v > 0 && v >= (Double(target) ?? 0)
        }
        return value == "1"
    }
}

package struct WeekPlan: Codable, Hashable {
    package var weeklyPlan: String = ""            // free note: how I'm attacking the week
    package var valuesPlan: String = ""            // free note: mental-health practices etc.
    package var outcomes: [TaskItem] = []          // the things that must get done this week
    package var values: [TaskItem] = []            // value emphases / habits, ticked per day

    package init() {}

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weeklyPlan = try c.decodeIfPresent(String.self, forKey: .weeklyPlan) ?? ""
        valuesPlan = try c.decodeIfPresent(String.self, forKey: .valuesPlan) ?? ""
        outcomes = try c.decodeIfPresent([TaskItem].self, forKey: .outcomes) ?? []
        values = try c.decodeIfPresent([TaskItem].self, forKey: .values) ?? []
    }

    /// Last week's plan carried forward: open outcomes only, habits unticked, fresh ids so the
    /// per-day ticks don't collide with the old week's.
    package func carriedForward() -> WeekPlan {
        var copy = self
        copy.outcomes = outcomes.filter { !$0.done }.map { var t = $0; t.id = UUID(); return t }
        copy.values = values.map { var t = $0; t.id = UUID(); t.done = false; return t }
        return copy
    }
}

package struct CoreDoc: Identifiable, Codable, Hashable {
    package enum Kind: String, Codable, CaseIterable { case values, career, personal, ideas, tasks }
    package var id: UUID = UUID()
    package var kind: Kind
    package var title: String
    package var text: String = ""
    package var updated: Date = Date()

    package init(id: UUID = UUID(), kind: Kind, title: String, text: String = "", updated: Date = Date()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.updated = updated
    }
}

package struct SystemDocs: Codable {
    package var root: String = ""
    package var docs: [CoreDoc] = [
        CoreDoc(kind: .values, title: "Values", text: "Roles I play, and the values by which I try to live each one.\n\n"),
        CoreDoc(kind: .career, title: "Career strategic plan", text: "Current thoughts, experimental systems and plans for my working life, true to my values.\n\n"),
        CoreDoc(kind: .personal, title: "Personal strategic plan", text: "Current thoughts and plans for life outside work, true to my values.\n\n"),
        CoreDoc(kind: .ideas, title: "Ideas", text: "Idea notebook. Reviewed at least once a semester.\n\n"),
        CoreDoc(kind: .tasks, title: "Tasks", text: "Captured tasks, processed from the daily Collection at shutdown.\n\n")
    ]
    package var disciplines: [Discipline] = [
        Discipline(code: "DW", name: "Deep work hours", isNumber: true, target: "3")
    ]
    package var weeks: [String: WeekPlan] = [:]
    package var nextOverhaul: Date? = nil
    package var tasks: [TaskItem] = []
    package var defaultWorkStartHour: Int = 8    // the grid a fresh day starts with; any day can override (Settings, ⌘,)
    package var defaultWorkEndHour: Int = 18

    package init() {}

    package init(from decoder: Decoder) throws {
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

    package func doc(_ kind: CoreDoc.Kind) -> CoreDoc? { docs.first { $0.kind == kind } }

    package var openTasks: [TaskItem] { tasks.filter { !$0.done } }
}
