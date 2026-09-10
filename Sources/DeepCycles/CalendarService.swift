import Foundation
import EventKit
import Combine

enum CalendarError: LocalizedError {
    case notAuthorized, noTargetCalendar
    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Calendar access not granted. Enable it in System Settings → Privacy & Security → Calendars."
        case .noTargetCalendar: return "Pick a target calendar first."
        }
    }
}

@MainActor
final class CalendarService: ObservableObject {
    let store = EKEventStore()

    @Published var authorized = false
    @Published var calendars: [EKCalendar] = []
    @Published var lastError: String? = nil
    @Published var autoSync: Bool = UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSync, forKey: "autoSync") }
    }
    @Published var targetCalendarID: String = UserDefaults.standard.string(forKey: "targetCalendarID") ?? "" {
        didSet { UserDefaults.standard.set(targetCalendarID, forKey: "targetCalendarID") }
    }

    var targetCalendar: EKCalendar? {
        targetCalendarID.isEmpty ? nil : store.calendar(withIdentifier: targetCalendarID)
    }

    func requestAccess() async {
        do {
            let ok: Bool
            if #available(macOS 14.0, *) {
                ok = try await store.requestFullAccessToEvents()
            } else {
                ok = try await store.requestAccess(to: .event)
            }
            authorized = ok
            if ok { refreshCalendars() } else { lastError = CalendarError.notAuthorized.errorDescription }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshCalendars() {
        calendars = store.calendars(for: .event).sorted { $0.title.lowercased() < $1.title.lowercased() }
        let valid = calendars.contains { $0.calendarIdentifier == targetCalendarID }
        if !valid {
            // Prefer an existing "Time Blocks" calendar, else the system default.
            if let tb = calendars.first(where: { $0.title == "Time Blocks" && $0.allowsContentModifications }) {
                targetCalendarID = tb.calendarIdentifier
            } else {
                targetCalendarID = store.defaultCalendarForNewEvents?.calendarIdentifier ?? ""
            }
        }
    }

    /// Non-all-day events across every calendar for the given day.
    func events(on day: Date) -> [EKEvent] {
        guard authorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Calendar events as ghost blocks, clamped to the day so multi-day events
    /// don't paint a bar from the top of the grid. Our own pushed blocks are excluded.
    func ghosts(on day: Date) -> [TimeBlock] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? day
        return events(on: day)
            .filter { e in !BlockKind.allCases.contains { e.title?.hasPrefix($0.emoji) ?? false } }
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
    func push(_ block: TimeBlock) throws -> String {
        guard authorized else { throw CalendarError.notAuthorized }
        guard let target = targetCalendar else { throw CalendarError.noTargetCalendar }
        let event: EKEvent
        if let id = block.eventID, let existing = store.event(withIdentifier: id) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = target
        }
        event.title = "\(block.kind.emoji) \(block.title)"
        event.startDate = block.start
        event.endDate = block.end
        event.notes = block.notes.isEmpty ? "Time block · \(block.kind.label) · DeepCycles" : block.notes
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    func remove(eventID: String) {
        guard let event = store.event(withIdentifier: eventID) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    /// Makes a dedicated "Time Blocks" calendar and selects it. Google accounts
    /// refuse calendar creation from apps, so we fall back to iCloud, then On My Mac.
    func createTimeBlocksCalendar() {
        guard authorized else { lastError = CalendarError.notAuthorized.errorDescription; return }
        var candidates: [EKSource] = []
        if let s = store.defaultCalendarForNewEvents?.source { candidates.append(s) }
        candidates += store.sources.filter { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
        candidates += store.sources.filter { $0.sourceType == .calDAV }
        candidates += store.sources.filter { $0.sourceType == .local }
        var seen = Set<String>()
        var lastFailure = "no calendar account allows it"
        for src in candidates where seen.insert(src.sourceIdentifier).inserted {
            let cal = EKCalendar(for: .event, eventStore: store)
            cal.title = "Time Blocks"
            cal.source = src
            do {
                try store.saveCalendar(cal, commit: true)
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
    @Published var createdOn: String? = nil
}
