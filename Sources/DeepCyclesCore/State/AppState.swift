import Foundation
import Combine

/// What the window is showing: page, focus mode, sheets, the palette, and the Focus selection.
/// Nothing here is saved except the appearance preference. Menus and the palette change this
/// object; the views follow it. Persisted data lives in `Store`.
@MainActor
package final class AppState: ObservableObject {
    @Published package var tab: Tab = .day
    @Published package var focusMode = false          // a Work Cycles session has taken over the window
    @Published package var showShutdown = false       // the end-of-day sheet
    @Published package var showPalette = false        // command palette (⌘P)
    @Published package var systemsPage: SystemsPage = .week
    @Published package var pending: PendingCommand? = nil

    // Focus mode. Kept here so menus and the palette can drive the session list (see SessionFlow).
    @Published package var focusSessionID: UUID? = nil
    @Published package var focusStage: SessionStage = .prepare
    @Published package var formFocusTick: Int = 0     // bumped to put keyboard focus in the current step's first field

    @Published package var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }

    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
    }

    /// Show a page, leaving Focus if it was open.
    package func go(_ tab: Tab) {
        self.tab = tab
        focusMode = false
    }

    package func showSystems(_ page: SystemsPage) {
        systemsPage = page
        go(.systems)
    }

    /// Arrow navigation: a week at a time in week view, otherwise a day.
    package func shiftPeriod(_ direction: Int, in store: Store) {
        store.shiftDay(direction * (tab == .week ? 7 : 1))
    }

    /// Ask the Focus form to take keyboard focus once the next step has rendered.
    package func requestFormFocus() {
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            formFocusTick += 1
        }
    }
}
