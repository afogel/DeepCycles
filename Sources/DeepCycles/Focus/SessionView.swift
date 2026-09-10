import SwiftUI
import DeepCyclesCore

/// One session: its title, the stage picker and the current step. Puts keyboard focus where the
/// flow asks (AppState.formFocusTick) and where the timer leaves the user.
@MainActor
struct SessionView: View {
    @Binding var session: CycleSession
    @Binding var stage: SessionStage
    @EnvironmentObject var engine: CycleEngine
    @EnvironmentObject var ui: AppState
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
                SegmentPicker(selection: $stage, options: SessionStage.allCases.map { (value: $0, label: $0.title) })
                    .frame(width: 240)
                    .focused($focus, equals: .stage)
                Spacer()
            }
            .padding(.horizontal, Space.xl).padding(.top, Space.xl).padding(.bottom, Space.l)
            ScrollView {
                Group {
                    switch stage {
                    case .prepare: PrepareView(session: $session, focus: $focus)
                    case .work: WorkView(session: $session, focus: $focus)
                    case .debrief: DebriefView(session: $session, focus: $focus)
                    }
                }
                .padding(.horizontal, Space.xl).padding(.bottom, Space.xl)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.paper)
        .onChange(of: ui.formFocusTick) { focusFirstField() }
        .onChange(of: engine.phase) { followTimer() }
    }

    /// Land in the first field of the current step.
    private func focusFirstField() {
        switch stage {
        case .prepare: set(.accomplish)
        case .debrief: set(.gotDone)
        case .work:
            if engine.sessionID == session.id, engine.phase == .reviewing { set(.target) } else { set(.goal) }
        }
    }

    /// The timer ended: the review (or the next plan) wants the keyboard.
    private func followTimer() {
        guard engine.sessionID == session.id, stage == .work else { return }
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

@MainActor
struct PrepareView: View {
    @Binding var session: CycleSession
    var focus: FocusState<SessionView.Field?>.Binding
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
    @EnvironmentObject var engine: CycleEngine

    private var flow: SessionFlow { SessionFlow(store: store, ui: ui, engine: engine) }

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
                Button { flow.toPlan(session.id) } label: { Label("Ready. Plan the first cycle", systemImage: "arrow.right") }
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
    var focus: FocusState<SessionView.Field?>.Binding
    @EnvironmentObject var engine: CycleEngine
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState

    private var flow: SessionFlow { SessionFlow(store: store, ui: ui, engine: engine) }
    private var isActiveSession: Bool { engine.sessionID == session.id }
    private var idx: Int { min(session.currentCycle, max(0, session.cycles.count - 1)) }
    private var phase: CycleEngine.Phase { isActiveSession ? engine.phase : .planning }
    private var lastCycle: Bool { session.isLastCycle }

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

    private func ensureCycles() { session.ensureCycles() }

    private var summaryStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            cycleChips
            SessionPulse(session: session)
        }
    }

    private var cycleChips: some View {
        HStack(spacing: 8) {
            ForEach(Array(session.cycles.prefix(session.cycleCount).enumerated()), id: \.offset) { i, c in
                let done = c.completed != nil
                let current = i == session.currentCycle
                VStack(spacing: 3) {
                    Text("\(i + 1)").font(.system(size: 12, weight: .semibold, design: .serif))
                    Text(c.completed?.label ?? (current ? "now" : " ")).font(Theme.small)
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
                Button { flow.startCycle(session.id) } label: {
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
                    Button("Skip to debrief") { flow.toDebrief(session.id) }.buttonStyle(QuietButtonStyle())
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

            let answered = cycle.wrappedValue.completed != nil
            HStack(spacing: Space.m) {
                if lastCycle {
                    Button { flow.toDebrief(session.id) } label: { Label("Finish and debrief", systemImage: "flag.checkered") }
                        .buttonStyle(InkButtonStyle())
                } else {
                    Button { flow.startBreak(session.id) } label: {
                        Label("Start break, \(session.breakMinutes) min", systemImage: "cup.and.saucer")
                    }
                    .buttonStyle(InkButtonStyle(fill: Theme.breakC))
                    Button("Skip break") { flow.skipBreak(session.id) }.buttonStyle(QuietButtonStyle())
                    Button("Stop here and debrief") { flow.toDebrief(session.id) }.buttonStyle(QuietButtonStyle())
                }
                Text("⌘↩").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }
            .disabled(!answered)
            if !answered {
                Text("Mark whether you hit the target to continue.").font(Theme.small).foregroundColor(Theme.inkFaint)
            } else if !lastCycle, session.currentCycle + 1 < session.cycles.count, session.cycles[session.currentCycle + 1].goal.isEmpty {
                Text("Next cycle has no goal yet. You can still break, but the plan is easier now than after.")
                    .font(Theme.small).foregroundColor(Theme.tasks)
            }
        }
    }
}

// MARK: - 3. Debrief

@MainActor
struct DebriefView: View {
    @Binding var session: CycleSession
    var focus: FocusState<SessionView.Field?>.Binding
    @EnvironmentObject var engine: CycleEngine
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState

    private var flow: SessionFlow { SessionFlow(store: store, ui: ui, engine: engine) }

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
                row("Target") { session.cycles[$0].completed?.label ?? "–" }
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
        Binding(get: { session.finished }, set: { flow.setFinished(session.id, $0) })
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
