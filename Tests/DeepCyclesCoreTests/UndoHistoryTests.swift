import Foundation
import TestKit
import DeepCyclesCore

final class UndoHistoryTests: XCTestCase {
    func testUndoThenRedo() {
        var h = UndoHistory<Int>()
        XCTAssertFalse(h.canUndo)
        h.record(1)                                 // the state was 1 and is about to become 2
        XCTAssertEqual(h.undo { _ in 2 }, 1)        // back to 1; 2 becomes redoable
        XCTAssertTrue(h.canRedo)
        XCTAssertFalse(h.canUndo)
        XCTAssertEqual(h.redo { _ in 1 }, 2)
        XCTAssertTrue(h.canUndo)
        XCTAssertFalse(h.canRedo)
    }

    func testRecordingForgetsTheRedoStack() {
        var h = UndoHistory<Int>()
        h.record(1)
        _ = h.undo { _ in 2 }
        h.record(3)
        XCTAssertFalse(h.canRedo)
    }

    func testTheLimitKeepsTheNewestSnapshots() {
        var h = UndoHistory<Int>(limit: 2)
        h.record(1); h.record(2); h.record(3)
        XCTAssertEqual(h.undo { $0 }, 3)
        XCTAssertEqual(h.undo { $0 }, 2)
        XCTAssertNil(h.undo { $0 })
    }
}
