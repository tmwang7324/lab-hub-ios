// swift-tools-version: 6.0
// LabHubCore: all of Lab Hub's logic, with no iOS UI frameworks, so it is testable with `swift test`.
import PackageDescription

let package = Package(
    name: "LabHubCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LabHubCore", targets: ["LabHubCore"]),
        .executable(name: "labhub-moment", targets: ["labhub-moment"]),
    ],
    targets: [
        .target(name: "LabHubCore"),
        // A command-line tool that runs the real resolver on a feed file: `swift run labhub-moment feed.json`.
        // Handy for seeing the logs without a phone, and the end-to-end tests drive it as a black box.
        .executableTarget(name: "labhub-moment", dependencies: ["LabHubCore"]),
        .testTarget(
            name: "LabHubCoreTests",
            dependencies: ["LabHubCore", "labhub-moment"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
