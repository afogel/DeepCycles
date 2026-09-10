import SwiftUI

/// Focus mode: the day's sessions on the left, the selected session's three steps on the right.
/// Keyboard: Tab through everything; the session list takes ↑↓ ↩ ⌫; ⌘↩ is the next step;
/// ⇧⌘N a new session; ⎋ back to the day. Selection lives in the store so menus and the
/// palette can drive it (see SessionFlow).
@MainActor
struct CyclesView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine
    @FocusState private var listFocused: Bool

    private var selectedID: UUID? { store.focusSessionID }

    var body: some View {
        HStack(spacing: 0) {
            sessionList.frame(width: 250).background(Theme.paperDeep)
            if let id = selectedID, store.today.sessions.contains(where: { $0.id == id }) {
                SessionView(session: binding(for: id), stage: $store.focusStage, dateKey: store.selectedKey)
            } else {
                emptyState
            }
        }
        .onAppear { ensureSelection(); handle(store.pending) }
        .onChange(of: store.today.sessions.count) { ensureSelection() }
        .onChange(of: engine.sessionID) { followEngine() }
        .onChange(of: store.selectedDate) { store.focusSessionID = nil; ensureSelection() }
        .onChange(of: store.pending) { handle(store.pending) }
        .onExitCommand { store.focusMode = false }
    }

    /// Commands from the menus / palette that only Focus can carry out.
    private func handle(_ cmd: PendingCommand?) {
        switch cmd {
        case .primaryAction:
            store.pending = nil
            SessionFlow.performPrimary(store, engine)
        case .newSession:
            store.pending = nil
            SessionFlow.newSession(store, from: SessionFlow.nextFreeDeepBlock(store))
        default:
            break
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No session yet").font(Theme.display(22)).foregroundColor(Theme.ink)
            Text("A session is one deep-work block executed as 30-minute cycles with 10-minute breaks.\nPick a deep block below, or start a standalone session.")
                .multilineTextAlignment(.center).foregroundColor(Theme.inkFaint).frame(maxWidth: 380)
            let deepBlocks = store.today.blocks.filter { $0.kind == .deep && store.session(forBlock: $0.id) == nil }
            HStack {
                if deepBlocks.isEmpty {
                    Button("Plan a deep block first") { store.focusMode = false; store.tab = 0 }.buttonStyle(InkButtonStyle())
                } else {
                    ForEach(deepBlocks) { b in
                        Button("\(b.start.shortTime) \(b.title)") { SessionFlow.newSession(store, from: b) }.buttonStyle(InkButtonStyle())
                    }
                }
                Button("Standalone session") { SessionFlow.newSession(store, from: nil) }.buttonStyle(QuietButtonStyle())
            }
            Text("⌘↩ starts a session for the next deep block · ⇧⌘N new session")
                .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Selection

    /// Keep a valid selection: the running session if it is on this day, else the first live one.
    private func ensureSelection() {
        let sessions = store.today.sessions
        if let id = selectedID, sessions.contains(where: { $0.id == id }) { return }
        if let running = engine.sessionID, engine.sessionDateKey == store.selectedKey,
           let s = sessions.first(where: { $0.id == running }) {
            SessionFlow.select(store, engine, s)
        } else if let s = SessionFlow.listOrder(store).first {
            SessionFlow.select(store, engine, s)
        } else {
            store.focusSessionID = nil
        }
    }

    /// The timer was attached to a session on this day: show it.
    private func followEngine() {
        guard let running = engine.sessionID, engine.sessionDateKey == store.selectedKey,
              let s = store.today.sessions.first(where: { $0.id == running }), selectedID != running else { return }
        SessionFlow.select(store, engine, s)
    }

    private func binding(for id: UUID) -> Binding<CycleSession> {
        Binding(
            get: { store.today.sessions.first { $0.id == id } ?? CycleSession() },
            set: { new in
                if let i = store.today.sessions.firstIndex(where: { $0.id == id }) { store.today.sessions[i] = new }
            }
        )
    }

    // MARK: Session list

    private var sessionList: some View {
        let list = SessionFlow.listOrder(store)
        let live = list.filter { !$0.finished }
        let done = list.filter { $0.finished }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading("Sessions")
                Spacer()
                Text("↑↓ · ↩ · ⌫").font(TypeScale.caption).foregroundColor(Theme.inkFaint).opacity(listFocused ? 1 : 0)
            }
            .padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(live) { s in row(s) }
                    if !done.isEmpty {
                        Text("Done today").font(TypeScale.caption).foregroundColor(Theme.inkFaint).padding(.top, 10).padding(.leading, 4)
                        ForEach(done) { s in row(s).opacity(0.75) }
                    }
                    if list.isEmpty {
                        Text("Sessions live with their day; older ones are in Systems → Session log.")
                            .font(TypeScale.caption).foregroundColor(Theme.inkFaint).padding(4)
                    }
                }
                .padding(.horizontal, 12)
            }
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { SessionFlow.selectAdjacent(store, engine, -1); return .handled }
            .onKeyPress(.downArrow) { SessionFlow.selectAdjacent(store, engine, 1); return .handled }
            .onKeyPress(.return) {
                guard selectedID != nil else { return .ignored }
                store.requestFormFocus()
                return .handled
            }
            .onKeyPress(.delete) {
                guard let id = selectedID else { return .ignored }
                SessionFlow.delete(store, engine, id)
                return .handled
            }
            .accessibilityLabel("Sessions")
            Spacer()
            newSessionMenu
        }
    }

    private func row(_ s: CycleSession) -> some View {
        SessionRowView(session: s, isSelected: selectedID == s.id, listFocused: listFocused) {
            SessionFlow.delete(store, engine, s.id)
        }
        .onTapGesture { SessionFlow.select(store, engine, s); listFocused = true }
    }

    private var newSessionMenu: some View {
        let deepBlocks = store.today.blocks.filter { $0.kind == .deep && store.session(forBlock: $0.id) == nil }
        return Menu {
            Button("Standalone session") { SessionFlow.newSession(store, from: nil) }
            if !deepBlocks.isEmpty { Divider() }
            ForEach(deepBlocks) { b in
                Button("\(b.start.shortTime)  \(b.title)  (\(b.minutes) min)") { SessionFlow.newSession(store, from: b) }
            }
        } label: { Label("New session", systemImage: "plus") }
        .menuStyle(.borderlessButton)
        .help("⇧⌘N: a session for the next deep block")
        .padding(16)
    }
}

