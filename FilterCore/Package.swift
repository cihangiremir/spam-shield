// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FilterCore",
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
            ]
        ),
        .testTarget(name: "FilterCoreTests", dependencies: ["FilterCore"]),
    ]
)
