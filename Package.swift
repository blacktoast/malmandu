// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "malmandu",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MalmanduCore", targets: ["MalmanduCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "MalmanduCore",
            dependencies: ["KeyboardShortcuts", "FluidAudio"],
            path: "Sources/MalmanduCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Malmandu",
            dependencies: ["MalmanduCore"],
            path: "Sources/Malmandu"
        ),
        .testTarget(
            name: "MalmanduCoreTests",
            dependencies: ["MalmanduCore"],
            path: "Tests/MalmanduCoreTests"
        ),
    ]
)