@MainActor
private struct SessionRowView: View {
    let session: CycleSession
    let isSelected: Bool
    let listFocused: Bool
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
        .focusRing(isSelected && listFocused, shape: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu { Button("Delete session", action: onDelete) }
    }
}

// MARK: - Session

@MainActor
struct SessionView: View {
    @Binding var session: CycleSession
    @Binding var stage: Int
    let dateKey: String
    @EnvironmentObject var engine: CycleEngine
    @EnvironmentObject var store: Store
    @FocusState private var focus: Field?

    /// Every keyboard stop in the three steps, so focus can be placed programmatically.
    enum Field: Hashable {
        case title, stage
        case accomplish, important, complete, risks, measurable, other          // Prepare
        case goal, startPlan, hazards, energy, morale                             // Plan
        case target, noteworthy, distractions, improvements                       // Review
        case nextGoal, nextStart, nextHazards, nextEnergy, nextMorale             // Plan the next cycle
        case gotDone, compare, bogged, wentWell, takeaways, finished              // Debrief
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                TextField("Session title", text: $session.title)
                    .font(Theme.display(22)).foregroundColor(Theme.ink).textFieldStyle(.plain)
                    .frame(maxWidth: 520)
                    .focused($focus, equals: .title)
                SegmentPicker(selection: $stage, options: [(value: 0, label: "Prepare"), (value: 1, label: "Work"), (value: 2, label: "Debrief")])
                    .frame(width: 240)
                    .focused($focus, equals: .stage)
                Spacer()
            }
            .padding(.horizontal, Space.xl).padding(.top, Space.xl).padding(.bottom, Space.l)
            ScrollView {
                Group {
                    switch stage {
                    case 0: PrepareView(session: $session, focus: $focus)
                    case 1: WorkView(session: $session, dateKey: dateKey, focus: $focus)
                    default: DebriefView(session: $session, focus: $focus)
                    }
                }
                .padding(.horizontal, Space.xl).padding(.bottom, Space.xl)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.paper)
        .onChange(of: store.formFocusTick) { focusFirstField() }
        .onChange(of: engine.phase) { followTimer() }
    }

    /// Land in the first field of the current step.
    private func focusFirstField() {
        switch stage {
        case 0: set(.accomplish)
        case 2: set(.gotDone)
        default:
            if engine.sessionID == session.id, engine.phase == .reviewing { set(.target) } else { set(.goal) }
        }
    }

    /// The timer ended: the review (or the next plan) wants the keyboard.
    private func followTimer() {
        guard engine.sessionID == session.id, stage == 1 else { return }
        switch engine.phase {
        case .reviewing: set(.target)
        case .planning: set(.goal)
        default: break
        }
    }

    private func set(_ f: Field) {
        DispatchQueue.main.async { focus = f }
    }
}

