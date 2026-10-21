// swift-tools-version: 5.10
import PackageDescription

// Rend les maquettes de docs/IDEAS.md en PNG, hors écran (ImageRenderer) : aucune fenêtre ne s'ouvre.
// Paquet à part : `swift build` à la racine du dépôt ne le compile pas.
//   cd docs/ideas/maquettes && swift run Maquettes ..
let package = Package(
    name: "Maquettes",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Maquettes", path: "Sources/Maquettes")
    ],
    swiftLanguageVersions: [.v5]
)
