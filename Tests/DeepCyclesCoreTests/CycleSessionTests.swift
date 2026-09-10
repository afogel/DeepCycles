import Foundation
import TestKit
import DeepCyclesCore

final class CycleSessionTests: XCTestCase {
    let day = date(2026, 3, 10)

    func testFittingFillsTheBlockWithCyclePlusBreakPairs() {
        XCTAssertEqual(CycleSession.fitting(block: block(on: day, from: (9, 0), to: (11, 30))).cycleCount, 4)   // 150 min
        XCTAssertEqual(CycleSession.fitting(block: block(on: day, from: (9, 0), to: (12, 10))).cycleCount, 5)   // 190 min
        XCTAssertEqual(CycleSession.fitting(block: block(on: day, from: (9, 0), to: (10, 0))).cycleCount, 1)    // 60 min
    }

    func testFittingShortensCyclesForShortBlocks() {
        let s = CycleSession.fitting(block: block(on: day, from: (9, 0), to: (9, 25)))
        XCTAssertEqual(s.cycleMinutes, 20)
        XCTAssertEqual(s.cycleCount, 1)
        let tiny = CycleSession.fitting(block: block(on: day, from: (9, 0), to: (9, 5)))
        XCTAssertEqual(tiny.cycleMinutes, 10)
        XCTAssertEqual(tiny.cycleCount, 1)
    }

    func testFittingTakesTheBlocksTitleAndID() {
        let b = block("Chapter 3", on: day, from: (9, 0), to: (11, 30))
        let s = CycleSession.fitting(block: b)
        XCTAssertEqual(s.title, "Chapter 3")
        XCTAssertEqual(s.blockID, b.id)
    }

    func testEnsureCyclesPadsTrimsAndClamps() {
        var s = CycleSession()
        s.cycleCount = 3
        s.ensureCycles()
        XCTAssertEqual(s.cycles.count, 3)
        s.cycleCount = 2
        s.currentCycle = 2
        s.ensureCycles()
        XCTAssertEqual(s.cycles.count, 2)
        XCTAssertEqual(s.currentCycle, 1)
    }

    func testAdvanceStopsAtTheLastCycle() {
        var s = CycleSession()
        s.cycleCount = 2
        s.ensureCycles()
        XCTAssertFalse(s.isLastCycle)
        s.advance()
        XCTAssertEqual(s.currentCycle, 1)
        XCTAssertTrue(s.isLastCycle)
        s.advance()
        XCTAssertEqual(s.currentCycle, 1)
    }

    func testTotalsCountOnlyAnsweredCycles() {
        var s = CycleSession()
        s.cycleCount = 3
        s.ensureCycles()
        s.cycles[0].completed = .yes; s.cycles[0].workedSeconds = 1800
        s.cycles[1].completed = .half; s.cycles[1].workedSeconds = 900
        s.cycles[2].workedSeconds = 59
        XCTAssertEqual(s.cyclesDone, 2)
        XCTAssertEqual(s.deepMinutes, 45)
    }

    func testHasStartedNoticesAnyWork() {
        var s = CycleSession()
        s.ensureCycles()
        XCTAssertFalse(s.hasStarted)
        s.cycles[0].goal = "Outline"
        XCTAssertTrue(s.hasStarted)
        var t = CycleSession()
        t.accomplish = "Draft"
        XCTAssertTrue(t.hasStarted)
    }

    func testCurrentIsSafeWhenCyclesAreMissing() {
        var s = CycleSession()
        s.currentCycle = 4
        XCTAssertEqual(s.current.energy, 3)
    }
}