// MARK: - 1. Prepare

struct PrepareView: View {
    @Binding var session: CycleSession
    var focus: FocusState<SessionView.Field?>.Binding
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Take a few minutes to prepare, so that the next few hours are effective.")
                .foregroundColor(Theme.inkFaint)
            HStack(spacing: Space.l) {
                ValueStepper($session.cycleCount, in: 1...12) { "\($0) cycles" }
                ValueStepper($session.cycleMinutes, in: 5...90, step: 5) { "of \($0) min" }
                ValueStepper($session.breakMinutes, in: 1...30) { "\($0)-min breaks" }
                Text("about \((session.cycleMinutes + session.breakMinutes) * session.cycleCount - session.breakMinutes) min")
                    .font(Theme.small).foregroundColor(Theme.inkFaint)
            }

            WritingField("What am I trying to accomplish?", $session.accomplish, focus: focus, tag: .accomplish)
            WritingField("Why is this important and valuable?", $session.important, focus: focus, tag: .important)
            WritingField("How will I know this is complete?", $session.complete, focus: focus, tag: .complete)
            WritingField("Any risks or hazards? Potential distractions, procrastination…", $session.risks, focus: focus, tag: .risks)
            WritingField("Is this concrete and measurable, or subjective and ambiguous?", $session.measurable, focus: focus, tag: .measurable)
            WritingField("Anything else noteworthy?", $session.other, focus: focus, tag: .other)

            HStack(spacing: Space.m) {
                Button { SessionFlow.toPlan(store, session.id) } label: { Label("Ready. Plan the first cycle", systemImage: "arrow.right") }
                    .buttonStyle(InkButtonStyle())
                Text("⌘↩").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }
        }
    }
}

// MARK: - 2. Work

@MainActor
struct WorkView: View {
    @Binding var session: CycleSession
    let dateKey: String
    var focus: FocusState<SessionView.Field?>.Binding
    @EnvironmentObject var engine: CycleEngine
    @EnvironmentObject var store: Store

