import SwiftUI
import DeepCyclesCore

/// ⌨ in the top bar: the shortcuts that exist, from the same catalogue as the menus.
@MainActor
struct ShortcutsSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
    @EnvironmentObject var engine: CycleEngine

    var body: some View {
        let all = CommandCatalog.commands(store: store, ui: ui, engine: engine, openSettings: {})
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
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
