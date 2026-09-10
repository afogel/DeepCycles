// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeepCycles",
    platforms: [.macOS(.v14)],
    targets: [
        // Models, persistence, the timer and the session flow. No SwiftUI or AppKit, so it
        // builds and tests quickly and could back a widget or a command-line tool later.
        .target(
            name: "DeepCyclesCore",
            path: "Sources/DeepCyclesCore",
            linkerSettings: [.linkedFramework("EventKit")]
        ),
        .executableTarget(
            name: "DeepCycles",
            dependencies: ["DeepCyclesCore"],
            path: "Sources/DeepCycles",
            linkerSettings: [
                .linkedFramework("EventKit"),
                .linkedFramework("UserNotifications")
            ]
        ),
        // The Command Line Tools ship neither XCTest nor Swift Testing, so the tests are an
        // executable (`swift run DeepCyclesCoreTests`) written against a small XCTest-shaped kit.
        // With Xcode installed, turn this into a .testTarget and `import XCTest` instead.
        .target(name: "TestKit", path: "Tests/TestKit"),
        .executableTarget(
            name: "DeepCyclesCoreTests",
            dependencies: ["DeepCyclesCore", "TestKit"],
            path: "Tests/DeepCyclesCoreTests"
        ),
    ]
)
