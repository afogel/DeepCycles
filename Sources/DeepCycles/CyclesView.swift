import SwiftUI

@MainActor
struct CyclesView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine
    @State private var selectedID: UUID? = nil
    @State private var stage: Int = 0   // 0 Prepare, 1 Work, 2 Debrief

    var body: some View {
        HStack(spacing: 0) {
            sessionList.frame(width: 250).background(Theme.paperDeep)
            if let id = selectedID, store.today.sessions.contains(where: { $0.id == id }) {
                SessionView(session: binding(for: id), stage: $stage, dateKey: store.selectedKey)
            } else {
                emptyState
            }
        }
        .onAppear { syncSelection() }
        .onChange(of: store.today.sessions.count) { _ in syncSelection() }
        .onChange(of: engine.sessionID) { _ in syncSelection() }
        .onChange(of: store.selectedDate) { _ in selectedID = nil; syncSelection() }
        .onChange(of: store.pending) { cmd in
            guard cmd == .startCycle else { return }
            store.pending = nil
            guard !engine.isRunning, let id = selectedID,
                  let s = store.today.sessions.first(where: { $0.id == id }) else { return }
            stage = 1
            if let i = store.today.sessions.firstIndex(where: { $0.id == id }) {
                while store.today.sessions[i].cycles.count < s.cycleCount { store.today.sessions[i].cycles.append(WorkCycle()) }
            }
            engine.attach(sessionID: id, dateKey: store.selectedKey)
            engine.startWork(minutes: s.cycleMinutes)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No session yet").font(Theme.display(22)).foregroundColor(Theme.ink)
            Text("A session is one deep-work block executed as 30-minute cycles with 10-minute breaks.\nPick a deep block below, or start a standalone session.")
                .multilineTextAlignment(.center).foregroundColor(Theme.inkFaint).frame(maxWidth: 380)
            let deepBlocks = store.today.blocks.filter { $0.kind == .deep }
            if deepBlocks.isEmpty {
                Button("Plan a deep block first") { store.focusMode = false; store.tab = 0 }.buttonStyle(InkButtonStyle())
            } else {
                HStack {
                    ForEach(deepBlocks) { b in
                        Button("\(b.start.shortTime) \(b.title)") { create(from: b) }.buttonStyle(InkButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncSelection() {
        if let running = engine.sessionID, engine.sessionDateKey == store.selectedKey,
           store.today.sessions.contains(where: { $0.id == running }) {
            if selectedID != running { selectedID = running; stage = hasPrepared(running) ? 1 : 0 }
        } else if selectedID == nil {
            selectedID = store.today.sessions.last?.id
            stage = 0
        }
    }

    private func hasPrepared(_ id: UUID) -> Bool {
        guard let s = store.today.sessions.first(where: { $0.id == id }) else { return false }
        return !s.accomplish.isEmpty
    }

    private func binding(for id: UUID) -> Binding<CycleSession> {
        Binding(
            get: { store.today.sessions.first { $0.id == id } ?? CycleSession() },
            set: { new in
                if let i = store.today.sessions.firstIndex(where: { $0.id == id }) { store.today.sessions[i] = new }
            }
        )
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Sessions").padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    let ordered = store.orderedSessions(store.today)
                    let live = ordered.filter { !$0.finished }
                    let done = ordered.filter { $0.finished }
                    ForEach(live) { s in
                        sessionRow(s).onTapGesture { selectedID = s.id; stage = s.accomplish.isEmpty ? 0 : 1 }
                    }
                    if !done.isEmpty {
                        Text("Done today").font(TypeScale.caption).foregroundColor(Theme.inkFaint).padding(.top, 10).padding(.leading, 4)
                        ForEach(done) { s in
                            sessionRow(s).opacity(0.75).onTapGesture { selectedID = s.id; stage = 2 }
                        }
                    }
                    if ordered.isEmpty {
                        Text("Sessions live with their day; older ones are in Systems → Session log.")
                            .font(TypeScale.caption).foregroundColor(Theme.inkFaint).padding(4)
                    }
                }
                .padding(.horizontal, 12)
            }
            Spacer()
            let deepBlocks = store.today.blocks.filter { $0.kind == .deep && store.session(forBlock: $0.id) == nil }
            Menu {
                Button("Standalone session") { create(from: nil) }
                if !deepBlocks.isEmpty { Divider() }
                ForEach(deepBlocks) { b in
                    Button("\(b.start.shortTime)  \(b.title)  (\(b.minutes) min)") { create(from: b) }
                }
            } label: { Label("New session", systemImage: "plus") }
            .menuStyle(.borderlessButton)
            .padding(16)
        }
    }

    private func sessionRow(_ s: CycleSession) -> some View {
        SessionRowView(session: s, isSelected: selectedID == s.id, onDelete: { delete(s) })
    }

    private func delete(_ s: CycleSession) {
        if engine.sessionID == s.id { engine.stop() }
        store.today.sessions.removeAll { $0.id == s.id }
        if selectedID == s.id { selectedID = nil }
    }
}

@MainActor
private struct SessionRowView: View {
    let session: CycleSession
    let isSelected: Bool
    let onDelete: () -> Void
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine
    @State private var hover = false

    var body: some View {
        let s = session
        let live = engine.sessionID == s.id && engine.isRunning
        let block = store.today.blocks.first { $0.id == s.blockID }
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(s.title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
                Spacer()
                if hover {
                    Button(action: onDelete) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.inkFaint) }
                        .buttonStyle(.plain).help("Delete session")
                } else if s.finished { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.breakC) }
                else if live { Circle().fill(Theme.nowLine).frame(width: 8, height: 8) }
            }
            SessionPulse(session: s, compact: true)
            Text((block.map { "\($0.start.shortTime)–\($0.end.shortTime) · " } ?? "") + "\(s.cycleCount) × \(s.cycleMinutes) min" + (s.deepMinutes > 0 ? " · \(s.deepMinutes) min done" : ""))
                .font(Theme.small).foregroundColor(Theme.inkFaint)
        }
        .padding(10)
        .background(isSelected ? Theme.paper : Theme.paper.opacity(hover ? 0.6 : 0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu { Button("Delete session", action: onDelete) }
    }
}

