import Foundation
import Combine

/// What to tell the user when a cycle or a break ends.
package struct CycleAlert: Equatable {
    package let title: String
    package let body: String
}

/// Drives the Work Cycles timer. Phases mirror the Ultraworking sheet:
/// planning (PLAN questions) → working (timer) → reviewing (REVIEW questions) → breaking → planning …
/// Seconds worked are written into the session, through the store, when a cycle ends. Sound,
/// Dock bounce and notifications are the app's business: it sets `alert`.
@MainActor
package final class CycleEngine: ObservableObject {
    package enum Phase { case idle, planning, working, reviewing, breaking, debrief }

    /// Makes a repeating one-second timer that calls `fire` on the main actor. Tests inject their own.
    package typealias TimerFactory = (_ fire: @escaping @Sendable @MainActor () -> Void) -> Timer

    @Published package private(set) var phase: Phase = .idle
    @Published package private(set) var remaining: Int = 0
    @Published package private(set) var paused = false
    @Published package private(set) var sessionID: UUID? = nil
    @Published package private(set) var sessionDateKey: String = ""

    package weak var store: Store?
    /// Called when a work cycle or a break ends.
    package var alert: ((CycleAlert) -> Void)?

    private let makeTimer: TimerFactory
    private var timer: Timer?
    private var workedSeconds = 0

    package init(timer: @escaping TimerFactory = CycleEngine.wallClock) {
        makeTimer = timer
    }

    /// A real timer on the main run loop, in the common modes so it keeps ticking while a menu is open.
    package nonisolated static func wallClock(_ fire: @escaping @Sendable @MainActor () -> Void) -> Timer {
        let t = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { fire() } }
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    package var isRunning: Bool { phase == .working || phase == .breaking }

    package var menuTitle: String {
        switch phase {
        case .working: return (paused ? "⏸ " : "● ") + mmss(remaining)
        case .breaking: return "☕️ " + mmss(remaining)
        case .reviewing: return "Review"
        case .planning: return "Plan cycle"
        default: return "DC"
        }
    }

    package func session() -> CycleSession? {
        guard let id = sessionID, let store else { return nil }
        return store.session(id, dateKey: sessionDateKey)
    }

    package func attach(sessionID: UUID, dateKey: String) {
        if self.sessionID != sessionID { stop() }
        self.sessionID = sessionID
        self.sessionDateKey = dateKey
        if phase == .idle { phase = .planning }
    }

    package func startWork(minutes: Int) {
        workedSeconds = 0
        remaining = minutes * 60
        paused = false
        phase = .working
        run()
    }

    package func startBreak(minutes: Int) {
        remaining = minutes * 60
        paused = false
        phase = .breaking
        run()
    }

    package func togglePause() { paused.toggle() }

    /// End the current work or break early.
    package func endNow() { finish() }

    package func stop() {
        timer?.invalidate()
        timer = nil
        phase = .idle
        remaining = 0
        paused = false
    }

    private func run() {
        timer?.invalidate()
        timer = makeTimer { [weak self] in self?.tick() }
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
            alert?(CycleAlert(title: "Cycle complete", body: "Take 2 minutes to review, then start your break."))
        case .breaking:
            phase = .planning
            alert?(CycleAlert(title: "Break over", body: "Plan the next cycle: what are you trying to accomplish?"))
        default:
            break
        }
    }

    private func recordWorkedSeconds() {
        guard let store, let id = sessionID else { return }
        let seconds = workedSeconds
        store.updateSession(id, dateKey: sessionDateKey) { s in
            guard s.currentCycle < s.cycles.count else { return }
            s.cycles[s.currentCycle].workedSeconds += seconds
        }
        workedSeconds = 0
    }
}
