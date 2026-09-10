import Foundation
import DeepCyclesCore

/// A local date at a wall-clock time.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// A block on `day` between two wall-clock times, given as (hour, minute).
func block(_ title: String = "Block", _ kind: BlockKind = .deep, on day: Date, from: (Int, Int), to: (Int, Int)) -> TimeBlock {
    let c = Calendar.current
    let start = c.date(bySettingHour: from.0, minute: from.1, second: 0, of: day)!
    let end = c.date(bySettingHour: to.0, minute: to.1, second: 0, of: day)!
    return TimeBlock(title: title, start: start, end: end, kind: kind)
}

/// A fresh scratch folder for one store.
func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("DeepCyclesTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Stands in for the engine's one-second timer: the test decides when it ticks.
@MainActor
final class FakeClock {
    private(set) var fire: (@Sendable @MainActor () -> Void)?
    var isScheduled: Bool { fire != nil }

    func factory(_ fire: @escaping @Sendable @MainActor () -> Void) -> Timer {
        self.fire = fire
        return Timer(timeInterval: 1, repeats: true) { _ in }
    }

    func tick(_ n: Int = 1) {
        for _ in 0..<n { fire?() }
    }
}

/// A store on scratch data, an app state on scratch defaults, and an engine on a fake clock,
/// all looking at `day`.
@MainActor
struct Harness {
    let store: Store
    let ui: AppState
    let clock: FakeClock
    let engine: CycleEngine
    let day: Date

    init(day: Date = date(2026, 3, 10)) {
        self.day = day
        let store = Store(directory: temporaryDirectory())
        store.selectedDate = day
        let clock = FakeClock()
        let engine = CycleEngine(timer: { clock.factory($0) })
        engine.store = store
        self.store = store
        self.clock = clock
        self.engine = engine
        self.ui = AppState(defaults: UserDefaults(suiteName: "DeepCyclesTests-\(UUID().uuidString)")!)
    }

    var flow: SessionFlow { SessionFlow(store: store, ui: ui, engine: engine) }
}
