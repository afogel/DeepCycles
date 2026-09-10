import SwiftUI

@main
struct DeepCyclesApp: App {
    @StateObject private var store: Store
    @StateObject private var calendar = CalendarService()
    @StateObject private var engine: CycleEngine

    init() {
        let s = Store()
        let e = CycleEngine()
        e.store = s
        _store = StateObject(wrappedValue: s)
        _engine = StateObject(wrappedValue: e)
    }

    var body: some Scene {
        WindowGroup("DeepCycles") {
            RootView()
                .environmentObject(store)
                .environmentObject(calendar)
                .environmentObject(engine)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(store: store, engine: engine) }

        // ⌘, and the app menu's "Settings…" come with the scene.
        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(calendar)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(engine)
        } label: {
            Label(engine.menuTitle, systemImage: engine.phase == .breaking ? "cup.and.saucer" : "timer")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
struct RootView: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                DateBar()
                ZStack {
                    Group {
                        switch store.tab {
                        case 1: WeekView()
                        case 2: SystemsView()
                        default: PlannerView()
                        }
                    }
                    if store.focusMode {
                        FocusView().transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            if store.showPalette {
                Color.black.opacity(0.18).ignoresSafeArea().onTapGesture { store.showPalette = false }
                VStack { CommandPalette().padding(.top, 60); Spacer() }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: store.showPalette)
        .animation(.easeInOut(duration: 0.22), value: store.focusMode)
        .sheet(isPresented: $store.showShutdown) { ShutdownView().environmentObject(store).environmentObject(engine) }
        .background(Theme.paper)
        .onAppear { store.appearance.apply() }
        .task { await calendar.requestAccess() }
    }
}

/// Top bar: date, the three pages, live timer, and the bridge between
/// a deep block that's happening right now and its Work Cycles session.
@MainActor
struct DateBar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine
    @State private var now = Date()
    @State private var showShortcuts = false
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 18) {
            Wordmark(size: 15)
            HStack(spacing: 4) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Text(store.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(Theme.display(20)).foregroundColor(Theme.ink)
                    .frame(minWidth: 220, alignment: .center)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                if !Calendar.current.isDateInToday(store.selectedDate) {
                    Button("Today") { store.selectedDate = Calendar.current.startOfDay(for: Date()) }
                        .buttonStyle(QuietButtonStyle())
                }
            }

            Picker("", selection: $store.tab) {
                Text("Day").tag(0)
                Text("Week").tag(1)
                Text("Systems").tag(2)
            }
            .pickerStyle(.segmented).frame(width: 240)

            Spacer()

            if engine.phase != .idle {
                TimerPill()
            } else if !store.focusMode, let block = store.currentDeepBlock(now: now), store.session(forBlock: block.id) == nil {
                Button { SessionFlow.runCycles(on: block, store, engine) } label: {
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

    private func shift(_ days: Int) { store.shiftPeriod(days) }
}

// MARK: - Menus and hotkeys (generated from CommandCatalog)

struct AppCommands: Commands {
    @ObservedObject var store: Store
    @ObservedObject var engine: CycleEngine

    var body: some Commands {
        let cmds = CommandCatalog.commands(store: store, engine: engine, openSettings: {})
        CommandGroup(replacing: .undoRedo) { MenuItems(commands: cmds, place: .edit) }
        CommandGroup(replacing: .newItem) { MenuItems(commands: cmds, place: .file) }
        CommandMenu("Go") { MenuItems(commands: cmds, place: .go) }
        CommandMenu("Cycle") { MenuItems(commands: cmds, place: .cycle) }
    }
}

/// The catalogue's commands for one menu, with separators between sections.
private struct MenuItems: View {
    let commands: [AppCommand]
    let place: MenuPlace

    var body: some View {
        let items = commands.filter { $0.menu == place }
        let sections = Array(Set(items.map(\.section))).sorted()
        ForEach(sections, id: \.self) { sec in
            if sec != sections.first { Divider() }
            ForEach(items.filter { $0.section == sec }) { c in
                Button(c.title) { c.run() }
                    .keyboardShortcut(c.shortcut)
                    .disabled(!c.enabled)
            }
        }
    }
}

/// Focus mode: the Work Cycles workspace, shown over the day while a session is live.
@MainActor
struct FocusView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.m) {
                Button { store.focusMode = false } label: { Label("Back to day", systemImage: "chevron.left") }
                    .buttonStyle(.borderless).foregroundColor(Theme.inkFaint)
                    .help("⇧⌘F or ⎋")
                Spacer()
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .background(Theme.paperDeep)
            CyclesView()
        }
        .background(Theme.paper)
    }
}

