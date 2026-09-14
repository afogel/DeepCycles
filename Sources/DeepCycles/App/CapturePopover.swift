import SwiftUI
import DeepCyclesCore

/// ⌘K or the tray icon in the top bar, from any page and from inside a running cycle: a thought
/// goes into today's Collection without leaving the block. Return adds it and clears the field
/// for the next one; Escape or a click outside closes.
@MainActor
struct CapturePopover: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
    @State private var text = ""
    @FocusState private var focused: Bool

    private var open: [TaskItem] { store.collection().filter { !$0.done } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Collection").font(TypeScale.title).foregroundColor(Theme.ink)
                Spacer()
                Text("↩ add · ⎋ close").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }
            TextField("Capture a thought, then back to the block", text: $text)
                .font(TypeScale.body)
                .focused($focused)
                .onSubmit(add)
                .inputChrome(vertical: Space.s)

            if open.isEmpty {
                Text("Nothing captured today yet.").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(open.suffix(5).reversed()) { t in
                        HStack(spacing: Space.s) {
                            Circle().stroke(Theme.inkFaint, lineWidth: 1).frame(width: 8, height: 8)
                            Text(t.text).font(TypeScale.caption).foregroundColor(Theme.ink).lineLimit(1)
                        }
                    }
                    if open.count > 5 {
                        Text("+\(open.count - 5) more").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                    }
                }
            }

            Text(Calendar.current.isDateInToday(store.selectedDate)
                 ? "Processed into Tasks at shutdown."
                 : "Lands in today's Collection, not the day you're looking at.")
                .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
        }
        .padding(Space.l)
        .frame(width: 340)
        .background(Theme.paper)
        .onAppear {
            text = ""
            // The field can't take focus until the popover has settled; ask again a moment later.
            focused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { if ui.showCapture { focused = true } }
        }
        .onExitCommand { ui.showCapture = false }
    }

    private func add() {
        if store.capture(text) { text = "" }
    }
}
