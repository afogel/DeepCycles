import Foundation
import TestKit
import DeepCyclesCore

/// The JSON files must keep loading as the model grows: missing keys get defaults, and the
/// old free-text fields migrate into items exactly once.
final class CodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func encodeToString<T: Encodable>(_ value: T) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return String(decoding: try enc.encode(value), as: UTF8.self)
    }

    func testLegacyCollectionTextBecomesCapturedItems() throws {
        let plan = try decode(DayPlan.self, #"{"blocks":[],"sessions":[],"collection":"call Sam\n\n  buy milk ","workStartHour":7}"#)
        XCTAssertEqual(plan.captured.map(\.text), ["call Sam", "buy milk"])
        XCTAssertEqual(plan.collection, "")
        XCTAssertEqual(plan.workStartHour, 7)
        XCTAssertEqual(plan.workEndHour, 18)
        XCTAssertFalse(plan.shutdownComplete)
    }

    func testEmptyDayPlanDecodes() throws {
        let plan = try decode(DayPlan.self, "{}")
        XCTAssertTrue(plan.blocks.isEmpty)
        XCTAssertTrue(plan.sessions.isEmpty)
    }

    func testTargetOutcomeKeepsItsStringForm() throws {
        var c = WorkCycle()
        c.completed = .half
        XCTAssertTrue(try encodeToString(c).contains(#""completed":"Half""#))
        c.completed = nil
        XCTAssertTrue(try encodeToString(c).contains(#""completed":"""#))
    }

    func testLegacyWorkCycleDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","goal":"g","startPlan":"","hazards":"","energy":4,"morale":2,"completed":"Yes","noteworthy":"","distractions":"","improvements":"","workedSeconds":1200}"#
        let c = try decode(WorkCycle.self, json)
        XCTAssertEqual(c.completed, .yes)
        XCTAssertEqual(c.energy, 4)
        XCTAssertEqual(c.workedSeconds, 1200)
        let unanswered = try decode(WorkCycle.self, #"{"completed":""}"#)
        XCTAssertNil(unanswered.completed)
        XCTAssertEqual(unanswered.morale, 3)
    }

    func testWorkCycleRoundTrips() throws {
        var c = WorkCycle()
        c.goal = "Write"
        c.completed = .no
        c.workedSeconds = 77
        let back = try decode(WorkCycle.self, try encodeToString(c))
        XCTAssertEqual(back, c)
    }

    func testLegacyTasksDocumentBecomesTaskItems() throws {
        let json = #"{"docs":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"tasks","title":"Tasks","text":"Captured tasks, processed from the daily Collection at shutdown.\n— header\nCall Sam\nBuy milk\n","updated":700000000}]}"#
        let docs = try decode(SystemDocs.self, json)
        XCTAssertEqual(docs.tasks.map(\.text), ["Call Sam", "Buy milk"])
        XCTAssertEqual(docs.doc(.tasks)?.text, "")
        XCTAssertEqual(docs.disciplines.map(\.code), ["DW"])   // the default stays when the key is absent
    }

    func testFreshSystemDocsHaveTheFiveDocuments() throws {
        let docs = try decode(SystemDocs.self, "{}")
        XCTAssertEqual(docs.docs.map(\.kind), CoreDoc.Kind.allCases)
        XCTAssertEqual(docs.defaultWorkStartHour, 8)
        XCTAssertEqual(docs.defaultWorkEndHour, 18)
    }

    func testTimeBlockDecodesWithoutOptionalFields() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Deep","start":700000000,"end":700003600,"kind":"deep"}"#
        let b = try decode(TimeBlock.self, json)
        XCTAssertEqual(b.minutes, 60)
        XCTAssertEqual(b.notes, "")
        XCTAssertFalse(b.fromCalendar)
        XCTAssertTrue(b.taskIDs.isEmpty)
    }

    func testPlansFileRoundTrips() throws {
        var plan = DayPlan()
        plan.blocks = [block("A", on: date(2026, 3, 10), from: (9, 0), to: (10, 0))]
        var s = CycleSession.fitting(block: plan.blocks[0])
        s.ensureCycles()
        s.cycles[0].completed = .yes
        plan.sessions = [s]
        plan.logDiscipline(UUID(), "2.5")
        let data = try JSONEncoder().encode(["2026-03-10": plan])
        let back = try XCTUnwrap(try JSONDecoder().decode([String: DayPlan].self, from: data)["2026-03-10"])
        XCTAssertEqual(back.blocks, plan.blocks)
        XCTAssertEqual(back.sessions, plan.sessions)
        XCTAssertEqual(back.disciplineLog, plan.disciplineLog)
    }
}
