import Foundation
import TestKit
import DeepCyclesCore

final class DisciplineTests: XCTestCase {
    func testANumberDisciplineIsHitAtOrAboveItsTarget() {
        let dw = Discipline(code: "DW", name: "Deep work", isNumber: true, target: "3")
        XCTAssertTrue(dw.isHit("3"))
        XCTAssertTrue(dw.isHit("4.5"))
        XCTAssertFalse(dw.isHit("2.9"))
        XCTAssertFalse(dw.isHit("0"))
        XCTAssertFalse(dw.isHit(""))
        let untargeted = Discipline(code: "CC", isNumber: true)
        XCTAssertTrue(untargeted.isHit("1"))
        XCTAssertFalse(untargeted.isHit("0"))
    }

    func testADidItDisciplineIsHitWhenLoggedAsOne() {
        let d = Discipline(code: "EX", name: "Exercise")
        XCTAssertTrue(d.isHit("1"))
        XCTAssertFalse(d.isHit("0"))
        XCTAssertFalse(d.isHit(""))
    }

    func testDayPlanKeepsDisciplinesAndValueTicksApart() {
        var p = DayPlan()
        let id = UUID()
        XCTAssertEqual(p.discipline(id), "")
        XCTAssertFalse(p.valueDone(id))
        p.setDisciplineDone(id, true)
        XCTAssertTrue(p.disciplineDone(id))
        XCTAssertFalse(p.valueDone(id))
        p.setValueDone(id, true)
        XCTAssertTrue(p.valueDone(id))
        p.logDiscipline(id, "2.5")
        XCTAssertEqual(p.discipline(id), "2.5")
        XCTAssertTrue(p.valueDone(id))
        XCTAssertEqual(p.disciplineLog.count, 2)
    }
}
