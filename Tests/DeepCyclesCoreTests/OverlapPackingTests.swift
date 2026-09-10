import Foundation
import TestKit
import DeepCyclesCore

final class OverlapPackingTests: XCTestCase {
    let day = date(2026, 3, 10)

    func testDisjointBlocksEachGetTheFullWidth() {
        let a = block(on: day, from: (9, 0), to: (10, 0))
        let b = block(on: day, from: (10, 0), to: (11, 0))
        let p = packOverlaps([a, b])
        XCTAssertEqual(p[a.id], LanePlacement(col: 0, cols: 1))
        XCTAssertEqual(p[b.id], LanePlacement(col: 0, cols: 1))
    }

    func testOverlappingBlocksSitSideBySide() {
        let a = block(on: day, from: (9, 0), to: (10, 0))
        let b = block(on: day, from: (9, 30), to: (10, 30))
        let p = packOverlaps([b, a])          // input order must not matter
        XCTAssertEqual(p[a.id], LanePlacement(col: 0, cols: 2))
        XCTAssertEqual(p[b.id], LanePlacement(col: 1, cols: 2))
    }

    func testAColumnIsReusedOnceItsBlockHasEnded() {
        let a = block(on: day, from: (9, 0), to: (10, 0))
        let b = block(on: day, from: (9, 30), to: (10, 30))
        let c = block(on: day, from: (10, 0), to: (11, 0))
        let p = packOverlaps([a, b, c])
        XCTAssertEqual(p[c.id], LanePlacement(col: 0, cols: 2))
    }

    func testSeparateClustersDoNotShareColumns() {
        let a = block(on: day, from: (9, 0), to: (10, 0))
        let b = block(on: day, from: (9, 30), to: (10, 0))
        let c = block(on: day, from: (14, 0), to: (15, 0))
        let p = packOverlaps([a, b, c])
        XCTAssertEqual(p[a.id]?.cols, 2)
        XCTAssertEqual(p[c.id], LanePlacement(col: 0, cols: 1))
    }

    func testEmptyInput() {
        XCTAssertTrue(packOverlaps([]).isEmpty)
    }
}