extension CyclesView {
    fileprivate func create(from block: TimeBlock?) {
        let s = block.map { CycleSession.fitting(block: $0) } ?? CycleSession()
        store.today.sessions.append(s)
        selectedID = s.id
        stage = 0
    }
}

// MARK: - Session

@MainActor
struct SessionView: View {
    @Binding var session: CycleSession
    @Binding var stage: Int
    let dateKey: String
    @EnvironmentObject var engine: CycleEngine

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                TextField("Session title", text: $session.title)
                    .font(Theme.display(22)).foregroundColor(Theme.ink).textFieldStyle(.plain)
                    .frame(maxWidth: 520)
                Picker("", selection: $stage) {
                    Text("Prepare").tag(0)
                    Text("Work").tag(1)
                    Text("Debrief").tag(2)
                }
                .pickerStyle(.segmented).frame(width: 240)
                Spacer()
            }
            .padding(.horizontal, Space.xl).padding(.top, Space.xl).padding(.bottom, Space.l)
            ScrollView {
                Group {
                    switch stage {
                    case 0: PrepareView(session: $session, onStart: { stage = 1 })
                    case 1: WorkView(session: $session, dateKey: dateKey, onDebrief: { stage = 2 })
                    default: DebriefView(session: $session)
                    }
                }
                .padding(.horizontal, Space.xl).padding(.bottom, Space.xl)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.paper)
    }
}

// MARK: - 1. Prepare

struct PrepareView: View {
    @Binding var session: CycleSession
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Take a few minutes to prepare, so that the next few hours are effective.")
                .foregroundColor(Theme.inkFaint)
            HStack(spacing: Space.l) {
                Stepper("\(session.cycleCount) cycles", value: $session.cycleCount, in: 1...12)
                Stepper("of \(session.cycleMinutes) min", value: $session.cycleMinutes, in: 5...90, step: 5)
                Stepper("\(session.breakMinutes)-min breaks", value: $session.breakMinutes, in: 1...30)
                Text("about \((session.cycleMinutes + session.breakMinutes) * session.cycleCount - session.breakMinutes) min")
                    .font(Theme.small).foregroundColor(Theme.inkFaint)
            }
            .font(Theme.body)

