import Foundation
import AppKit
import UserNotifications
import Combine

/// Drives the Work Cycles timer. Phases mirror the Ultraworking sheet:
/// planning (PLAN questions) → working (timer) → reviewing (REVIEW questions) → breaking → planning …
final class CycleEngine: ObservableObject {
    enum Phase { case idle, planning, working, reviewing, breaking, debrief }

    @Published var phase: Phase = .idle
    @Published var remaining: Int = 0
    @Published var paused = false
    @Published var sessionID: UUID? = nil
    @Published var sessionDateKey: String = ""

    weak var store: Store?
    private var timer: Timer?
    private var workedSeconds = 0
    private var notificationsReady = false

    var isRunning: Bool { phase == .working || phase == .breaking }

    var menuTitle: String {
        switch phase {
        case .working: return (paused ? "⏸ " : "● ") + mmss(remaining)
        case .breaking: return "☕️ " + mmss(remaining)
        case .reviewing: return "Review"
        case .planning: return "Plan cycle"
        default: return "DC"
        }
    }

    func session() -> CycleSession? {
        guard let id = sessionID, let store else { return nil }
        return store.plans[sessionDateKey]?.sessions.first { $0.id == id }
    }

    func attach(sessionID: UUID, dateKey: String) {
        if self.sessionID != sessionID { stop() }
        self.sessionID = sessionID
        self.sessionDateKey = dateKey
        if phase == .idle { phase = .planning }
    }

    func startWork(minutes: Int) {
        workedSeconds = 0
        remaining = minutes * 60
        paused = false
        phase = .working
        run()
    }

    func startBreak(minutes: Int) {
        remaining = minutes * 60
        paused = false
        phase = .breaking
        run()
    }

    func togglePause() { paused.toggle() }

    /// End the current work or break early.
    func endNow() { finish() }

    func stop() {
        timer?.invalidate()
        timer = nil
        phase = .idle
        remaining = 0
        paused = false
    }

    private func run() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        guard !paused else { return }
        remaining -= 1
        if phase == .working { workedSeconds += 1 }
        if remaining <= 0 { finish() }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        switch phase {
        case .working:
            recordWorkedSeconds()
            phase = .reviewing
            notify(title: "Cycle complete", body: "Take 2 minutes to review, then start your break.")
        case .breaking:
            phase = .planning
            notify(title: "Break over", body: "Plan the next cycle: what are you trying to accomplish?")
        default:
            break
        }
        NSSound.beep()
        NSApp.requestUserAttention(.informationalRequest)
    }

    private func recordWorkedSeconds() {
        guard let store, let id = sessionID, var plan = store.plans[sessionDateKey],
              let s = plan.sessions.firstIndex(where: { $0.id == id }) else { return }
        let c = plan.sessions[s].currentCycle
        guard c < plan.sessions[s].cycles.count else { return }
        plan.sessions[s].cycles[c].workedSeconds += workedSeconds
        store.plans[sessionDateKey] = plan
        workedSeconds = 0
    }

    // MARK: Notifications (only available when running as a real .app bundle)

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if notificationsReady { send() } else {
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] ok, _ in
                self?.notificationsReady = ok
                if ok { send() }
            }
        }
    }
}
