import SwiftUI

/// Where a command appears in the menu bar. The palette lists everything.
enum MenuPlace { case edit, file, go, cycle }

/// One user-facing command. The menus, the command palette and the shortcuts sheet are all
/// generated from `CommandCatalog.commands`, so each shortcut is defined in exactly one place.
struct AppCommand: Identifiable {
    let id: String
    let title: String
    let group: String                  // palette grouping
    var shortcut: KeyboardShortcut? = nil
    var menu: MenuPlace? = nil
    var section: Int = 0               // menu separator grouping
    var enabled: Bool = true
    var inPalette: Bool = true
    let run: () -> Void
}

/// The one list of commands. Only what is used many times a day gets a shortcut; the
/// palette (⌘P) covers the rest by name.
enum CommandCatalog {
    static func commands(store: Store, engine: CycleEngine, openSettings: @escaping () -> Void) -> [AppCommand] {
        var out: [AppCommand] = []
        func add(_ id: String, _ title: String, _ group: String, _ key: KeyboardShortcut? = nil,
                 menu: MenuPlace? = nil, section: Int = 0, enabled: Bool = true, palette: Bool = true,
                 _ run: @escaping () -> Void) {
            out.append(AppCommand(id: id, title: title, group: group, shortcut: key, menu: menu,
                                  section: section, enabled: enabled, inPalette: palette, run: run))
        }
        let today = Calendar.current.startOfDay(for: Date())
        func go(_ tab: Int) { store.tab = tab; store.focusMode = false }
        func systems(_ page: String) { store.systemsPage = page; go(2) }

        // Edit
        add("edit.undo", "Undo", "Edit", .init("z"), menu: .edit, enabled: store.canUndo, palette: false) { store.undo() }
        add("edit.redo", "Redo", "Edit", .init("z", modifiers: [.command, .shift]), menu: .edit, enabled: store.canRedo, palette: false) { store.redo() }

        // Application-wide
        add("palette", "Command Palette…", "Go", .init("p"), menu: .file, palette: false) { store.showPalette.toggle() }
        add("settings", "Settings…", "Settings", .init(",")) { openSettings() }

        // Go
        add("go.day", "Day", "Go", .init("1"), menu: .go) { go(0) }
        add("go.week", "Week", "Go", .init("2"), menu: .go) { go(1) }
        add("go.systems", "Systems", "Go", .init("3"), menu: .go) { go(2) }
        add("go.focus", store.focusMode ? "Leave Focus" : "Focus (Cycles)", "Go", .init("f", modifiers: [.command, .shift]), menu: .go, section: 1) { store.focusMode.toggle() }
        add("go.endDay", "End Day…", "Go", menu: .go, section: 1) { store.showShutdown = true }
        add("go.tasks", "Tasks", "Go", menu: .go, section: 1, palette: false) { systems("tasks") }
        add("go.sessionLog", "Session Log", "Go", menu: .go, section: 1, palette: false) { systems("sessions") }
        add("go.prev", store.tab == 1 ? "Previous Week" : "Previous Day", "Go", .init("["), menu: .go, section: 2) { store.shiftPeriod(-1) }
        add("go.next", store.tab == 1 ? "Next Week" : "Next Day", "Go", .init("]"), menu: .go, section: 2) { store.shiftPeriod(1) }
        add("go.today", "Today", "Go", .init("t"), menu: .go, section: 2) { store.selectedDate = today }
        add("go.tomorrow", "Tomorrow", "Go") { store.selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today }
        add("go.yesterday", "Yesterday", "Go") { store.selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today }

        // Day
        add("day.newBlock", "New Block", "Day", .init("n"), menu: .file, section: 1) { go(0); store.pending = .newBlock }
        add("day.newSession", "New Session", "Sessions", .init("n", modifiers: [.command, .shift]), menu: .file, section: 1) {
            store.focusMode = true; store.pending = .newSession
        }
        add("day.deleteBlock", "Delete Block", "Day", .init(.delete), menu: .file, section: 1) { store.pending = .deleteBlock }
        add("day.capture", "Capture to Collection", "Day", .init("k"), menu: .file, section: 1) { go(0); store.pending = .focusCollection }
        add("day.adopt", "Adopt Calendar Events as Blocks", "Day", menu: .file, section: 2) { go(0); store.pending = .importEvents }
        add("day.sync", "Sync Blocks to Calendar Now", "Day", menu: .file, section: 2) { go(0); store.pending = .pushPlan }
        add("day.collect", "Move Collection to Tasks", "Day") { store.processCollection() }
        add("day.shutdown", store.today.shutdownComplete ? "Reopen the Day" : "Mark Shutdown Complete", "Day") { store.today.shutdownComplete.toggle() }

        // Sessions on today's deep blocks
        for b in store.today.blocks where b.kind == .deep {
            if let s = store.session(forBlock: b.id) {
                add("session.open.\(s.id)", "Open cycles: \(b.title)", "Sessions") { SessionFlow.open(store, engine, s) }
            } else {
                add("session.run.\(b.id)", "Run cycles on: \(b.title) (\(b.start.shortTime))", "Sessions") { SessionFlow.runCycles(on: b, store, engine) }
            }
        }
        add("session.standalone", "New Standalone Session", "Sessions") { store.focusMode = true; SessionFlow.newSession(store, from: nil) }

        // Cycle
        add("cycle.primary", SessionFlow.primaryTitle(store, engine), "Cycle", .init(.return),
            menu: .cycle, enabled: SessionFlow.primaryEnabled(store, engine)) {
            store.focusMode = true
            store.pending = .primaryAction
        }
        add("cycle.pause", engine.paused ? "Resume" : "Pause", "Cycle", .init("."), menu: .cycle, enabled: engine.isRunning) { engine.togglePause() }
        add("cycle.end", engine.phase == .breaking ? "End Break" : "End Cycle Early", "Cycle", .init("e", modifiers: [.command, .shift]),
            menu: .cycle, enabled: engine.isRunning) { engine.endNow() }

        if store.focusMode, let s = SessionFlow.selected(store) {
            if engine.sessionID == s.id, engine.phase == .reviewing, !SessionFlow.isLast(s) {
                add("cycle.skipBreak", "Skip Break", "Cycle", enabled: !SessionFlow.currentCycle(s).completed.isEmpty) { SessionFlow.skipBreak(store, engine, s.id) }
            }
            if store.focusStage == 1, !s.finished {
                add("cycle.debrief", "Stop Here and Debrief", "Cycle") { SessionFlow.toDebrief(store, engine, s.id) }
            }
            for (i, name) in ["Prepare", "Work", "Debrief"].enumerated() where i != store.focusStage {
                add("stage.\(i)", "Show \(name)", "Cycle") { store.focusStage = i; store.requestFormFocus() }
            }
            add("session.next", "Next Session", "Sessions") { SessionFlow.selectAdjacent(store, engine, 1) }
            add("session.prev", "Previous Session", "Sessions") { SessionFlow.selectAdjacent(store, engine, -1) }
            add("session.delete", "Delete Session: \(s.title)", "Sessions") { SessionFlow.delete(store, engine, s.id) }
        }

        // Systems
        add("systems.root", "Root Document", "Systems") { systems("root") }
        add("systems.week", "Weekly Plan & Values Plan", "Systems") { go(1) }
        for d in store.system.docs { add("systems.doc.\(d.kind.rawValue)", d.title, "Systems") { systems(d.kind.rawValue) } }
        add("systems.disciplines", "Disciplines", "Systems") { systems("disciplines") }
        add("systems.sessions", "Session Log", "Systems") { systems("sessions") }

        // Settings
        for a in Appearance.allCases { add("appearance.\(a.rawValue)", "Appearance: \(a.label)", "Settings") { store.appearance = a } }
        return out
    }

