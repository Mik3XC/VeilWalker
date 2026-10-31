// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VeilWalkerCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VeilWalkerCore", targets: ["VeilWalkerCore"]),
        .library(name: "VeilWalkerTor", targets: ["VeilWalkerTor"]),
        // The Live Activity's shared type, kept apart so the widget extension links nothing else.
        .library(name: "VeilWalkerActivity", targets: ["VeilWalkerActivity"]),
    ],
    dependencies: [
        // SQLite with raw SQL access, so the ledger's append-only triggers port 1:1 from Android.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
    ],
    targets: [
        .target(
            name: "VeilWalkerCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            resources: [
                .copy("Resources/bip39-english.txt"),
                // Byte-identical copy of Android's core/achievements asset.
                .copy("Resources/achievements.json"),
                // Generated from the Android Kotlin content by tools/export_content.py.
                .copy("Resources/content"),
            ]
        ),
        // Built by ../rust/vw-tor/build-xcframework.sh (iOS device, iOS simulator, macOS).
        .binaryTarget(name: "VWTor", path: "Frameworks/VWTor.xcframework"),
        // The Tor Project's Snowflake proxy, built by ../snowflake/build-xcframework.sh (gomobile).
        .binaryTarget(name: "VWFlake", path: "Frameworks/VWFlake.xcframework"),
        .target(
            name: "VeilWalkerTor",
            dependencies: ["VeilWalkerCore", "VWTor", "VWFlake"],
            // Go's resolver (inside VWFlake) calls libresolv.
            linkerSettings: [.linkedLibrary("resolv")]
        ),
        .target(name: "VeilWalkerActivity"),
        .testTarget(
            name: "VeilWalkerCoreTests",
            dependencies: ["VeilWalkerCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "VeilWalkerTorTests",
            dependencies: ["VeilWalkerTor"]
        ),
    ]
)
