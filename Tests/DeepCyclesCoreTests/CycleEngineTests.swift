import Foundation
import TestKit
import DeepCyclesCore

@MainActor
final class CycleEngineTests: XCTestCase {
    /// A harness with one two-cycle session (one-minute cycles and breaks) attached to the engine.
    private func attached() -> (Harness, CycleSession) {
        let h = Harness()
        var s = CycleSession()
        s.cycleMinutes = 1
        s.breakMinutes = 1
        s.cycleCount = 2
        s.ensureCycles()
        h.store.today.sessions = [s]
        h.engine.attach(sessionID: s.id, dateKey: h.store.selectedKey)
        return (h, s)
    }

    func testAttachStartsPlanning() {
        let (h, s) = attached()
        XCTAssertEqual(h.engine.phase, .planning)
        XCTAssertEqual(h.engine.sessionID, s.id)
        XCTAssertFalse(h.engine.isRunning)
        XCTAssertEqual(h.engine.session()?.id, s.id)
    }

    func testAWorkCycleCountsDownThenAsksForTheReview() {
        let (h, s) = attached()
        var alerts: [CycleAlert] = []
        h.engine.alert = { alerts.append($0) }
        h.engine.startWork(minutes: 1)
        XCTAssertEqual(h.engine.phase, .working)
        XCTAssertEqual(h.engine.remaining, 60)
        XCTAssertTrue(h.clock.isScheduled)
        h.clock.tick(59)
        XCTAssertEqual(h.engine.remaining, 1)
        XCTAssertEqual(h.engine.phase, .working)
        h.clock.tick()
        XCTAssertEqual(h.engine.phase, .reviewing)
        XCTAssertEqual(alerts.map(\.title), ["Cycle complete"])
        XCTAssertEqual(h.store.session(s.id, dateKey: h.store.selectedKey)?.cycles[0].workedSeconds, 60)
        XCTAssertEqual(h.engine.menuTitle, "Review")
    }

    func testPauseFreezesTheCountdown() {
        let (h, _) = attached()
        h.engine.startWork(minutes: 1)
        h.engine.togglePause()
        h.clock.tick(5)
        XCTAssertEqual(h.engine.remaining, 60)
        XCTAssertTrue(h.engine.paused)
        XCTAssertEqual(h.engine.menuTitle, "⏸ 01:00")
        h.engine.togglePause()
        h.clock.tick(5)
        XCTAssertEqual(h.engine.remaining, 55)
        XCTAssertEqual(h.engine.menuTitle, "● 00:55")
    }

    func testEndingEarlyRecordsThePartialCycle() {
        let (h, s) = attached()
        h.engine.startWork(minutes: 1)
        h.clock.tick(10)
        h.engine.endNow()
        XCTAssertEqual(h.engine.phase, .reviewing)
        XCTAssertEqual(h.store.session(s.id, dateKey: h.store.selectedKey)?.cycles[0].workedSeconds, 10)
    }

    func testABreakEndsInPlanning() {
        let (h, _) = attached()
        var alerts: [CycleAlert] = []
        h.engine.alert = { alerts.append($0) }
        h.engine.startBreak(minutes: 1)
        XCTAssertEqual(h.engine.phase, .breaking)
        XCTAssertTrue(h.engine.isRunning)
        XCTAssertEqual(h.engine.menuTitle, "☕️ 01:00")
        h.clock.tick(60)
        XCTAssertEqual(h.engine.phase, .planning)
        XCTAssertEqual(alerts.map(\.title), ["Break over"])
    }

    func testStopResetsEverything() {
        let (h, _) = attached()
        h.engine.startWork(minutes: 1)
        h.clock.tick(3)
        h.engine.stop()
        XCTAssertEqual(h.engine.phase, .idle)
        XCTAssertEqual(h.engine.remaining, 0)
        XCTAssertFalse(h.engine.paused)
        XCTAssertEqual(h.engine.menuTitle, "DC")
    }

    func testAttachingAnotherSessionStopsTheTimer() {
        let (h, _) = attached()
        h.engine.startWork(minutes: 1)
        let other = UUID()
        h.engine.attach(sessionID: other, dateKey: h.store.selectedKey)
        XCTAssertEqual(h.engine.sessionID, other)
        XCTAssertEqual(h.engine.phase, .planning)
        XCTAssertEqual(h.engine.remaining, 0)
    }

    func testFinishingWithoutCyclesDoesNotCrash() {
        let h = Harness()
        var s = CycleSession()
        s.cycleCount = 1            // cycles never padded
        h.store.today.sessions = [s]
        h.engine.attach(sessionID: s.id, dateKey: h.store.selectedKey)
        h.engine.startWork(minutes: 1)
        h.clock.tick(60)
        XCTAssertEqual(h.engine.phase, .reviewing)
    }
}
