// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeepCycles",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DeepCycles",
            path: "Sources/DeepCycles",
            linkerSettings: [
                .linkedFramework("EventKit"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)
