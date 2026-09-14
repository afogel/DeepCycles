import SwiftUI
import DeepCyclesCore

/// The menu-bar extra: countdown, pause / end, a capture field for the Collection, and a way
/// back into the app. Usable without bringing the window forward.
@MainActor
struct MenuBarView: View {
    @EnvironmentObject var engine: CycleEngine
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
    @State private var capture = ""
    @FocusState private var captureFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = engine.session() {
                Text(s.title).font(Theme.display(16))
                if !s.current.goal.isEmpty {
                    Text("Cycle \(s.currentCycle + 1) of \(s.cycleCount): \(s.current.goal)")
                        .font(Theme.small).foregroundColor(Theme.inkFaint).lineLimit(3)
                }
            } else {
                Wordmark(size: 16)
                Text("Nothing running. Plan a deep block, then run cycles on it.")
                    .font(Theme.small).foregroundColor(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
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

            // Quick capture into today's Collection, straight from the menu bar.
            VStack(alignment: .leading, spacing: 4) {
                TextField("Capture a thought…", text: $capture)
                    .textFieldStyle(.plain).font(TypeScale.body)
                    .focused($captureFocused)
                    .onSubmit { if store.capture(capture) { capture = "" } }
                    .padding(.horizontal, Space.s).padding(.vertical, 6)
                    .background(Theme.paperDeep)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                let open = store.collection().filter { !$0.done }.count
                Text(open == 0 ? "↩ adds it to today's Collection." : "\(open) in today's Collection, processed at shutdown.")
                    .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }

            Divider()
            Button("Open DeepCycles") {
                if engine.session() != nil { ui.focusMode = true }
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }.buttonStyle(.borderless)
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 270)
        .background(Theme.paper)
        .onAppear {
            captureFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { captureFocused = true }
        }
    }
}
