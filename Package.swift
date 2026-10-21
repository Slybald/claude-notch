// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeNotch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeNotch",
            dependencies: ["FanControl"],
            path: "Sources/ClaudeNotch"
        ),
        // Accès au SMC, partagé par l'app (lecture) et l'outil d'aide `fanctl` (écriture, en root).
        .target(
            name: "FanControl",
            path: "Sources/FanControl"
        ),
        .executableTarget(
            name: "fanctl",
            dependencies: ["FanControl"],
            path: "Sources/fanctl"
        ),
        .testTarget(
            name: "ClaudeNotchTests",
            dependencies: ["ClaudeNotch", "FanControl"],
            path: "Tests/ClaudeNotchTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
