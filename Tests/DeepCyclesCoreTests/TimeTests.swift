import Foundation
import TestKit
import DeepCyclesCore

final class TimeTests: XCTestCase {
    func testMMSS() {
        XCTAssertEqual(mmss(0), "00:00")
        XCTAssertEqual(mmss(65), "01:05")
        XCTAssertEqual(mmss(-5), "00:00")
        XCTAssertEqual(mmss(3600), "60:00")
    }

    func testRoundedToQuarterHours() {
        XCTAssertEqual(date(2026, 3, 10, 10, 7).rounded(toMinutes: 15), date(2026, 3, 10, 10, 0))
        XCTAssertEqual(date(2026, 3, 10, 10, 8).rounded(toMinutes: 15), date(2026, 3, 10, 10, 15))
        XCTAssertEqual(date(2026, 3, 10, 10, 53).rounded(toMinutes: 15), date(2026, 3, 10, 11, 0))
    }

    func testDayKeys() {
        XCTAssertEqual(DateKeys.day(date(2026, 3, 10, 15, 30)), "2026-03-10")
        XCTAssertEqual(DateKeys.date(fromDay: "2026-03-10"), date(2026, 3, 10))
        XCTAssertNil(DateKeys.date(fromDay: "not a day"))
    }

    func testISOWeekKeys() {
        XCTAssertEqual(DateKeys.week(date(2026, 3, 10)), "2026-W11")
        XCTAssertEqual(DateKeys.week(date(2024, 12, 30)), "2025-W01")   // a Monday that belongs to the next year's week 1
        XCTAssertEqual(DateKeys.week(date(2027, 1, 1)), "2026-W53")     // a Friday still in the old year's last week
    }
}
