// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FilterCore",
    // Texts are written in English and translated to Turkish in Localizable.xcstrings,
    // so phones in other languages get English.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        // Only so the engine can be tested with `swift test` on a Mac.
        .macOS(.v13),
    ],
    products: [
        .library(name: "FilterCore", targets: ["FilterCore"]),
    ],
    targets: [
        .target(
            name: "FilterCore",
            resources: [
                .copy("Resources/rules.json"),
                .copy("Resources/legitimate-samples.json"),
                .process("Resources/Localizable.xcstrings"),
            ]
        ),
        .testTarget(name: "FilterCoreTests", dependencies: ["FilterCore"]),
    ]
)
