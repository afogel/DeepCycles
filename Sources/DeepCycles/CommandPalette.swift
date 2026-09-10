import SwiftUI
import AppKit

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let group: String
    var shortcut: String = ""
    let run: () -> Void
}

/// ⌘P: type a few letters, Enter. Everything the menus can do, plus jumps to
/// documents, dates, blocks and sessions.
@MainActor
struct CommandPalette: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    @State private var keyMonitor: Any? = nil

    private var commands: [PaletteCommand] {
        var c: [PaletteCommand] = []
        func add(_ t: String, _ g: String, _ k: String = "", _ r: @escaping () -> Void) { c.append(PaletteCommand(title: t, group: g, shortcut: k, run: r)) }

        add("Go to Day", "Go", "⌘1") { store.tab = 0; store.focusMode = false }
        add("Go to Week", "Go", "⌘2") { store.tab = 1; store.focusMode = false }
        add("Go to Systems", "Go", "⌘3") { store.tab = 2; store.focusMode = false }
        add("Today", "Go", "⌘T") { store.selectedDate = Calendar.current.startOfDay(for: Date()) }
        add("Tomorrow", "Go") { store.selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))! }
        add("Yesterday", "Go") { store.selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))! }
        add(store.focusMode ? "Leave focus" : "Focus (cycles)", "Go", "⇧⌘F") { store.focusMode.toggle() }
        add("End day (shutdown)", "Go", "⇧⌘S") { store.showShutdown = true }

        add("New block", "Day", "⌘N") { store.tab = 0; store.focusMode = false; store.pending = .newBlock }
        add("Delete selected block", "Day", "⌫") { store.pending = .deleteBlock }
        add("Capture to Collection", "Day", "⌘K") { store.tab = 0; store.focusMode = false; store.pending = .focusCollection }
        add("Adopt calendar events as blocks", "Day", "⌘I") { store.tab = 0; store.pending = .importEvents }
        add("Sync blocks to calendar now", "Day", "⇧⌘P") { store.tab = 0; store.pending = .pushPlan }
        add("Move Collection to Tasks", "Day") { store.processCollection() }
        add("Toggle shutdown complete", "Day") { store.today.shutdownComplete.toggle() }

        for b in store.today.blocks where b.kind == .deep {
            if let s = store.session(forBlock: b.id) {
                add("Open cycles: \(b.title)", "Sessions", "\(s.cyclesDone)/\(s.cycleCount)") { engine.attach(sessionID: s.id, dateKey: store.selectedKey); store.focusMode = true }
            } else {
                add("Run cycles on: \(b.title)", "Sessions", b.start.shortTime) {
                    let s = CycleSession.fitting(block: b); store.today.sessions.append(s)
                    engine.attach(sessionID: s.id, dateKey: store.selectedKey); store.focusMode = true
                }
            }
        }
        add("Start cycle", "Cycle", "⌘↩") { store.focusMode = true; store.pending = .startCycle }
        if engine.isRunning {
            add(engine.paused ? "Resume timer" : "Pause timer", "Cycle", "⌘.") { engine.togglePause() }
            add(engine.phase == .breaking ? "End break" : "End cycle early", "Cycle", "⇧⌘E") { engine.endNow() }
        }

        add("Root document", "Systems") { store.systemsPage = "root"; store.tab = 2; store.focusMode = false }
        add("Weekly plan & values plan", "Systems") { store.tab = 1; store.focusMode = false }
        for d in store.system.docs { add(d.title, "Systems") { store.systemsPage = d.kind.rawValue; store.tab = 2; store.focusMode = false } }
        add("Disciplines", "Systems") { store.systemsPage = "disciplines"; store.tab = 2; store.focusMode = false }
        add("Session log", "Systems") { store.systemsPage = "sessions"; store.tab = 2; store.focusMode = false }
        add("Appearance: System", "Settings") { store.appearance = .system }
        add("Appearance: Light", "Settings") { store.appearance = .light }
        add("Appearance: Dark", "Settings") { store.appearance = .dark }
        return c
    }

    private var matches: [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = commands
        guard !q.isEmpty else { return all }
        return all.filter { fuzzy(q, in: $0.title.lowercased()) || $0.group.lowercased().hasPrefix(q) }
    }

    /// Subsequence match: "gtw" matches "go to week".
    private func fuzzy(_ q: String, in text: String) -> Bool {
        if text.contains(q) { return true }
        var it = text.makeIterator()
        for ch in q {
            var found = false
            while let t = it.next() { if t == ch { found = true; break } }
            if !found { return false }
        }
        return true
    }

    var body: some View {
        let list = matches
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                Image(systemName: "command").foregroundColor(Theme.inkFaint)
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { run(list) }
                Text("↑↓ move · ↩ run · esc").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }
            .padding(Space.l)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(list.prefix(40).enumerated()), id: \.element.id) { i, cmd in
                            HStack {
                                Text(cmd.group).font(TypeScale.caption).foregroundColor(Theme.inkFaint).frame(width: 64, alignment: .leading)
                                Text(cmd.title).font(TypeScale.body).foregroundColor(Theme.ink)
                                Spacer()
                                Text(cmd.shortcut).font(TypeScale.caption.monospacedDigit()).foregroundColor(Theme.inkFaint)
                                if i < 9 { Text("⌘\(i + 1)").font(TypeScale.caption.monospacedDigit()).foregroundColor(Theme.inkFaint.opacity(0.6)).frame(width: 28, alignment: .trailing) }
                            }
                            .padding(.horizontal, Space.l).padding(.vertical, 7)
                            .background(i == selection ? Theme.deep.opacity(0.14) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = i; run(list) }
                            .id(i)
                        }
                        if list.isEmpty { Text("No matches").font(TypeScale.caption).foregroundColor(Theme.inkFaint).padding() }
                    }
                    .padding(.vertical, Space.xs)
                }
                .onChange(of: selection) { proxy.scrollTo($0) }
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 520)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onAppear {
            selection = 0; query = ""
            // Focus can't land while the overlay is still being inserted; ask again on the next runloop turns.
            focused = true
            for delay in [0.03, 0.12, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { if store.showPalette, !focused { focused = true } }
            }
            NSApp.keyWindow?.makeFirstResponder(nil)
            // Arrow keys, ctrl-N/P, Return and Escape, independent of which view has focus.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                let list = matches
                let ctrl = e.modifierFlags.contains(.control)
                if !focused, e.keyCode != 53, !e.modifierFlags.contains(.command), !ctrl,
                   let ch = e.characters, !ch.isEmpty, ch.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                    query += ch; focused = true; return nil          // swallow the keystroke into the query
                }
                switch e.keyCode {
                case 125: move(1, in: list); return nil                                    // ↓
                case 126: move(-1, in: list); return nil                                   // ↑
                case 48:  move(e.modifierFlags.contains(.shift) ? -1 : 1, in: list); return nil   // tab / shift-tab
                case 36, 76: run(list); return nil                                          // return / enter
                case 53:  store.showPalette = false; return nil                             // esc
                default: break
                }
                if ctrl, let ch = e.charactersIgnoringModifiers {
                    if ch == "n" || ch == "j" { move(1, in: list); return nil }
                    if ch == "p" || ch == "k" { move(-1, in: list); return nil }
                }
                if e.modifierFlags.contains(.command), let ch = e.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n) {
                    if n - 1 < list.count { selection = n - 1; run(list) }
                    return nil
                }
                return e
            }
        }
        .onDisappear { if let m = keyMonitor { NSEvent.removeMonitor(m) }; keyMonitor = nil }
        .onChange(of: query) { _ in selection = 0 }
    }

    private func move(_ delta: Int, in list: [PaletteCommand]) {
        guard !list.isEmpty else { return }
        let n = min(list.count, 40)
        selection = (selection + delta + n) % n
    }

    private func run(_ list: [PaletteCommand]) {
        guard !list.isEmpty else { return }
        let cmd = list[min(selection, list.count - 1)]
        store.showPalette = false
        cmd.run()
    }
}