            WritingField("What am I trying to accomplish?", $session.accomplish)
            WritingField("Why is this important and valuable?", $session.important)
            WritingField("How will I know this is complete?", $session.complete)
            WritingField("Any risks or hazards? Potential distractions, procrastination…", $session.risks)
            WritingField("Is this concrete and measurable, or subjective and ambiguous?", $session.measurable)
            WritingField("Anything else noteworthy?", $session.other)

            Button { onStart() } label: { Label("Ready. Plan the first cycle", systemImage: "arrow.right") }
                .buttonStyle(InkButtonStyle())
        }
    }
}

// MARK: - 2. Work

@MainActor
struct WorkView: View {
    @Binding var session: CycleSession
    let dateKey: String
    let onDebrief: () -> Void
    @EnvironmentObject var engine: CycleEngine

    private var isActiveSession: Bool { engine.sessionID == session.id }
    private var idx: Int { min(session.currentCycle, max(0, session.cycles.count - 1)) }
    private var phase: CycleEngine.Phase { isActiveSession ? engine.phase : .planning }
    private var lastCycle: Bool { session.currentCycle >= session.cycleCount - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            summaryStrip
            if session.cycles.isEmpty {
                Color.clear.frame(height: 0).onAppear(perform: ensureCycles)
            } else if idx < session.cycles.count {
                let cycle = $session.cycles[idx]
                switch phase {
                case .working, .breaking:
                    timerPanel(cycle: cycle.wrappedValue)
                case .reviewing:
                    reviewPanel(cycle: cycle)
                default:
                    planPanel(cycle: cycle)
                }
            }
        }
        .onAppear(perform: ensureCycles)
        .onChange(of: session.cycleCount) { _ in ensureCycles() }
    }

    private func ensureCycles() {
        while session.cycles.count < session.cycleCount { session.cycles.append(WorkCycle()) }
        if session.cycles.count > session.cycleCount { session.cycles.removeLast(session.cycles.count - session.cycleCount) }
        if session.currentCycle >= session.cycleCount { session.currentCycle = session.cycleCount - 1 }
    }

    private var summaryStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            cycleChips
            SessionPulse(session: session)
        }
    }

    private var cycleChips: some View {
        HStack(spacing: 8) {
            ForEach(Array(session.cycles.prefix(session.cycleCount).enumerated()), id: \.offset) { i, c in
                let done = !c.completed.isEmpty
                let current = i == session.currentCycle
                VStack(spacing: 3) {
                    Text("\(i + 1)").font(.system(size: 12, weight: .semibold, design: .serif))
                    Text(done ? c.completed : (current ? "now" : " ")).font(Theme.small)
                }
                .foregroundColor(current || done ? .white : Theme.inkFaint)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(current ? Theme.deep : (done ? Theme.deep.opacity(0.55) : Theme.paperDeep))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }

    private func planPanel(cycle: Binding<WorkCycle>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Plan cycle \(session.currentCycle + 1) of \(session.cycleCount)").font(Theme.display(20)).foregroundColor(Theme.ink)
            if session.currentCycle > 0, !cycle.wrappedValue.goal.isEmpty, phase == .planning {
                Text("Planned before the break. Adjust if anything changed, then start.")
                    .font(Theme.small).foregroundColor(Theme.inkFaint)
            }
            WritingField("What am I trying to accomplish this cycle?", cycle.goal)
            WritingField("How will I get started?", cycle.startPlan)
            WritingField("Any hazards present?", cycle.hazards)
            HStack(spacing: 28) {
                Rating("Energy", cycle.energy)
                Rating("Morale", cycle.morale)
            }
            .padding(.vertical, 4)
            HStack {
                Button {
                    engine.attach(sessionID: session.id, dateKey: dateKey)
                    engine.startWork(minutes: session.cycleMinutes)
                } label: { Label("Start cycle, \(session.cycleMinutes) min", systemImage: "play.fill") }
                .buttonStyle(InkButtonStyle())
                .disabled(engine.isRunning && !isActiveSession)
                if engine.isRunning && !isActiveSession {
                    Text("Another session's timer is running.").font(Theme.small).foregroundColor(Theme.tasks)
                }
                Spacer()
                if session.currentCycle > 0 {
                    Button("Skip to debrief") { onDebrief() }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private func timerPanel(cycle: WorkCycle) -> some View {
        let working = engine.phase == .working
        let total = (working ? session.cycleMinutes : session.breakMinutes) * 60
        let progress = total > 0 ? 1 - Double(engine.remaining) / Double(total) : 0
        return VStack(spacing: 14) {
            Text(working ? "Cycle \(session.currentCycle + 1) of \(session.cycleCount)" : "Break")
                .font(Theme.heading).foregroundColor(Theme.onField.opacity(0.7))
            Text(mmss(engine.remaining))
                .font(.system(size: 120, weight: .medium, design: .serif).monospacedDigit())
                .foregroundColor(Theme.onField)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.onField.opacity(0.18))
                    Capsule().fill(Theme.onField).frame(width: g.size.width * progress)
                }
            }
            .frame(height: 4).padding(.horizontal, 60)
            if working {
                if !cycle.goal.isEmpty {
                    Text(cycle.goal).font(.system(size: 17, weight: .medium)).foregroundColor(Theme.onField)
                        .multilineTextAlignment(.center).frame(maxWidth: 480)
                }
                if !cycle.hazards.isEmpty {
                    Text("Watch for: \(cycle.hazards)").font(Theme.small).foregroundColor(Theme.onField.opacity(0.7))
                }
            } else {
                Text("Stand up. Water. Eyes off the screen.").font(Theme.body).foregroundColor(Theme.onField.opacity(0.8))
            }
            HStack(spacing: 10) {
                fieldButton(engine.paused ? "Resume" : "Pause") { engine.togglePause() }
                fieldButton(working ? "End cycle early" : "Skip break") { engine.endNow() }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(working ? Theme.workField : Theme.breakField)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func fieldButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.onField)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .overlay(Capsule().stroke(Theme.onField.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func reviewPanel(cycle: Binding<WorkCycle>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review cycle \(session.currentCycle + 1)").font(Theme.display(20)).foregroundColor(Theme.ink)
            HStack(spacing: 12) {
                Text("Completed the cycle's target?").font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink)
                ForEach(["Yes", "Half", "No"], id: \.self) { v in
                    Button(v) { cycle.wrappedValue.completed = v }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(cycle.wrappedValue.completed == v ? .white : Theme.ink)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(cycle.wrappedValue.completed == v ? Theme.deep : Theme.paperDeep)
                        .clipShape(Capsule())
                }
            }
            WritingField("Anything noteworthy?", cycle.noteworthy)
            WritingField("Any distractions?", cycle.distractions)
            WritingField("Things to improve for next cycle?", cycle.improvements)

            if !lastCycle, session.currentCycle + 1 < session.cycles.count {
                let next = $session.cycles[session.currentCycle + 1]
                Divider().padding(.vertical, 4)
                Text("Plan cycle \(session.currentCycle + 2) before the break").font(Theme.display(18)).foregroundColor(Theme.ink)
                Text("Decide now, while the context is warm, so the break is a real break and the next cycle starts on the timer.")
                    .font(Theme.small).foregroundColor(Theme.inkFaint)
                WritingField("What am I trying to accomplish next cycle?", next.goal)
                WritingField("How will I get started?", next.startPlan)
                WritingField("Any hazards present?", next.hazards)
                HStack(spacing: 28) {
                    Rating("Energy", next.energy)
                    Rating("Morale", next.morale)
                }
                .padding(.vertical, 4)
            }

            HStack {
                if lastCycle {
                    Button { finishSession() } label: { Label("Finish and debrief", systemImage: "flag.checkered") }
                        .buttonStyle(InkButtonStyle())
                } else {
                    Button { advance(); engine.startBreak(minutes: session.breakMinutes) } label: {
                        Label("Start break, \(session.breakMinutes) min", systemImage: "cup.and.saucer")
                    }
                    .buttonStyle(InkButtonStyle(fill: Theme.breakC))
                    Button("Skip break") { advance(); engine.stop(); engine.attach(sessionID: session.id, dateKey: dateKey) }
                        .buttonStyle(QuietButtonStyle())
                    Button("Stop here and debrief") { finishSession() }.buttonStyle(QuietButtonStyle())
                }
            }
            .disabled(cycle.wrappedValue.completed.isEmpty)
            if cycle.wrappedValue.completed.isEmpty {
                Text("Mark whether you hit the target to continue.").font(Theme.small).foregroundColor(Theme.inkFaint)
            } else if !lastCycle, session.currentCycle + 1 < session.cycles.count, session.cycles[session.currentCycle + 1].goal.isEmpty {
                Text("Next cycle has no goal yet. You can still break, but the plan is easier now than after.")
                    .font(Theme.small).foregroundColor(Theme.tasks)
            }
        }
    }

    private func advance() {
        if session.currentCycle < session.cycleCount - 1 { session.currentCycle += 1 }
    }

    private func finishSession() {
        engine.stop()
        onDebrief()
    }
}

// MARK: - 3. Debrief

struct DebriefView: View {
    @Binding var session: CycleSession
    @EnvironmentObject var engine: CycleEngine
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Take a few minutes to debrief, so that you can identify and lock in lessons.")
                .foregroundColor(Theme.inkFaint)

            SessionPulse(session: session, tall: true)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("").frame(width: 110)
                    ForEach(0..<session.cycles.count, id: \.self) { i in
                        Text("\(i + 1)").font(.system(size: 13, weight: .semibold, design: .serif)).foregroundColor(Theme.ink)
                    }
                }
                row("Energy") { "\(session.cycles[$0].energy)" }
                row("Morale") { "\(session.cycles[$0].morale)" }
                row("Target") { session.cycles[$0].completed.isEmpty ? "–" : session.cycles[$0].completed }
                row("Minutes") { "\(session.cycles[$0].workedSeconds / 60)" }
            }
            .panel()

            Text("\(session.deepMinutes) minutes of deep work logged").font(Theme.display(18)).foregroundColor(Theme.deep)

            WritingField("What did I get done these past few hours?", $session.gotDone)
            WritingField("How did this compare to my normal work output?", $session.compare)
            WritingField("Did I get bogged down? Where?", $session.boggedDown)
            WritingField("What went well? How can I replicate this in the future?", $session.wentWell)
            WritingField("Any other takeaways? Lessons to share with others?", $session.takeaways)

            Toggle("Session finished", isOn: $session.finished)
                .toggleStyle(.switch)
                .font(.system(size: 13, weight: .medium))
                .onChange(of: session.finished) { done in
                    if done {
                        if engine.sessionID == session.id { engine.stop() }
                        store.focusMode = false
                    }
                }
        }
    }

    private func row(_ label: String, _ value: @escaping (Int) -> String) -> some View {
        GridRow {
            Text(label).font(Theme.small).foregroundColor(Theme.inkFaint)
            ForEach(0..<session.cycles.count, id: \.self) { i in
                Text(value(i)).font(Theme.body.monospacedDigit()).foregroundColor(Theme.ink)
            }
        }
    }
}

