// swift-tools-version: 5.9
// NB: tools-version < 6.0 defaults the Swift language mode to v5. The host
// target subclasses IMKInputController, whose Objective-C headers are not
// @MainActor-annotated; strict Swift 6 concurrency makes that subclassing
// impractical, so the whole package is built in Swift 5 mode. The engine and
// storage still use actors + Sendable types; they just are not strictly
// checked at compile time.
import PackageDescription

let package = Package(
    name: "BanglaIME",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BanglaEngine", targets: ["BanglaEngine"]),
        .library(name: "BanglaStorage", targets: ["BanglaStorage"]),
        .library(name: "BanglaXPC", targets: ["BanglaXPC"]),
        .library(name: "BanglaCandidateUI", targets: ["BanglaCandidateUI"]),
        .executable(name: "bangla-ime", targets: ["BanglaIMEExtension"]),
        .executable(name: "bangla-settings", targets: ["BanglaSettings"]),
        .executable(name: "lexicon-builder", targets: ["LexiconBuilder"]),
    ],
    targets: [
        .target(
            name: "BanglaEngine",
            path: "Packages/BanglaEngine/Sources/BanglaEngine"
        ),
        .target(
            name: "BanglaStorage",
            dependencies: ["BanglaEngine"],
            path: "Packages/BanglaStorage/Sources/BanglaStorage",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "BanglaXPC",
            path: "Packages/BanglaXPC/Sources/BanglaXPC"
        ),
        .target(
            name: "BanglaCandidateUI",
            dependencies: ["BanglaEngine"],
            path: "Targets/BanglaCandidateUI"
        ),
        .executableTarget(
            name: "BanglaIMEExtension",
            dependencies: ["BanglaEngine", "BanglaStorage", "BanglaXPC", "BanglaCandidateUI"],
            path: "Targets/BanglaIMEExtension",
            exclude: ["Info.plist", "Entitlements"],
            resources: [
                .copy("Resources/layouts"),
                .copy("Resources/lexicon.db"),
            ],
            linkerSettings: [.linkedFramework("InputMethodKit"), .linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "BanglaSettings",
            dependencies: ["BanglaEngine", "BanglaStorage", "BanglaXPC"],
            path: "Targets/BanglaSettings"
        ),
        .executableTarget(
            name: "LexiconBuilder",
            dependencies: ["BanglaEngine", "BanglaStorage"],
            path: "Tools/lexicon-builder/Sources/lexicon-builder"
        ),
        .testTarget(
            name: "BanglaEngineTests",
            dependencies: ["BanglaEngine"],
            path: "Tests/BanglaEngineTests"
        ),
        .testTarget(
            name: "BanglaStorageTests",
            dependencies: ["BanglaStorage", "BanglaEngine"],
            path: "Tests/BanglaStorageTests"
        ),
        .testTarget(
            name: "BanglaIMEExtensionTests",
            dependencies: ["BanglaIMEExtension", "BanglaEngine", "BanglaStorage"],
            path: "Tests/BanglaIMEExtensionTests"
        ),
    ]
)