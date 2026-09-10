import Foundation
import TestKit
import DeepCyclesCore

@MainActor
final class SessionFlowTests: XCTestCase {
    /// A selected session at Prepare with `n` one-minute cycles and one-minute breaks.
    private func prepared(_ h: Harness, cycles n: Int = 2) -> CycleSession {
        var s = CycleSession()
        s.cycleMinutes = 1
        s.breakMinutes = 1
        s.cycleCount = n
        h.store.today.sessions = [s]
        h.flow.select(s)
        return s
    }

    func testNextFreeDeepBlockPrefersOneThatHasNotEnded() {
        let h = Harness()
        let morning = block("Morning", on: h.day, from: (9, 0), to: (11, 30))
        let afternoon = block("Afternoon", on: h.day, from: (14, 0), to: (15, 0))
        h.store.today.blocks = [afternoon, morning, block("Call", .meeting, on: h.day, from: (16, 0), to: (17, 0))]
        XCTAssertEqual(h.flow.nextFreeDeepBlock(now: date(2026, 3, 10, 10, 0))?.title, "Morning")
        XCTAssertEqual(h.flow.nextFreeDeepBlock(now: date(2026, 3, 10, 12, 0))?.title, "Afternoon")
        XCTAssertEqual(h.flow.nextFreeDeepBlock(now: date(2026, 3, 10, 18, 0))?.title, "Morning")   // all over: the first free one
        h.store.today.sessions = [CycleSession.fitting(block: morning)]
        XCTAssertEqual(h.flow.nextFreeDeepBlock(now: date(2026, 3, 10, 18, 0))?.title, "Afternoon")
    }

    func testPrimaryWithNoSelectionMakesASessionForTheNextFreeDeepBlock() {
        let h = Harness()
        let morning = block("Morning", on: h.day, from: (9, 0), to: (11, 30))
        h.store.today.blocks = [morning]
        XCTAssertEqual(h.flow.primaryTitle, "New Session")
        XCTAssertTrue(h.flow.primaryEnabled)
        h.flow.performPrimary()
        let s = h.flow.selected
        XCTAssertEqual(s?.blockID, morning.id)
        XCTAssertEqual(s?.cycleCount, 4)
        XCTAssertEqual(h.ui.focusStage, .prepare)
    }

    func testStageFollowsTheSessionsState() {
        let h = Harness()
        var s = CycleSession()
        s.ensureCycles()
        XCTAssertEqual(h.flow.stage(for: s), .prepare)
        s.accomplish = "Draft the intro"
        XCTAssertEqual(h.flow.stage(for: s), .work)
        s.finished = true
        XCTAssertEqual(h.flow.stage(for: s), .debrief)
        let fresh = CycleSession()
        h.store.today.sessions = [fresh]
        h.engine.attach(sessionID: fresh.id, dateKey: h.store.selectedKey)
        XCTAssertEqual(h.flow.stage(for: fresh), .work)
    }

    func testPrepareLeadsToPlanningTheFirstCycle() {
        let h = Harness()
        _ = prepared(h)
        XCTAssertEqual(h.ui.focusStage, .prepare)
        XCTAssertEqual(h.flow.primaryTitle, "Plan the First Cycle")
        h.flow.performPrimary()
        XCTAssertEqual(h.ui.focusStage, .work)
        XCTAssertEqual(h.flow.selected?.cycles.count, 2)
        XCTAssertEqual(h.engine.phase, .idle)        // planning is on paper; the timer starts with the cycle
    }

    func testTheWholeSessionOnThePrimaryAction() {
        let h = Harness()
        let s = prepared(h)
        h.flow.performPrimary()                       // Prepare → plan cycle 1
        XCTAssertEqual(h.flow.primaryTitle, "Start Cycle")
        h.flow.performPrimary()                       // start cycle 1
        XCTAssertEqual(h.engine.phase, .working)
        XCTAssertEqual(h.engine.sessionID, s.id)
        XCTAssertEqual(h.flow.primaryTitle, "Cycle Running")
        XCTAssertFalse(h.flow.primaryEnabled)
        h.flow.performPrimary()                       // ignored while the timer runs
        XCTAssertEqual(h.engine.phase, .working)
        h.clock.tick(60)                              // the timer ends → review
        XCTAssertEqual(h.engine.phase, .reviewing)
        XCTAssertFalse(h.flow.primaryEnabled)         // the target question is unanswered
        h.flow.performPrimary()
        XCTAssertEqual(h.engine.phase, .reviewing)
        XCTAssertEqual(h.flow.selected?.currentCycle, 0)
        h.store.today.sessions[0].cycles[0].completed = .yes
        XCTAssertTrue(h.flow.primaryEnabled)
        XCTAssertEqual(h.flow.primaryTitle, "Start Break")
        h.flow.performPrimary()                       // break
        XCTAssertEqual(h.engine.phase, .breaking)
        XCTAssertEqual(h.flow.selected?.currentCycle, 1)
        XCTAssertEqual(h.flow.primaryTitle, "Break Running")
        h.clock.tick(60)
        XCTAssertEqual(h.engine.phase, .planning)
        h.flow.performPrimary()                       // cycle 2
        XCTAssertEqual(h.engine.phase, .working)
        h.clock.tick(60)
        h.store.today.sessions[0].cycles[1].completed = .half
        XCTAssertEqual(h.flow.primaryTitle, "Finish and Debrief")
        h.flow.performPrimary()
        XCTAssertEqual(h.ui.focusStage, .debrief)
        XCTAssertEqual(h.engine.phase, .idle)
        XCTAssertEqual(h.flow.primaryTitle, "Finish Session")
        h.ui.focusMode = true
        h.flow.performPrimary()
        XCTAssertEqual(h.flow.selected?.finished, true)
        XCTAssertFalse(h.ui.focusMode)
        XCTAssertEqual(h.flow.primaryTitle, "Session Finished")
        XCTAssertFalse(h.flow.primaryEnabled)
        XCTAssertEqual(h.flow.selected?.deepMinutes, 2)
    }

