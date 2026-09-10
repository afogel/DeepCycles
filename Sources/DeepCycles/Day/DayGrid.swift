import SwiftUI
import AppKit
import DeepCyclesCore

// MARK: - Day grid: one timeline, ghosts, drag to create, move, resize, side-by-side conflicts

struct DayGrid: View {
    let startHour: Int
    let endHour: Int
    let date: Date
    let ghosts: [TimeBlock]
    let blocks: [TimeBlock]
    let sessions: [CycleSession]
    let selectedID: UUID?
    let draft: TimeBlock?
    let editingID: UUID?
    var focus: FocusState<PlannerView.Field?>.Binding
    let onTapBlock: (TimeBlock) -> Void
    let onTapGhost: (TimeBlock) -> Void
    let onCreate: (Date, Date) -> Void
    let onMoveResize: (UUID, Date, Date) -> Void
    let onMoveSelection: (Int) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var dragRange: (start: Date, end: Date)? = nil
    @State private var adjust: (id: UUID, dStart: Int, dEnd: Int)? = nil   // live move/resize, in minutes

    private let ptPerMinute: CGFloat = 1.5
    private let gap: CGFloat = 3
    private var totalMinutes: Int { max(60, (endHour - startHour) * 60) }
    private var height: CGFloat { CGFloat(totalMinutes) * ptPerMinute }
    private var dayStart: Date { Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: date) ?? date }
    private var dayEnd: Date { dayStart.addingTimeInterval(TimeInterval(totalMinutes * 60)) }

    private var gridFocused: Bool { focus.wrappedValue == .grid }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: Space.m) {
                hourLabels
                timeline
            }
            .frame(height: height + Space.m)
            .padding(Space.xl)
        }
        .background(Theme.paper)
        // The grid is a Tab stop: ↑↓ walk the blocks, ↩ edits the selected one, ⌫ deletes it.
        .focusable()
        .focused(focus, equals: .grid)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { onMoveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { onMoveSelection(1); return .handled }
        .onKeyPress(.return) {
            guard selectedID != nil else { return .ignored }
            onEdit()
            return .handled
        }
        .onDeleteCommand { if selectedID != nil { onDelete() } }
        .accessibilityLabel("Day grid")
    }

    private var base: some View { Color.clear.frame(maxWidth: .infinity).frame(height: height) }

    private var hourLabels: some View {
        base.frame(width: 40)
            .overlay(alignment: .topTrailing) {
                ForEach(0..<(totalMinutes / 60), id: \.self) { i in
                    Text(String(format: "%02d", startHour + i))
                        .font(.system(size: 12, weight: .medium, design: .serif))
                        .foregroundColor(Theme.inkFaint)
                        .frame(height: 14)
                        .offset(y: CGFloat(i * 60) * ptPerMinute - 7)
                }
            }
    }

    /// Blocks with any in-progress move/resize applied, and the inspector's
    /// unsaved edits shown in place of the block being edited.
    private var liveBlocks: [TimeBlock] {
        blocks.map { b in
            if let e = editingID, e == b.id, let d = draft, adjust == nil {
                var m = b; m.title = d.title; m.kind = d.kind; m.start = d.start; m.end = d.end; return m
            }
            guard let a = adjust, a.id == b.id else { return b }
            var m = b
            m.start = b.start.addingTimeInterval(TimeInterval(a.dStart * 60))
            m.end = b.end.addingTimeInterval(TimeInterval(a.dEnd * 60))
            return m
        }
    }

    private var timeline: some View {
        let live = liveBlocks
        let placement = packOverlaps(ghosts + live)
        return base
            .overlay(alignment: .top) { rules }
            .overlay(alignment: .top) {
                if blocks.isEmpty && draft == nil && dragRange == nil {
                    Text("Drag across the hours you want to block, or press ⌘N.")
                        .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                        .padding(.top, Space.l)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .local)
                    .onChanged { g in
                        let a = time(at: g.startLocation.y), b = time(at: g.location.y)
                        let lo = min(a, b), hi = max(a, b)
                        dragRange = (lo, max(hi, lo.addingTimeInterval(15 * 60)))
                    }
                    .onEnded { _ in
                        if let r = dragRange { onCreate(r.start, r.end) }
                        dragRange = nil
                    }
            )
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    ForEach(ghosts) { g in
                        let p = placement[g.id] ?? LanePlacement(col: 0, cols: 1)
                        GhostCard(block: g)
                            .frame(width: colWidth(geo.size.width, p), height: cardHeight(g))
                            .offset(x: colX(geo.size.width, p), y: yOffset(g.start) + 1)
                            .onTapGesture { onTapGhost(g) }
                    }
                    ForEach(live) { item in
                        let p = placement[item.id] ?? LanePlacement(col: 0, cols: 1)
                        BlockCard(block: item, selected: item.id == selectedID, session: sessions.last { $0.blockID == item.id },
                                  keyboard: gridFocused && item.id == selectedID)
                            .frame(width: colWidth(geo.size.width, p), height: cardHeight(item))
                            .overlay(alignment: .bottom) { resizeHandle(for: item) }
                            .offset(x: colX(geo.size.width, p), y: yOffset(item.start) + 1)
                            .onTapGesture { onTapBlock(item) }
                            .gesture(moveGesture(for: item))
                            .zIndex(adjust?.id == item.id ? 2 : 1)
                    }
                }
            }
            .overlay(alignment: .top) {
                if let r = dragRange {
                    preview(title: nil, kind: .deep, start: r.start, end: r.end)
                } else if let d = draft, editingID == nil {
                    preview(title: d.title, kind: d.kind, start: d.start, end: d.end)
                }
            }
            .overlay(alignment: .top) { nowLine }
            .clipped()
            .focusRing(gridFocused && selectedID == nil, shape: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
    }

    // MARK: Move & resize

    private func moveGesture(for item: TimeBlock) -> some Gesture {
        let original = blocks.first { $0.id == item.id } ?? item
        return DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { g in
                var d = snap(g.translation.height)
                // keep the block inside the working day
                let lo = Int(dayStart.timeIntervalSince(original.start) / 60)
                let hi = Int(dayEnd.timeIntervalSince(original.end) / 60)
                d = max(lo, min(hi, d))
                adjust = (item.id, d, d)
            }
            .onEnded { _ in commitAdjust(original) }
    }

    private func resizeHandle(for item: TimeBlock) -> some View {
        let original = blocks.first { $0.id == item.id } ?? item
        return Rectangle().fill(Color.clear)
            .frame(height: 10)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { g in
                        var d = snap(g.translation.height)
                        let minEnd = -(original.minutes - 15)
                        let maxEnd = Int(dayEnd.timeIntervalSince(original.end) / 60)
                        d = max(minEnd, min(maxEnd, d))
                        adjust = (item.id, 0, d)
                    }
                    .onEnded { _ in commitAdjust(original) }
            )
    }

    private func commitAdjust(_ original: TimeBlock) {
        if let a = adjust, a.dStart != 0 || a.dEnd != 0 {
            onMoveResize(original.id,
                         original.start.addingTimeInterval(TimeInterval(a.dStart * 60)),
                         original.end.addingTimeInterval(TimeInterval(a.dEnd * 60)))
        }
        adjust = nil
    }

    private func snap(_ dy: CGFloat) -> Int { Int((dy / ptPerMinute / 15).rounded()) * 15 }

    // MARK: Geometry

    private func colWidth(_ total: CGFloat, _ p: LanePlacement) -> CGFloat { (total - gap * CGFloat(p.cols - 1)) / CGFloat(p.cols) }
    private func colX(_ total: CGFloat, _ p: LanePlacement) -> CGFloat { CGFloat(p.col) * (colWidth(total, p) + gap) }
    private func cardHeight(_ b: TimeBlock) -> CGFloat { max(20, CGFloat(b.minutes) * ptPerMinute - 3) }

    private func preview(title: String?, kind: BlockKind, start: Date, end: Date) -> some View {
        let mins = max(15, Int(end.timeIntervalSince(start) / 60))
        return VStack(alignment: .leading, spacing: 2) {
            Text(title?.isEmpty == false ? title! : "\(start.shortTime) – \(end.shortTime)")
                .font(TypeScale.label).foregroundColor(kind.color)
            if title?.isEmpty == false {
                Text("\(start.shortTime) – \(end.shortTime)").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(20, CGFloat(mins) * ptPerMinute - 3))
        .background(kind.color.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundColor(kind.color))
        .offset(y: yOffset(start) + 1)
        .allowsHitTesting(false)
    }

    private var rules: some View {
        Canvas { ctx, size in
            for i in 0...(totalMinutes / 30) {
                let y = CGFloat(i * 30) * ptPerMinute + 0.5
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                if i % 2 == 0 {
                    ctx.stroke(p, with: .color(Theme.rule), lineWidth: 1)
                } else {
                    ctx.stroke(p, with: .color(Theme.ruleFaint), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var nowLine: some View {
        if Calendar.current.isDateInToday(date) {
            let y = yOffset(Date())
            if y > 0 && y < height {
                HStack(spacing: Space.xs) {
                    Text(Date().shortTime).font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundColor(Theme.nowLine)
                    Circle().fill(Theme.nowLine).frame(width: 6, height: 6)
                    Rectangle().fill(Theme.nowLine).frame(height: 1.5)
                }
                .frame(height: 12)
                .offset(y: y - 6)
                .allowsHitTesting(false)
            }
        }
    }

    private func time(at y: CGFloat) -> Date {
        let mins = Int((max(0, min(y, height)) / ptPerMinute / 15).rounded()) * 15
        return dayStart.addingTimeInterval(TimeInterval(mins * 60))
    }

    private func yOffset(_ time: Date) -> CGFloat {
        let mins = time.timeIntervalSince(dayStart) / 60
        return CGFloat(min(max(mins, 0), Double(totalMinutes))) * ptPerMinute
    }
}

/// A calendar event that isn't a block yet: outlined, quiet, one click to adopt.
struct GhostCard: View {
    let block: TimeBlock
    @State private var hover = false
    var body: some View {
        HStack(alignment: .top) {
            Text(block.title).font(TypeScale.body).foregroundColor(Theme.inkFaint).lineLimit(1)
            Spacer(minLength: 0)
            Text(hover ? "Add as block" : "\(block.start.shortTime)–\(block.end.shortTime)")
                .font(TypeScale.caption.monospacedDigit()).foregroundColor(hover ? Theme.ink : Theme.inkFaint)
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.meeting.opacity(hover ? 0.10 : 0.04))
        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundColor(Theme.meeting.opacity(0.6)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct BlockCard: View {
    let block: TimeBlock
    let selected: Bool
    let session: CycleSession?
    var keyboard: Bool = false     // selected and the grid has keyboard focus
    @EnvironmentObject var store: Store
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(block.kind.color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(block.title).font(TypeScale.label).foregroundColor(Theme.ink).lineLimit(2)
                    Spacer(minLength: 0)
                    Text("\(block.start.shortTime)–\(block.end.shortTime)")
                        .font(TypeScale.caption.monospacedDigit()).foregroundColor(Theme.inkFaint)
                }
                if !block.taskIDs.isEmpty, block.minutes >= 30 {
                    let tasks = block.taskIDs.compactMap { store.task($0) }
                    ForEach(tasks.prefix(max(1, block.minutes / 20))) { t in
                        HStack(spacing: 4) {
                            Image(systemName: t.done ? "checkmark.circle.fill" : "circle").font(.system(size: 9))
                                .foregroundColor(t.done ? Theme.breakC : Theme.inkFaint)
                            Text(t.text).font(TypeScale.caption).foregroundColor(t.done ? Theme.inkFaint : Theme.ink).lineLimit(1)
                        }
                    }
                } else if block.minutes >= 45, !block.notes.isEmpty {
                    Text(block.notes).font(TypeScale.caption).foregroundColor(Theme.inkFaint).lineLimit(block.minutes >= 90 ? 4 : 1)
                }
                if let s = session, block.minutes >= 40 {
                    HStack(spacing: 3) {
                        ForEach(0..<s.cycleCount, id: \.self) { i in
                            let c = i < s.cycles.count ? s.cycles[i].completed : nil
                            Capsule()
                                .fill(c == nil ? Theme.deep.opacity(0.25) : (c == .yes ? Theme.deep : Theme.deep.opacity(0.6)))
                                .frame(width: 14, height: 4)
                        }
                        Text("\(s.deepMinutes) min").font(.system(size: 10)).foregroundColor(Theme.inkFaint)
                    }
                }
            }
            .padding(.vertical, Space.xs).padding(.horizontal, Space.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(block.kind.color.opacity(selected ? 0.24 : (hover ? 0.20 : 0.15)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            .stroke(selected ? block.kind.color : Color.clear, lineWidth: 1.5))
        .focusRing(keyboard, shape: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
