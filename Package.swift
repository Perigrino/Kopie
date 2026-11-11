// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Kopie",
    platforms: [.macOS(.v13)],
    dependencies: [
        // In-app updates. Sparkle 2.10 requires macOS 12+ (Kopie: 13+) and
        // ships an EdDSA-signed appcast format, so update payloads are verified
        // independently of TLS. It is the single third-party dependency.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(
            name: "KopieCore",
            path: "Sources/KopieCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Kopie",
            dependencies: [
                "KopieCore",
                "Sparkle",
            ],
            path: "Sources/Kopie",
            linkerSettings: [
                // scripts/build.sh embeds Sparkle.framework into the app bundle
                // it assembles by hand; the executable finds it here.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "KopieCoreTests",
            dependencies: ["KopieCore"],
            path: "Tests/KopieCoreTests"
        ),
    ]
)
