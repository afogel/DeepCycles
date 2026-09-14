import Foundation
import TestKit
import DeepCyclesCore

@MainActor
final class StoreTests: XCTestCase {
    func testAFreshDayUsesTheDefaultHours() {
        let h = Harness()
        h.store.system.defaultWorkStartHour = 9
        h.store.system.defaultWorkEndHour = 17
        XCTAssertEqual(h.store.today.workStartHour, 9)
        XCTAssertEqual(h.store.today.workEndHour, 17)
        h.store.system.defaultWorkEndHour = 8
        XCTAssertEqual(h.store.freshDay().workEndHour, 10)   // never before the start
    }

    func testChangedDefaultHoursReachTodayAndTheDaysAhead() {
        let h = Harness()
        let yesterday = date(2026, 3, 9), tomorrow = date(2026, 3, 11), byHand = date(2026, 3, 12)
        h.store.plans[DateKeys.day(yesterday)] = h.store.freshDay()
        h.store.today.blocks.append(block(on: h.day, from: (9, 0), to: (10, 0)))   // today exists, on the defaults
        h.store.plans[DateKeys.day(tomorrow)] = h.store.freshDay()
        var own = h.store.freshDay()
        own.workStartHour = 6; own.workEndHour = 12
        h.store.plans[DateKeys.day(byHand)] = own

        let oldStart = h.store.system.defaultWorkStartHour
        h.store.system.defaultWorkStartHour = 7
        h.store.adoptDefaultHours(previousStart: oldStart, previousEnd: h.store.system.defaultWorkEndHour, from: h.day)

        XCTAssertEqual(h.store.today.workStartHour, 7)
        XCTAssertEqual(h.store.plan(for: tomorrow).workStartHour, 7)
        XCTAssertEqual(h.store.plan(for: yesterday).workStartHour, oldStart)   // the past keeps its grid
        XCTAssertEqual(h.store.plan(for: byHand).workStartHour, 6)             // a day set by hand keeps its own
    }

    func testWritingTodayCreatesThePlan() {
        let h = Harness()
        XCTAssertEqual(h.store.selectedKey, "2026-03-10")
        XCTAssertNil(h.store.plans[h.store.selectedKey])
        h.store.today.blocks.append(block(on: h.day, from: (9, 0), to: (10, 0)))
        XCTAssertEqual(h.store.plans[h.store.selectedKey]?.blocks.count, 1)
    }

    func testSessionsAreOrderedByTheirBlock() {
        let h = Harness()
        let late = block("Late", on: h.day, from: (14, 0), to: (15, 0))
        let early = block("Early", on: h.day, from: (9, 0), to: (10, 0))
        h.store.today.blocks = [late, early]
        var standalone = CycleSession()
        standalone.title = "Standalone"
        standalone.created = date(2026, 3, 10, 12, 0)
        h.store.today.sessions = [CycleSession.fitting(block: late), standalone, CycleSession.fitting(block: early)]
        XCTAssertEqual(h.store.today.orderedSessions.map(\.title), ["Early", "Standalone", "Late"])
    }

    func testTheSessionLogIsNewestFirstWithinTheWindow() {
        let h = Harness()
        func plan(_ title: String) -> DayPlan {
            var p = DayPlan()
            var s = CycleSession()
            s.title = title
            p.sessions = [s]
            return p
        }
        h.store.plans[DateKeys.day(date(2026, 3, 10))] = plan("today")
        h.store.plans[DateKeys.day(date(2026, 3, 8))] = plan("earlier")
        h.store.plans[DateKeys.day(date(2026, 1, 1))] = plan("old")
        let log = h.store.sessionLog(days: 30, now: date(2026, 3, 11))
        XCTAssertEqual(log.map(\.session.title), ["today", "earlier"])
    }

    func testUndoAndRedoRestoreTheDay() {
        let h = Harness()
        XCTAssertNil(h.store.undo())
        h.store.snapshot()
        h.store.today.blocks.append(block(on: h.day, from: (9, 0), to: (10, 0)))
        XCTAssertTrue(h.store.canUndo)
        XCTAssertNotNil(h.store.undo())
        XCTAssertTrue(h.store.today.blocks.isEmpty)
        XCTAssertTrue(h.store.canRedo)
        XCTAssertNotNil(h.store.redo())
        XCTAssertEqual(h.store.today.blocks.count, 1)
        h.store.snapshot()
        XCTAssertFalse(h.store.canRedo)
    }

    func testUndoSwitchesBackToTheDayItBelongsTo() {
        let h = Harness()
        h.store.snapshot()
        h.store.today.blocks.append(block(on: h.day, from: (9, 0), to: (10, 0)))
        h.store.selectedDate = date(2026, 3, 11)
        XCTAssertNotNil(h.store.undo())
        XCTAssertEqual(h.store.selectedDate, date(2026, 3, 10))
        XCTAssertTrue(h.store.today.blocks.isEmpty)
    }