    /// Rows for the shortcuts sheet (⌨ in the top bar): which commands to show together, and how to word them.
    static let sheetRows: [(ids: [String], text: String)] = [
        (["palette"], "Command palette: everything, by name"),
        (["settings"], "Settings"),
        (["go.day", "go.week", "go.systems"], "Day · Week · Systems"),
        (["go.focus"], "Focus mode in / out (⎋ also leaves)"),
        (["go.prev", "go.next", "go.today"], "Previous · next · today"),
        (["day.newBlock", "day.deleteBlock"], "New block · delete the selected block"),
        (["edit.undo", "edit.redo"], "Undo · redo"),
        (["day.capture"], "Capture a thought to Collection"),
        (["day.newSession"], "New session for the next deep block"),
        (["cycle.primary"], "Next step: plan → start cycle → start break → debrief"),
        (["cycle.pause", "cycle.end"], "Pause / resume · end cycle or break early"),
    ]

    /// Keys that work inside the forms, without a menu item.
    static let keyboardNotes: [(keys: String, text: String)] = [
        ("⇥  ⇧⇥", "Move between fields and controls"),
        ("␣", "Press the focused button, switch or checkbox"),
        ("↑↓  ←→", "Move in lists, pickers, steppers and ratings"),
        ("1–5   Y H N", "Rate energy / morale · answer the target question"),
        ("↩  ⌫", "In the session list and the day grid: open · delete"),
    ]
}

extension KeyboardShortcut {
    /// "⇧⌘F"-style rendering for the shortcuts sheet and the palette.
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + KeyboardShortcut.name(of: key)
    }

    private static func name(of key: KeyEquivalent) -> String {
        let c = key.character
        switch c {
        case KeyEquivalent.return.character: return "↩"
        case KeyEquivalent.delete.character: return "⌫"
        case KeyEquivalent.escape.character: return "⎋"
        case KeyEquivalent.tab.character: return "⇥"
        case KeyEquivalent.space.character: return "␣"
        case KeyEquivalent.upArrow.character: return "↑"
        case KeyEquivalent.downArrow.character: return "↓"
        case KeyEquivalent.leftArrow.character: return "←"
        case KeyEquivalent.rightArrow.character: return "→"
        default: return String(c).uppercased()
        }
    }
}
