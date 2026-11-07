// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaskBoard",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TaskBoard", targets: ["TaskBoard"])],
    targets: [
        .executableTarget(
            name: "TaskBoard",
            linkerSettings: [.linkedFramework("EventKit")]
        ),
        .testTarget(name: "TaskBoardTests", dependencies: ["TaskBoard"])
    ]
)
