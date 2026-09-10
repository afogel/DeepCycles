import SwiftUI
import DeepCyclesCore

@main
struct DeepCyclesApp: App {
    @StateObject private var store: Store
    @StateObject private var ui = AppState()
    @StateObject private var calendar = CalendarService()
    @StateObject private var engine: CycleEngine

    init() {
        let s = Store()
        let e = CycleEngine()
        e.store = s
        e.alert = { CycleAlerts.deliver($0) }
        _store = StateObject(wrappedValue: s)
        _engine = StateObject(wrappedValue: e)
        // Saves are coalesced; write them out when the app goes to the background or quits,
        // whether or not the window is open. The center keeps these observers for the app's life.
        for name in [NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { s.flush() }
            }
        }
    }

    var body: some Scene {
        WindowGroup("DeepCycles") {
            RootView()
                .environmentObject(store)
                .environmentObject(ui)
                .environmentObject(calendar)
                .environmentObject(engine)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(store: store, ui: ui, engine: engine) }

        // ⌘, and the app menu's "Settings…" come with the scene.
        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(ui)
                .environmentObject(calendar)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(ui)
                .environmentObject(engine)
        } label: {
            Label(engine.menuTitle, systemImage: engine.phase == .breaking ? "cup.and.saucer" : "timer")
        }
        .menuBarExtraStyle(.window)
    }
}
