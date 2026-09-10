import SwiftUI
import DeepCyclesCore

/// The menu-bar extra: countdown, pause / end, and a way back into the app.
@MainActor
struct MenuBarView: View {
    @EnvironmentObject var engine: CycleEngine
    @EnvironmentObject var ui: AppState

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
                if engine.session() != nil { ui.focusMode = true }
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
