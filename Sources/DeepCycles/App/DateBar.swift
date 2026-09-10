import SwiftUI
import DeepCyclesCore

/// Top bar: date, the three pages, live timer, and the bridge between
/// a deep block that's happening right now and its Work Cycles session.
@MainActor
struct DateBar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
    @EnvironmentObject var engine: CycleEngine
    @State private var now = Date()
    @State private var showShortcuts = false
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 18) {
            Wordmark(size: 15)
            HStack(spacing: 4) {
                Button { ui.shiftPeriod(-1, in: store) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Text(store.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(Theme.display(20)).foregroundColor(Theme.ink)
                    .frame(minWidth: 220, alignment: .center)
                Button { ui.shiftPeriod(1, in: store) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                if !Calendar.current.isDateInToday(store.selectedDate) {
                    Button("Today") { store.selectedDate = Calendar.current.startOfDay(for: Date()) }
                        .buttonStyle(QuietButtonStyle())
                }
            }

            Picker("", selection: $ui.tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 240)

            Spacer()

            if engine.phase != .idle {
                TimerPill()
            } else if !ui.focusMode, let block = store.currentDeepBlock(now: now), store.session(forBlock: block.id) == nil {
                Button { SessionFlow(store: store, ui: ui, engine: engine).runCycles(on: block) } label: {
                    Label("Start cycles: \(block.title)", systemImage: "play.fill")
                }
                .buttonStyle(QuietButtonStyle())
                .help("This deep block is happening now and has no session yet")
            }

            if store.today.shutdownComplete {
                Label("Shutdown complete", systemImage: "checkmark.seal.fill").foregroundColor(Theme.breakC).font(Theme.small)
            }

            Button { showShortcuts.toggle() } label: {
                Image(systemName: "keyboard").foregroundColor(Theme.inkFaint)
            }
            .buttonStyle(.borderless)
            .help("Keyboard shortcuts")
            .popover(isPresented: $showShortcuts) { ShortcutsSheet() }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Theme.paperDeep)
        .onReceive(clock) { now = $0 }
    }
}

/// The session's state, always in the top bar: ring, countdown, phase, cycle N of M.
/// Hover for pause / end; click to open Focus.
@MainActor
struct TimerPill: View {
    @EnvironmentObject var ui: AppState
    @EnvironmentObject var engine: CycleEngine
    @State private var hover = false

    private var color: Color { engine.phase == .breaking ? Theme.breakC : Theme.deep }
    private var session: CycleSession? { engine.session() }
    private var total: Int {
        guard let s = session else { return 0 }
        return (engine.phase == .breaking ? s.breakMinutes : s.cycleMinutes) * 60
    }
    private var progress: Double { total > 0 && engine.isRunning ? 1 - Double(engine.remaining) / Double(total) : 0 }

    private var label: String {
        let n = (session?.currentCycle ?? 0) + 1, m = session?.cycleCount ?? 0
        switch engine.phase {
        case .working: return engine.paused ? "Paused · cycle \(n) of \(m)" : "Cycle \(n) of \(m)"
        case .breaking: return "Break"
        case .reviewing: return "Review cycle \(n)"
        case .planning: return "Plan cycle \(n)"
        default: return ""
        }
    }

    var body: some View {
        HStack(spacing: Space.s) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 2.5)
                Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                if engine.paused { Image(systemName: "pause.fill").font(.system(size: 7)).foregroundColor(color) }
            }
            .frame(width: 18, height: 18)
            .animation(.linear(duration: 1), value: progress)

            if engine.isRunning {
                Text(mmss(engine.remaining))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced).monospacedDigit())
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(TypeScale.caption.weight(.medium)).foregroundColor(Theme.ink)
                if let s = session, !s.current.goal.isEmpty, engine.phase == .working {
                    Text(s.current.goal).font(TypeScale.caption).foregroundColor(Theme.inkFaint).lineLimit(1).frame(maxWidth: 220, alignment: .leading)
                }
            }
            if hover, engine.isRunning {
                Button { engine.togglePause() } label: { Image(systemName: engine.paused ? "play.fill" : "pause.fill") }
                    .buttonStyle(.plain).foregroundColor(Theme.inkFaint).help(engine.paused ? "Resume  ⌘." : "Pause  ⌘.")
                Button { engine.endNow() } label: { Image(systemName: "forward.end.fill") }
                    .buttonStyle(.plain).foregroundColor(Theme.inkFaint).help(engine.phase == .breaking ? "End break  ⇧⌘E" : "End cycle  ⇧⌘E")
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, 5)
        .background(color.opacity(hover ? 0.14 : 0.09))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .onTapGesture { ui.focusMode = true }
        .help("Open Focus  ⇧⌘F")
    }
}
