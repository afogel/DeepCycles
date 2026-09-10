import SwiftUI
import DeepCyclesCore

/// Focus mode: the day's sessions on the left, the selected session's three steps on the right.
/// Keyboard: Tab through everything; the session list takes ↑↓ ↩ ⌫; ⌘↩ is the next step;
/// ⇧⌘N a new session; ⎋ back to the day. Selection lives in AppState so menus and the
/// palette can drive it (see SessionFlow).
@MainActor
struct CyclesView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
    @EnvironmentObject var engine: CycleEngine
    @FocusState private var listFocused: Bool

    private var flow: SessionFlow { SessionFlow(store: store, ui: ui, engine: engine) }
    private var selectedID: UUID? { ui.focusSessionID }

    var body: some View {
        HStack(spacing: 0) {
            sessionList.frame(width: 250).background(Theme.paperDeep)
            if let id = selectedID, store.today.sessions.contains(where: { $0.id == id }) {
                SessionView(session: binding(for: id), stage: $ui.focusStage)
            } else {
                emptyState
            }
        }
        .onAppear { ensureSelection(); handle(ui.pending) }
        .onChange(of: store.today.sessions.count) { ensureSelection() }
        .onChange(of: engine.sessionID) { followEngine() }
        .onChange(of: store.selectedDate) { ui.focusSessionID = nil; ensureSelection() }
        .onChange(of: ui.pending) { handle(ui.pending) }
        .onExitCommand { ui.focusMode = false }
    }

    /// Commands from the menus / palette that only Focus can carry out.
    private func handle(_ cmd: PendingCommand?) {
        switch cmd {
        case .primaryAction:
            ui.pending = nil
            flow.performPrimary()
        case .newSession:
            ui.pending = nil
            flow.newSession(from: flow.nextFreeDeepBlock())
        default:
            break
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No session yet").font(Theme.display(22)).foregroundColor(Theme.ink)
            Text("A session is one deep-work block executed as 30-minute cycles with 10-minute breaks.\nPick a deep block below, or start a standalone session.")
                .multilineTextAlignment(.center).foregroundColor(Theme.inkFaint).frame(maxWidth: 380)
            let deepBlocks = freeDeepBlocks
            HStack {
                if deepBlocks.isEmpty {
                    Button("Plan a deep block first") { ui.go(.day) }.buttonStyle(InkButtonStyle())
                } else {
                    ForEach(deepBlocks) { b in
                        Button("\(b.start.shortTime) \(b.title)") { flow.newSession(from: b) }.buttonStyle(InkButtonStyle())
                    }
                }
                Button("Standalone session") { flow.newSession(from: nil) }.buttonStyle(QuietButtonStyle())
            }
            Text("⌘↩ starts a session for the next deep block · ⇧⌘N new session")
                .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var freeDeepBlocks: [TimeBlock] {
        store.today.blocks.filter { $0.kind == .deep && store.session(forBlock: $0.id) == nil }
    }

    // MARK: Selection

    /// Keep a valid selection: the running session if it is on this day, else the first live one.
    private func ensureSelection() {
        let sessions = store.today.sessions
        if let id = selectedID, sessions.contains(where: { $0.id == id }) { return }
        if let running = engine.sessionID, engine.sessionDateKey == store.selectedKey,
           let s = sessions.first(where: { $0.id == running }) {
            flow.select(s)
        } else if let s = flow.listOrder.first {
            flow.select(s)
        } else {
            ui.focusSessionID = nil
        }
    }

    /// The timer was attached to a session on this day: show it.
    private func followEngine() {
        guard let running = engine.sessionID, engine.sessionDateKey == store.selectedKey,
              let s = store.today.sessions.first(where: { $0.id == running }), selectedID != running else { return }
        flow.select(s)
    }

    private func binding(for id: UUID) -> Binding<CycleSession> {
        Binding(
            get: { store.today.sessions.first { $0.id == id } ?? CycleSession() },
            set: { new in
                if let i = store.today.sessions.firstIndex(where: { $0.id == id }) { store.today.sessions[i] = new }
            }
        )
    }

    // MARK: Session list

    private var sessionList: some View {
        let list = flow.listOrder
        let live = list.filter { !$0.finished }
        let done = list.filter { $0.finished }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading("Sessions")
                Spacer()
                Text("↑↓ · ↩ · ⌫").font(TypeScale.caption).foregroundColor(Theme.inkFaint).opacity(listFocused ? 1 : 0)
            }
            .padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(live) { s in row(s) }
                    if !done.isEmpty {
                        Text("Done today").font(TypeScale.caption).foregroundColor(Theme.inkFaint).padding(.top, 10).padding(.leading, 4)
                        ForEach(done) { s in row(s).opacity(0.75) }
                    }
                    if list.isEmpty {
                        Text("Sessions live with their day; older ones are in Systems → Session log.")
                            .font(TypeScale.caption).foregroundColor(Theme.inkFaint).padding(4)
                    }
                }
                .padding(.horizontal, 12)
            }
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { flow.selectAdjacent(-1); return .handled }
            .onKeyPress(.downArrow) { flow.selectAdjacent(1); return .handled }
            .onKeyPress(.return) {
                guard selectedID != nil else { return .ignored }
                ui.requestFormFocus()
                return .handled
            }
            .onKeyPress(.delete) {
                guard let id = selectedID else { return .ignored }
                flow.delete(id)
                return .handled
            }
            .accessibilityLabel("Sessions")
            Spacer()
            newSessionMenu
        }
    }

    private func row(_ s: CycleSession) -> some View {
        SessionRowView(session: s, isSelected: selectedID == s.id, listFocused: listFocused) {
            flow.delete(s.id)
        }
        .onTapGesture { flow.select(s); listFocused = true }
    }

    private var newSessionMenu: some View {
        let deepBlocks = freeDeepBlocks
        return Menu {
            Button("Standalone session") { flow.newSession(from: nil) }
            if !deepBlocks.isEmpty { Divider() }
            ForEach(deepBlocks) { b in
                Button("\(b.start.shortTime)  \(b.title)  (\(b.minutes) min)") { flow.newSession(from: b) }
            }
        } label: { Label("New session", systemImage: "plus") }
        .menuStyle(.borderlessButton)
        .help("⇧⌘N: a session for the next deep block")
        .padding(16)
    }
}

@MainActor
private struct SessionRowView: View {
    let session: CycleSession
    let isSelected: Bool
    let listFocused: Bool
    let onDelete: () -> Void
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine
    @State private var hover = false

    var body: some View {
        let s = session
        let live = engine.sessionID == s.id && engine.isRunning
        let block = store.today.blocks.first { $0.id == s.blockID }
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(s.title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink).lineLimit(1)
                Spacer()
                if hover {
                    Button(action: onDelete) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.inkFaint) }
                        .buttonStyle(.plain).help("Delete session")
                } else if s.finished { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.breakC) }
                else if live { Circle().fill(Theme.nowLine).frame(width: 8, height: 8) }
            }
            SessionPulse(session: s, compact: true)
            Text((block.map { "\($0.start.shortTime)–\($0.end.shortTime) · " } ?? "") + "\(s.cycleCount) × \(s.cycleMinutes) min" + (s.deepMinutes > 0 ? " · \(s.deepMinutes) min done" : ""))
                .font(Theme.small).foregroundColor(Theme.inkFaint)
        }
        .padding(10)
        .background(isSelected ? Theme.paper : Theme.paper.opacity(hover ? 0.6 : 0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .focusRing(isSelected && listFocused, shape: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu { Button("Delete session", action: onDelete) }
    }
}
