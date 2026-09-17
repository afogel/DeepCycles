import SwiftUI
import EventKit
import DeepCyclesCore

/// Everything known about one entry in the week grid: a calendar event (read back in full from
/// EventKit) or one of the plan's own blocks. Shown in a popover from the entry.
@MainActor
struct EventDetail: View {
    let block: TimeBlock
    let day: Date
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
    @EnvironmentObject var calendar: CalendarService

    private var event: EKEvent? { block.eventID.flatMap { calendar.event(withIdentifier: $0, on: day) } }

    var body: some View {
        let ev = event
        let start = ev?.startDate ?? block.start
        let end = ev?.endDate ?? block.end
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title(ev)).font(TypeScale.title).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Circle().fill(tint(ev)).frame(width: 8, height: 8)
                    Text(kindLine(ev)).font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                }
            }

            row("clock") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateLine(start, end))
                    Text(timeLine(start, end, allDay: ev?.isAllDay ?? false)).foregroundColor(Theme.inkFaint)
                }
            }

            if let ev {
                if let loc = clean(ev.location) { row("mappin.and.ellipse") { Text(loc).textSelection(.enabled) } }
                if let org = ev.organizer?.name, !org.isEmpty { row("person") { Text("Organised by \(org)") } }
                if let att = ev.attendees, !att.isEmpty { attendees(att) }
                if ev.hasRecurrenceRules { row("repeat") { Text("Repeats") } }
                if ev.status == .tentative { row("questionmark.circle") { Text("Tentative") } }
                if ev.status == .canceled { row("xmark.circle") { Text("Cancelled").foregroundColor(Theme.nowLine) } }
            }

            if let notes = clean(ev?.notes ?? block.notes) {
                row("text.alignleft") {
                    ScrollView(.vertical) {
                        Text(notes).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
            }

            if !block.fromCalendar { tasks }

            HStack(spacing: Space.s) {
                if let link = link(ev) {
                    Button("Open link") { NSWorkspace.shared.open(link) }.buttonStyle(QuietButtonStyle())
                }
                if let ev {
                    Button("Open in Calendar") { open(ev) }.buttonStyle(QuietButtonStyle())
                }
                Spacer(minLength: 0)
                Button("Go to day") {
                    store.selectedDate = Calendar.current.startOfDay(for: day)
                    ui.tab = .day
                }.buttonStyle(InkButtonStyle())
            }
            .padding(.top, 2)
        }
        .font(TypeScale.body).foregroundColor(Theme.ink)
        .padding(Space.l)
        .frame(width: 340)
        .background(Theme.paper)
    }

    // MARK: Pieces

    private func row<C: View>(_ symbol: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundColor(Theme.inkFaint)
                .frame(width: 14).padding(.top, 2)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func attendees(_ list: [EKParticipant]) -> some View {
        let shown = Array(list.prefix(8))
        let accepted = list.filter { $0.participantStatus == .accepted }.count
        return row("person.2") {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, p in
                    let mark = status(p)
                    HStack(spacing: 6) {
                        Image(systemName: mark.symbol).font(.system(size: 10)).foregroundColor(mark.color).frame(width: 12)
                        Text(name(p)).lineLimit(1)
                        if p.isCurrentUser { Text("you").font(TypeScale.caption).foregroundColor(Theme.inkFaint) }
                    }
                }
                if list.count > shown.count {
                    Text("+\(list.count - shown.count) more").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                }
                Text("\(list.count) invited · \(accepted) accepted").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }
        }
    }

    @ViewBuilder
    private var tasks: some View {
        let items = store.system.tasks.filter { block.taskIDs.contains($0.id) }
        if !items.isEmpty {
            row("checklist") {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(items) { t in
                        HStack(spacing: 6) {
                            Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10)).foregroundColor(t.done ? Theme.breakC : Theme.inkFaint).frame(width: 12)
                            Text(t.text).lineLimit(1).foregroundColor(t.done ? Theme.inkFaint : Theme.ink)
                                .struckThrough(t.done, text: t.text)
                        }
                    }
                }
            }
        }
    }

    // MARK: Text

    private func title(_ ev: EKEvent?) -> String {
        let t = ev?.title ?? block.title
        return t.isEmpty ? "Untitled" : t
    }

    private func tint(_ ev: EKEvent?) -> Color {
        if let ev, let cg = ev.calendar?.cgColor { return Color(cgColor: cg) }
        return block.kind.color
    }

    private func kindLine(_ ev: EKEvent?) -> String {
        if let ev {
            let cal = ev.calendar?.title ?? "Calendar"
            let source = ev.calendar?.source?.title
            let where_ = source.map { "\(cal) · \($0)" } ?? cal
            return block.fromCalendar ? where_ : "\(block.kind.label) · on \(where_)"
        }
        return block.fromCalendar ? "Calendar event" : block.kind.label
    }

    private func dateLine(_ start: Date, _ end: Date) -> String {
        let f: Date.FormatStyle = .dateTime.weekday(.wide).day().month(.wide)
        if Calendar.current.isDate(start, inSameDayAs: end) || end == Calendar.current.startOfDay(for: end) {
            return start.formatted(f)
        }
        return "\(start.formatted(f)) – \(end.formatted(f))"
    }

    private func timeLine(_ start: Date, _ end: Date, allDay: Bool) -> String {
        if allDay { return "All day" }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        return "\(start.shortTime) – \(end.shortTime) · \(duration(minutes))"
    }

    private func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    private func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private func name(_ p: EKParticipant) -> String {
        if let n = p.name, !n.isEmpty { return n }
        return p.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
    }

    private func status(_ p: EKParticipant) -> (symbol: String, color: Color) {
        switch p.participantStatus {
        case .accepted: return ("checkmark.circle.fill", Theme.breakC)
        case .declined: return ("xmark.circle", Theme.nowLine)
        case .tentative: return ("questionmark.circle", Theme.overflow)
        default: return ("circle", Theme.inkFaint)
        }
    }

    // MARK: Links

    /// The event's URL, else the first web link in its location or notes (meeting links live
    /// there); for the plan's own blocks, the first link in their notes.
    private func link(_ ev: EKEvent?) -> URL? {
        if let u = ev?.url, let scheme = u.scheme?.lowercased(), scheme.hasPrefix("http") { return u }
        let text = ev.map { [$0.location, $0.notes].compactMap { $0 }.joined(separator: "\n") } ?? block.notes
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .first { ($0.scheme?.lowercased() ?? "").hasPrefix("http") }
    }

    /// Calendar.app opens straight to the event through its `ical://ekevent/<id>` URL.
    private func open(_ ev: EKEvent) {
        let raw: String = ev.eventIdentifier ?? ""
        let id = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
        if !id.isEmpty, let u = URL(string: "ical://ekevent/\(id)?method=show&options=more") {
            NSWorkspace.shared.open(u)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
    }
}
