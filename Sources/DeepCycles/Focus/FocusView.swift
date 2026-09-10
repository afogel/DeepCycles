import SwiftUI
import DeepCyclesCore

/// Focus mode: the Work Cycles workspace, shown over the day while a session is live.
@MainActor
struct FocusView: View {
    @EnvironmentObject var ui: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.m) {
                Button { ui.focusMode = false } label: { Label("Back to day", systemImage: "chevron.left") }
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