    private var isActiveSession: Bool { engine.sessionID == session.id }
    private var idx: Int { min(session.currentCycle, max(0, session.cycles.count - 1)) }
    private var phase: CycleEngine.Phase { isActiveSession ? engine.phase : .planning }
    private var lastCycle: Bool { SessionFlow.isLast(session) }

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
        .onChange(of: session.cycleCount) { ensureCycles() }
    }

    private func ensureCycles() { SessionFlow.ensureCycles(&session) }

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
            WritingField("What am I trying to accomplish this cycle?", cycle.goal, focus: focus, tag: .goal)
            WritingField("How will I get started?", cycle.startPlan, focus: focus, tag: .startPlan)
            WritingField("Any hazards present?", cycle.hazards, focus: focus, tag: .hazards)
            HStack(spacing: 28) {
                Rating("Energy", cycle.energy).focused(focus, equals: .energy)
                Rating("Morale", cycle.morale).focused(focus, equals: .morale)
            }
            .padding(.vertical, 4)
            HStack(spacing: Space.m) {
                Button { SessionFlow.startCycle(store, engine, session.id) } label: {
                    Label("Start cycle, \(session.cycleMinutes) min", systemImage: "play.fill")
                }
                .buttonStyle(InkButtonStyle())
                .disabled(engine.isRunning && !isActiveSession)
                if engine.isRunning && !isActiveSession {
                    Text("Another session's timer is running.").font(Theme.small).foregroundColor(Theme.tasks)
                } else {
                    Text("⌘↩").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                }
                Spacer()
                if session.currentCycle > 0 {
                    Button("Skip to debrief") { SessionFlow.toDebrief(store, engine, session.id) }.buttonStyle(QuietButtonStyle())
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
                Button(engine.paused ? "Resume  ⌘." : "Pause  ⌘.") { engine.togglePause() }.buttonStyle(FieldButtonStyle())
                Button(working ? "End cycle early  ⇧⌘E" : "Skip break  ⇧⌘E") { engine.endNow() }.buttonStyle(FieldButtonStyle())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(working ? Theme.workField : Theme.breakField)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func reviewPanel(cycle: Binding<WorkCycle>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review cycle \(session.currentCycle + 1)").font(Theme.display(20)).foregroundColor(Theme.ink)
            TargetPicker(cycle.completed).focused(focus, equals: .target)
            WritingField("Anything noteworthy?", cycle.noteworthy, focus: focus, tag: .noteworthy)
            WritingField("Any distractions?", cycle.distractions, focus: focus, tag: .distractions)
            WritingField("Things to improve for next cycle?", cycle.improvements, focus: focus, tag: .improvements)

            if !lastCycle, session.currentCycle + 1 < session.cycles.count {
                let next = $session.cycles[session.currentCycle + 1]
                Divider().padding(.vertical, 4)
                Text("Plan cycle \(session.currentCycle + 2) before the break").font(Theme.display(18)).foregroundColor(Theme.ink)
                Text("Decide now, while the context is warm, so the break is a real break and the next cycle starts on the timer.")
                    .font(Theme.small).foregroundColor(Theme.inkFaint)
                WritingField("What am I trying to accomplish next cycle?", next.goal, focus: focus, tag: .nextGoal)
                WritingField("How will I get started?", next.startPlan, focus: focus, tag: .nextStart)
                WritingField("Any hazards present?", next.hazards, focus: focus, tag: .nextHazards)
                HStack(spacing: 28) {
                    Rating("Energy", next.energy).focused(focus, equals: .nextEnergy)
                    Rating("Morale", next.morale).focused(focus, equals: .nextMorale)
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: Space.m) {
                if lastCycle {
                    Button { SessionFlow.toDebrief(store, engine, session.id) } label: { Label("Finish and debrief", systemImage: "flag.checkered") }
                        .buttonStyle(InkButtonStyle())
                } else {
                    Button { SessionFlow.startBreak(store, engine, session.id) } label: {
                        Label("Start break, \(session.breakMinutes) min", systemImage: "cup.and.saucer")
                    }
                    .buttonStyle(InkButtonStyle(fill: Theme.breakC))
                    Button("Skip break") { SessionFlow.skipBreak(store, engine, session.id) }.buttonStyle(QuietButtonStyle())
                    Button("Stop here and debrief") { SessionFlow.toDebrief(store, engine, session.id) }.buttonStyle(QuietButtonStyle())
                }
                Text("⌘↩").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
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
}

// MARK: - 3. Debrief

struct DebriefView: View {
    @Binding var session: CycleSession
    var focus: FocusState<SessionView.Field?>.Binding
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

            WritingField("What did I get done these past few hours?", $session.gotDone, focus: focus, tag: .gotDone)
            WritingField("How did this compare to my normal work output?", $session.compare, focus: focus, tag: .compare)
            WritingField("Did I get bogged down? Where?", $session.boggedDown, focus: focus, tag: .bogged)
            WritingField("What went well? How can I replicate this in the future?", $session.wentWell, focus: focus, tag: .wentWell)
            WritingField("Any other takeaways? Lessons to share with others?", $session.takeaways, focus: focus, tag: .takeaways)

            HStack(spacing: Space.m) {
                Toggle("Session finished", isOn: finished)
                    .toggleStyle(KeySwitchStyle())
                    .font(.system(size: 13, weight: .medium))
                    .focused(focus, equals: .finished)
                Text("⌘↩").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }
        }
    }

    /// Flipping the switch is what finishes a session (stops the timer, leaves Focus);
    /// merely looking at a finished one must not.
    private var finished: Binding<Bool> {
        Binding(get: { session.finished }, set: { SessionFlow.setFinished(store, engine, session.id, $0) })
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