// MARK: - Small controls

struct Rating: View {
    let label: String
    @Binding var value: Int
    init(_ label: String, _ value: Binding<Int>) { self.label = label; self._value = value }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.ink)
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= value ? Theme.deep : Theme.deep.opacity(0.18))
                    .frame(width: 14, height: 14)
                    .onTapGesture { value = i }
            }
        }
    }
}


// MARK: - Session pulse: energy and morale stacked on one axis, targets underneath

/// Two 1–5 lanes (energy, morale) that share the cycle axis, with target dots
/// under the same columns. `compact` is the sidebar version.
struct SessionPulse: View {
    let session: CycleSession
    var tall: Bool = false
    var compact: Bool = false

    private func rated(_ i: Int) -> Bool {
        i < session.cycles.count && (i <= session.currentCycle || !session.cycles[i].completed.isEmpty)
    }
    private var energy: [Int?] { (0..<session.cycleCount).map { rated($0) ? session.cycles[$0].energy : nil } }
    private var morale: [Int?] { (0..<session.cycleCount).map { rated($0) ? session.cycles[$0].morale : nil } }
    private var laneHeight: CGFloat { compact ? 18 : (tall ? 48 : 30) }
    private var labelWidth: CGFloat { compact ? 14 : 52 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            lane(compact ? "E" : "Energy", values: energy, color: Theme.deep)
            lane(compact ? "M" : "Morale", values: morale, color: Theme.tasks)
            HStack(spacing: Space.s) {
                Text(compact ? "" : "Target").font(TypeScale.caption).foregroundColor(Theme.inkFaint).frame(width: labelWidth, alignment: .leading)
                targetsRow
            }
            if !compact { axis }
        }
    }

    private func lane(_ label: String, values: [Int?], color: Color) -> some View {
        HStack(spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label).font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                if !compact, let v = values.compactMap({ $0 }).last {
                    Text("\(v)").font(TypeScale.caption.weight(.semibold).monospacedDigit()).foregroundColor(color)
                }
            }
            .frame(width: labelWidth, alignment: .leading)
            Sparkline(values: values, color: color, current: session.currentCycle)
                .frame(height: laneHeight)
        }
    }

    /// Dots on the same columns as the sparkline points.
    private var targetsRow: some View {
        GeometryReader { geo in
            let n = max(session.cycleCount, 2)
            let stepX = geo.size.width / CGFloat(n - 1)
            ForEach(0..<session.cycleCount, id: \.self) { i in
                let c = i < session.cycles.count ? session.cycles[i].completed : ""
                Circle()
                    .fill(c == "Yes" ? Theme.breakC : c == "Half" ? Theme.tasks : c == "No" ? Theme.nowLine : Theme.ruleFaint)
                    .frame(width: compact ? 6 : 9, height: compact ? 6 : 9)
                    .position(x: CGFloat(i) * stepX, y: geo.size.height / 2)
            }
        }
        .frame(height: compact ? 8 : 12)
    }

    private var axis: some View {
        HStack(spacing: Space.s) {
            Color.clear.frame(width: labelWidth, height: 1)
            GeometryReader { geo in
                let n = max(session.cycleCount, 2)
                let stepX = geo.size.width / CGFloat(n - 1)
                ForEach(0..<session.cycleCount, id: \.self) { i in
                    Text("\(i + 1)")
                        .font(.system(size: 10, weight: i == session.currentCycle ? .semibold : .regular, design: .serif))
                        .foregroundColor(i == session.currentCycle ? Theme.ink : Theme.inkFaint)
                        .position(x: CGFloat(i) * stepX, y: 6)
                }
            }
            .frame(height: 12)
        }
    }
}