/// ⌨ in the top bar: the shortcuts that exist, from the same catalogue as the menus.
@MainActor
struct ShortcutsSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues: CommandCatalog.commands(store: store, engine: engine, openSettings: {}).map { ($0.id, $0) })
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard shortcuts").font(Theme.display(16)).foregroundColor(Theme.ink)
            ForEach(CommandCatalog.sheetRows, id: \.text) { row in
                let keys = row.ids.compactMap { byID[$0]?.shortcut?.display }.joined(separator: "  ")
                line(keys, row.text)
            }
            Divider().padding(.vertical, 4)
            Text("In the forms").font(TypeScale.label).foregroundColor(Theme.ink)
            ForEach(CommandCatalog.keyboardNotes, id: \.text) { note in line(note.keys, note.text) }
            Text("Everything else is in the command palette, ⌘P.").font(TypeScale.caption).foregroundColor(Theme.inkFaint).padding(.top, 4)
        }
        .padding(16).frame(width: 400).background(Theme.paper)
    }

    private func line(_ keys: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(keys).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(Theme.deep).frame(width: 130, alignment: .leading)
            Text(text).font(Theme.small).foregroundColor(Theme.ink)
        }
    }
}

/// The session's state, always in the top bar: ring, countdown, phase, cycle N of M.
/// Hover for pause / end; click to open Focus.
@MainActor
struct TimerPill: View {
    @EnvironmentObject var store: Store
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
                if let s = session, let goal = s.cycles.indices.contains(s.currentCycle) ? s.cycles[s.currentCycle].goal : nil, !goal.isEmpty, engine.phase == .working {
                    Text(goal).font(TypeScale.caption).foregroundColor(Theme.inkFaint).lineLimit(1).frame(maxWidth: 220, alignment: .leading)
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
        .onTapGesture { store.focusMode = true }
        .help("Open Focus  ⇧⌘F")
    }
}

@MainActor
struct MenuBarView: View {
    @EnvironmentObject var engine: CycleEngine
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = engine.session() {
                Text(s.title).font(Theme.display(16))
                let c = s.currentCycle
                if c < s.cycles.count, !s.cycles[c].goal.isEmpty {
                    Text("Cycle \(c + 1) of \(s.cycleCount): \(s.cycles[c].goal)")
                        .font(Theme.small).foregroundColor(Theme.inkFaint).lineLimit(3)
                }
            } else {
                Wordmark(size: 16)
                Text("Nothing running. Plan a deep block, then run cycles on it.")
                    .font(Theme.small).foregroundColor(Theme.inkFaint)
            }

            if engine.isRunning {
                Text(mmss(engine.remaining))
                    .font(.system(size: 40, weight: .semibold, design: .serif).monospacedDigit())
                    .foregroundColor(engine.phase == .working ? Theme.deep : Theme.breakC)
                HStack {
                    Button(engine.paused ? "Resume" : "Pause") { engine.togglePause() }.buttonStyle(QuietButtonStyle())
                    Button(engine.phase == .working ? "End cycle" : "End break") { engine.endNow() }.buttonStyle(QuietButtonStyle())
                }
            } else if engine.phase == .reviewing {
                Text("Cycle finished. Write the review in the app.").font(Theme.small)
            }

            Divider()
            Button("Open DeepCycles") {
                if engine.session() != nil { store.focusMode = true }
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }.buttonStyle(.borderless)
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 270)
        .background(Theme.paper)
    }
}
