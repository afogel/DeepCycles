import SwiftUI
import DeepCyclesCore

/// Menus and hotkeys, generated from CommandCatalog.
struct AppCommands: Commands {
    @ObservedObject var store: Store
    @ObservedObject var ui: AppState
    @ObservedObject var engine: CycleEngine

    var body: some Commands {
        let cmds = CommandCatalog.commands(store: store, ui: ui, engine: engine, openSettings: {})
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