    func testUndoRestoresTheWeekPlanReplacedByCopyLastWeek() {
        let h = Harness()                                   // 2026-03-10 is in week 11
        var last = WeekPlan()
        last.outcomes = [TaskItem(text: "Ship it"), TaskItem(text: "Done already", done: true)]
        last.weeklyPlan = "Push hard"
        h.store.system.weeks[DateKeys.week(date(2026, 3, 3))] = last
        var mine = WeekPlan()
        mine.weeklyPlan = "My own plan"
        h.store.thisWeek = mine

        h.store.snapshotWeek()
        h.store.thisWeek = h.store.lastWeek!.carriedForward()
        XCTAssertEqual(h.store.thisWeek.outcomes.map(\.text), ["Ship it"])
        XCTAssertEqual(h.store.thisWeek.weeklyPlan, "Push hard")

        h.store.selectedDate = date(2026, 3, 20)            // looking at another week: undo comes back
        XCTAssertNotNil(h.store.undo())
        XCTAssertEqual(h.store.selectedWeekKey, DateKeys.week(date(2026, 3, 10)))
        XCTAssertEqual(h.store.thisWeek.weeklyPlan, "My own plan")
        XCTAssertTrue(h.store.thisWeek.outcomes.isEmpty)
        XCTAssertNotNil(h.store.redo())
        XCTAssertEqual(h.store.thisWeek.outcomes.map(\.text), ["Ship it"])
    }

    func testChangesAreWrittenOnFlushAndReadBackByANewStore() {
        let h = Harness()
        h.store.today.blocks.append(block("Persisted", on: h.day, from: (9, 0), to: (10, 0)))
        h.store.system.root = "root text"
        XCTAssertTrue(h.store.hasUnsavedChanges)
        h.store.flush()
        XCTAssertFalse(h.store.hasUnsavedChanges)
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.store.directory.appendingPathComponent("plans.json").path))
        let again = Store(directory: h.store.directory)
        again.selectedDate = h.day
        XCTAssertEqual(again.today.blocks.map(\.title), ["Persisted"])
        XCTAssertEqual(again.system.root, "root text")
    }

    func testQuickCaptureGoesToTheActualDayNotTheOneBeingLookedAt() {
        let h = Harness()                                   // looking at 2026-03-10
        let now = date(2026, 3, 12, 10, 30)
        XCTAssertTrue(h.store.capture("  call Sam ", now: now))
        XCTAssertFalse(h.store.capture("   ", now: now))
        XCTAssertEqual(h.store.collection(now: now).map(\.text), ["call Sam"])
        XCTAssertTrue(h.store.today.captured.isEmpty)
        XCTAssertEqual(h.store.plans[DateKeys.day(now)]?.captured.count, 1)
    }

    func testProcessCollectionMovesOpenItemsOnly() {
        let h = Harness()
        h.store.today.captured = [TaskItem(text: "keep"), TaskItem(text: "done", done: true), TaskItem(text: "  ")]
        h.store.system.tasks = [TaskItem(text: "existing")]
        h.store.processCollection()
        XCTAssertEqual(h.store.system.tasks.map(\.text), ["keep", "existing"])
        XCTAssertTrue(h.store.today.captured.isEmpty)
    }

    func testValueTicksArePerDay() {
        let h = Harness()
        let id = UUID()
        h.store.setValueDone(id, on: h.day, true)
        XCTAssertTrue(h.store.valueDone(id, on: h.day))
        XCTAssertFalse(h.store.valueDone(id, on: date(2026, 3, 11)))
    }

    func testCurrentDeepBlockOnlyOnTheSelectedDay() {
        let h = Harness()
        let b = block(on: h.day, from: (9, 0), to: (10, 0))
        h.store.today.blocks = [b, block("Meeting", .meeting, on: h.day, from: (10, 0), to: (11, 0))]
        XCTAssertEqual(h.store.currentDeepBlock(now: date(2026, 3, 10, 9, 30))?.id, b.id)
        XCTAssertNil(h.store.currentDeepBlock(now: date(2026, 3, 10, 10, 0)))
        XCTAssertNil(h.store.currentDeepBlock(now: date(2026, 3, 11, 9, 30)))
    }

    func testUpdateSessionEditsInPlace() {
        let h = Harness()
        var s = CycleSession()
        s.ensureCycles()
        h.store.today.sessions = [s]
        h.store.updateSession(s.id, dateKey: h.store.selectedKey) { $0.cycles[0].workedSeconds = 120 }
        XCTAssertEqual(h.store.session(s.id, dateKey: h.store.selectedKey)?.cycles[0].workedSeconds, 120)
        h.store.updateSession(UUID(), dateKey: h.store.selectedKey) { $0.title = "never" }   // unknown id: no change
        XCTAssertEqual(h.store.today.sessions.count, 1)
    }

    func testDocumentEditsStampTheUpdateDate() throws {
        let h = Harness()
        let before = try XCTUnwrap(h.store.system.doc(.ideas)).updated
        h.store.setDocText(.ideas, "An idea")
        XCTAssertEqual(h.store.docText(.ideas), "An idea")
        XCTAssertTrue(try XCTUnwrap(h.store.system.doc(.ideas)).updated >= before)
    }

    func testTaskLookupSearchesTheWeeksToo() {
        let h = Harness()
        let t = TaskItem(text: "Outcome")
        var w = WeekPlan()
        w.outcomes = [t]
        h.store.thisWeek = w
        XCTAssertEqual(h.store.task(t.id)?.text, "Outcome")
        XCTAssertNil(h.store.task(UUID()))
    }

    func testCarryingAWeekForwardDropsDoneOutcomesAndUnticksHabits() {
        var w = WeekPlan()
        w.outcomes = [TaskItem(text: "open"), TaskItem(text: "done", done: true)]
        w.values = [TaskItem(text: "call a friend", done: true)]
        let next = w.carriedForward()
        XCTAssertEqual(next.outcomes.map(\.text), ["open"])
        XCTAssertNotEqual(next.outcomes[0].id, w.outcomes[0].id)
        XCTAssertEqual(next.values.map(\.done), [false])
    }
}
