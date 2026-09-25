import Foundation
import TestKit
import DeepCyclesCore

@MainActor
final class AppStateTests: XCTestCase {
    func testNotificationSoundDefaultsToEnabled() {
        let suite = "DeepCyclesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = AppState(defaults: defaults)
        XCTAssertTrue(state.notificationSoundEnabled)
        XCTAssertEqual(state.appearance, .system)
    }

    func testNotificationSoundPreferencePersistsOffAndOn() {
        let suite = "DeepCyclesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = AppState(defaults: defaults)
        state.notificationSoundEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "notificationSoundEnabled"))
        let restored = AppState(defaults: defaults)
        XCTAssertFalse(restored.notificationSoundEnabled)

        restored.notificationSoundEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "notificationSoundEnabled"))
        XCTAssertTrue(AppState(defaults: defaults).notificationSoundEnabled)
    }
}