    func testSkipBreakGoesStraightToPlanning() {
        let h = Harness()
        let s = prepared(h)
        h.flow.toPlan(s.id)
        h.flow.startCycle(s.id)
        h.clock.tick(60)
        h.store.today.sessions[0].cycles[0].completed = .no
        h.flow.skipBreak(s.id)
        XCTAssertEqual(h.engine.phase, .planning)
        XCTAssertEqual(h.flow.selected?.currentCycle, 1)
        XCTAssertFalse(h.engine.isRunning)
    }

    func testTheListPutsFinishedSessionsLastAndArrowsClamp() {
        let h = Harness()
        let early = block("Early", on: h.day, from: (8, 0), to: (9, 0))
        let mid = block("Mid", on: h.day, from: (10, 0), to: (11, 0))
        let late = block("Late", on: h.day, from: (14, 0), to: (15, 0))
        h.store.today.blocks = [early, mid, late]
        var done = CycleSession.fitting(block: early)
        done.finished = true
        h.store.today.sessions = [CycleSession.fitting(block: late), done, CycleSession.fitting(block: mid)]
        XCTAssertEqual(h.flow.listOrder.map(\.title), ["Mid", "Late", "Early"])
        h.flow.selectAdjacent(1)
        XCTAssertEqual(h.flow.selected?.title, "Mid")
        h.flow.selectAdjacent(1)
        XCTAssertEqual(h.flow.selected?.title, "Late")
        h.flow.selectAdjacent(1)
        XCTAssertEqual(h.flow.selected?.title, "Early")
        XCTAssertEqual(h.ui.focusStage, .debrief)       // a finished session opens on its debrief
        h.flow.selectAdjacent(1)
        XCTAssertEqual(h.flow.selected?.title, "Early")   // clamped at the end
        h.flow.selectAdjacent(-1)
        XCTAssertEqual(h.flow.selected?.title, "Late")
    }

    func testDeleteStopsTheTimerAndIsUndoable() {
        let h = Harness()
        let s = prepared(h)
        h.flow.toPlan(s.id)
        h.flow.startCycle(s.id)
        h.flow.delete(s.id)
        XCTAssertTrue(h.store.today.sessions.isEmpty)
        XCTAssertNil(h.ui.focusSessionID)
        XCTAssertEqual(h.engine.phase, .idle)
        XCTAssertTrue(h.store.undo())
        XCTAssertEqual(h.store.today.sessions.map(\.id), [s.id])
    }

    func testRunCyclesOpensFocusOnANewSession() {
        let h = Harness()
        let b = block("Chapter", on: h.day, from: (9, 0), to: (11, 30))
        h.store.today.blocks = [b]
        h.flow.runCycles(on: b)
        XCTAssertTrue(h.ui.focusMode)
        XCTAssertEqual(h.ui.focusStage, .prepare)
        XCTAssertEqual(h.flow.selected?.blockID, b.id)
        XCTAssertEqual(h.engine.sessionID, h.flow.selected?.id)
        XCTAssertEqual(h.engine.phase, .planning)
        XCTAssertNil(h.flow.nextFreeDeepBlock())        // the block now has its session
    }

    func testOpenLandsOnTheWorkStep() {
        let h = Harness()
        let s = CycleSession()
        h.store.today.sessions = [s]
        h.flow.open(s)
        XCTAssertTrue(h.ui.focusMode)
        XCTAssertEqual(h.ui.focusStage, .work)
        XCTAssertEqual(h.engine.sessionID, s.id)
    }
}
