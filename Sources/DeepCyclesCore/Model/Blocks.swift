import Foundation

// MARK: - Time blocks (Cal Newport)

package enum BlockKind: String, Codable, CaseIterable, Identifiable {
    case deep, shallow, meeting, tasks, breakTime, overflow
    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .deep: return "Deep work"
        case .shallow: return "Shallow (email, admin)"
        case .meeting: return "Meeting / call"
        case .tasks: return "Task block"
        case .breakTime: return "Break / lunch"
        case .overflow: return "Overflow (conditional)"
        }
    }

    package var shortLabel: String {
        switch self {
        case .deep: return "Deep"
        case .shallow: return "Shallow"
        case .meeting: return "Meeting"
        case .tasks: return "Tasks"
        case .breakTime: return "Break"
        case .overflow: return "Overflow"
        }
    }

    /// Prefix of the calendar events the app writes; also how it recognises them on the way back in.
    package var emoji: String {
        switch self {
        case .deep: return "🔵"
        case .shallow: return "⚪️"
        case .meeting: return "🟣"
        case .tasks: return "🟠"
        case .breakTime: return "🟢"
        case .overflow: return "🟡"
        }
    }

    /// True for a calendar event title the app itself produced.
    package static func isOwnEvent(_ title: String?) -> Bool {
        guard let title else { return false }
        return allCases.contains { title.hasPrefix($0.emoji) }
    }
}

package struct TimeBlock: Identifiable, Codable, Hashable {
    package var id: UUID = UUID()
    package var title: String = ""
    package var start: Date = Date()
    package var end: Date = Date().addingTimeInterval(3600)
    package var kind: BlockKind = .deep
    package var notes: String = ""
    package var eventID: String? = nil      // EventKit identifier once pushed / imported
    package var fromCalendar: Bool = false  // imported from the calendar, not created here
    package var taskIDs: [UUID] = []        // tasks scheduled into this block

    package var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }

    package init() {}

    package init(title: String, start: Date, end: Date, kind: BlockKind = .deep, notes: String = "") {
        self.title = title
        self.start = start
        self.end = end
        self.kind = kind
        self.notes = notes
    }

    // Tolerant decoding so older plans.json files keep loading as fields are added.
    package init(from decoder: Decoder) throws {
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
package struct TaskItem: Identifiable, Codable, Hashable {
    package var id: UUID = UUID()
    package var text: String = ""
    package var done: Bool = false
    package var created: Date = Date()

    package init(id: UUID = UUID(), text: String = "", done: Bool = false, created: Date = Date()) {
        self.id = id
        self.text = text
        self.done = done
        self.created = created
    }
}
