import Foundation
import EventKit
import Combine

package enum CalendarError: LocalizedError {
    case notAuthorized, noTargetCalendar

    package var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Calendar access not granted. Enable it in System Settings → Privacy & Security → Calendars."
        case .noTargetCalendar: return "Pick a target calendar first."
        }
    }
}

/// EventKit read/write: the day's events as ghost blocks, and the app's blocks pushed to one
/// target calendar. Sync preferences are in UserDefaults.
@MainActor
package final class CalendarService: ObservableObject {
    package let eventStore = EKEventStore()

    @Published package var authorized = false
    @Published package var calendars: [EKCalendar] = []
    @Published package var lastError: String? = nil
    @Published package var createdOn: String? = nil
    @Published package var autoSync: Bool = UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSync, forKey: "autoSync") }
    }
    @Published package var targetCalendarID: String = UserDefaults.standard.string(forKey: "targetCalendarID") ?? "" {
        didSet { UserDefaults.standard.set(targetCalendarID, forKey: "targetCalendarID") }
    }

    package init() {}

    package var targetCalendar: EKCalendar? {
        targetCalendarID.isEmpty ? nil : eventStore.calendar(withIdentifier: targetCalendarID)
    }

    package func requestAccess() async {
        do {
            let ok = try await eventStore.requestFullAccessToEvents()
            authorized = ok
            if ok { refreshCalendars() } else { lastError = CalendarError.notAuthorized.errorDescription }
        } catch {
            lastError = error.localizedDescription
        }
    }

    package func refreshCalendars() {
        calendars = eventStore.calendars(for: .event).sorted { $0.title.lowercased() < $1.title.lowercased() }
        let valid = calendars.contains { $0.calendarIdentifier == targetCalendarID }
        if !valid {
            // Prefer an existing "Time Blocks" calendar, else the system default.
            if let tb = calendars.first(where: { $0.title == "Time Blocks" && $0.allowsContentModifications }) {
                targetCalendarID = tb.calendarIdentifier
            } else {
                targetCalendarID = eventStore.defaultCalendarForNewEvents?.calendarIdentifier ?? ""
            }
        }
    }

    /// Non-all-day events across every calendar for the given day.
    package func events(on day: Date) -> [EKEvent] {
        guard authorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Calendar events as ghost blocks, clamped to the day so multi-day events
    /// don't paint a bar from the top of the grid. Our own pushed blocks are excluded.
    package func ghosts(on day: Date) -> [TimeBlock] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? day
        return events(on: day)
            .filter { !BlockKind.isOwnEvent($0.title) }
            .filter { $0.endDate.timeIntervalSince($0.startDate) < 20 * 3600 }   // "all day"-ish timed events
            .map { e in
                var b = TimeBlock()
                b.title = e.title ?? "Event"
                b.start = max(e.startDate, dayStart)
                b.end = min(e.endDate, dayEnd)
                b.kind = .meeting
                b.eventID = e.eventIdentifier
                b.fromCalendar = true
                return b
            }
            .filter { $0.minutes > 0 }
    }

    /// Creates or updates the calendar event for a block. Returns the event identifier.
    @discardableResult
    package func push(_ block: TimeBlock) throws -> String {
        guard authorized else { throw CalendarError.notAuthorized }
        guard let target = targetCalendar else { throw CalendarError.noTargetCalendar }
        let event: EKEvent
        if let id = block.eventID, let existing = eventStore.event(withIdentifier: id) {
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
            event.calendar = target
        }
        event.title = "\(block.kind.emoji) \(block.title)"
        event.startDate = block.start
        event.endDate = block.end
        event.notes = block.notes.isEmpty ? "Time block · \(block.kind.label) · DeepCycles" : block.notes
        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    package func remove(eventID: String) {
        guard let event = eventStore.event(withIdentifier: eventID) else { return }
        try? eventStore.remove(event, span: .thisEvent, commit: true)
    }

    /// Makes a dedicated "Time Blocks" calendar and selects it. Google accounts
    /// refuse calendar creation from apps, so we fall back to iCloud, then On My Mac.
    package func createTimeBlocksCalendar() {
        guard authorized else { lastError = CalendarError.notAuthorized.errorDescription; return }
        var candidates: [EKSource] = []
        if let s = eventStore.defaultCalendarForNewEvents?.source { candidates.append(s) }
        candidates += eventStore.sources.filter { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
        candidates += eventStore.sources.filter { $0.sourceType == .calDAV }
        candidates += eventStore.sources.filter { $0.sourceType == .local }
        var seen = Set<String>()
        var lastFailure = "no calendar account allows it"
        for src in candidates where seen.insert(src.sourceIdentifier).inserted {
            let cal = EKCalendar(for: .event, eventStore: eventStore)
            cal.title = "Time Blocks"
            cal.source = src
            do {
                try eventStore.saveCalendar(cal, commit: true)
                refreshCalendars()
                targetCalendarID = cal.calendarIdentifier
                lastError = nil
                createdOn = src.title
                return
            } catch {
                lastFailure = error.localizedDescription
            }
        }
        lastError = "Couldn't create a calendar (\(lastFailure)). Make one named “Time Blocks” in Calendar.app or Google Calendar, then refresh."
    }
}
