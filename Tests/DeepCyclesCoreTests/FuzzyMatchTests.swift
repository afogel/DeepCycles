import Foundation
import TestKit
import DeepCyclesCore

final class FuzzyMatchTests: XCTestCase {
    func testSubstringsAndSubsequencesMatch() {
        XCTAssertTrue(FuzzyMatch.matches("week", in: "Go to Week"))
        XCTAssertTrue(FuzzyMatch.matches("gtw", in: "Go to Week"))
        XCTAssertTrue(FuzzyMatch.matches("", in: "anything"))
    }

    func testCharactersMustAppearInOrder() {
        XCTAssertFalse(FuzzyMatch.matches("wg", in: "go week"))
        XCTAssertFalse(FuzzyMatch.matches("xyz", in: "Go to Week"))
    }
}
