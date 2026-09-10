import Foundation

/// The three pages, ordered by time horizon.
package enum Tab: Int, CaseIterable, Identifiable {
    case day, week, systems
    package var id: Int { rawValue }

    package var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .systems: return "Systems"
        }
    }
}

/// The three steps of a Work Cycles session.
package enum SessionStage: Int, CaseIterable, Identifiable {
    case prepare, work, debrief
    package var id: Int { rawValue }

    package var title: String {
        switch self {
        case .prepare: return "Prepare"
        case .work: return "Work"
        case .debrief: return "Debrief"
        }
    }
}

/// The pages inside Systems.
package enum SystemsPage: Hashable {
    case week, root, doc(CoreDoc.Kind), disciplines, sessions

    /// Sidebar order.
    package static let all: [SystemsPage] = [.week, .root] + CoreDoc.Kind.allCases.map { .doc($0) } + [.disciplines, .sessions]
}

/// User-selectable appearance. "System" follows macOS; "Dark" is the calm night palette.
package enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    package var id: String { rawValue }
    package var label: String { rawValue.capitalized }
}

/// Commands issued from menus or the palette that a specific page has to carry out. The page
/// clears the command once done; a page that appears later picks it up on appear.
package enum PendingCommand: Equatable {
    case newBlock, deleteBlock, importEvents, pushPlan, focusCollection, reconcileCalendar
    case primaryAction      // ⌘↩ in Focus: the next step of the selected session
    case newSession         // ⇧⌘N: a session for the next free deep block, or standalone
}