/// A 1–5 sparkline. Gaps in `values` (nil) break the line; the current cycle gets a ring.
struct Sparkline: View {
    let values: [Int?]
    let color: Color
    var current: Int = -1
    var maxValue: Double = 5

    var body: some View {
        Canvas { ctx, size in
            let n = max(values.count, 2)
            let stepX = size.width / CGFloat(n - 1)
            let pad: CGFloat = 4
            func point(_ i: Int, _ v: Int) -> CGPoint {
                CGPoint(x: CGFloat(i) * stepX,
                        y: pad + (size.height - 2 * pad) * (1 - CGFloat((Double(v) - 1) / (maxValue - 1))))
            }
            // baseline at 3 (neutral)
            var base = Path()
            let midY = pad + (size.height - 2 * pad) * 0.5
            base.move(to: CGPoint(x: 0, y: midY)); base.addLine(to: CGPoint(x: size.width, y: midY))
            ctx.stroke(base, with: .color(Theme.ruleFaint), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            // line
            var path = Path()
            var pen = false
            for (i, v) in values.enumerated() {
                if let v {
                    let p = point(i, v)
                    if pen { path.addLine(to: p) } else { path.move(to: p); pen = true }
                } else { pen = false }
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            // dots
            for (i, v) in values.enumerated() {
                guard let v else { continue }
                let p = point(i, v)
                let r: CGFloat = i == current ? 3.5 : 2.5
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
                if i == current {
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(color.opacity(0.5)), lineWidth: 1)
                }
            }
        }
    }
}
