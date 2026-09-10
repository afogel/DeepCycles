import SwiftUI
import AppKit

/// ⌘P: type a few letters, Enter. Everything the menus can do, plus jumps to
/// documents, dates, blocks and sessions. The list comes from CommandCatalog.
@MainActor
struct CommandPalette: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    @State private var keyMonitor: Any? = nil

    private var commands: [AppCommand] {
        CommandCatalog.commands(store: store, engine: engine, openSettings: { openSettings() })
            .filter { $0.inPalette && $0.enabled }
    }

    private var matches: [AppCommand] {
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
                                Text(cmd.shortcut?.display ?? "").font(TypeScale.caption.monospacedDigit()).foregroundColor(Theme.inkFaint)
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
                .onChange(of: selection) { proxy.scrollTo(selection) }
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
        .onChange(of: query) { selection = 0 }
    }

    private func move(_ delta: Int, in list: [AppCommand]) {
        guard !list.isEmpty else { return }
        let n = min(list.count, 40)
        selection = (selection + delta + n) % n
    }

    private func run(_ list: [AppCommand]) {
        guard !list.isEmpty else { return }
        let cmd = list[min(selection, list.count - 1)]
        store.showPalette = false
        cmd.run()
    }
}
