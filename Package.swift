// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Kopie",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "KopieCore",
            path: "Sources/KopieCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Kopie",
            dependencies: ["KopieCore"],
            path: "Sources/Kopie"
        ),
        .testTarget(
            name: "KopieCoreTests",
            dependencies: ["KopieCore"],
            path: "Tests/KopieCoreTests"
        ),
    ]
)
