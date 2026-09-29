// swift-tools-version: 6.2
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "AA",                                   // resource bundles are "AA_AACore.bundle" / "AA_AA.bundle" (03 BD.3.4)
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "AA", targets: ["AA"]),
        .library(name: "AACore", targets: ["AACore"]),
    ],
    dependencies: [],                             // no third-party code, ever (brief; 03 SHELL-180)
    targets: [
        .target(
            name: "AACore",
            path: "Sources/AACore",
            resources: [.copy("Resources/sire2_question_bank.json")],
            swiftSettings: swift5
        ),
        .executableTarget(
            name: "AA",
            dependencies: ["AACore"],
            path: "Sources/AA",
            resources: [
                .copy("Resources/Splash.png"),
                .copy("Resources/MenuBarIconTemplate.png"),
                .copy("Resources/MenuBarIconTemplate@2x.png"),
            ],
            swiftSettings: swift5
        ),
        .executableTarget(                        // 13 §6.1 / FLASH-120 conformance CLI (dev only, never shipped)
            name: "AAFlashSyncInterop",
            dependencies: ["AACore"],
            path: "Tools/FlashSyncInterop",
            swiftSettings: swift5
        ),
        .testTarget(
            name: "AACoreTests",
            dependencies: ["AACore"],
            path: "Tests/AACoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: swift5
        ),
    ]
)
