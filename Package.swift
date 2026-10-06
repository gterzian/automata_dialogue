// swift-tools-version: 6.0
import PackageDescription

// SwiftPM is the iteration and test path (xcodebuild is unavailable in the
// sandbox). The Xcode project in project.yml builds the app bundle from the
// same Core sources.
let package = Package(
    name: "Rater",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .executable(name: "rater-cli", targets: ["rater-cli"]),
    ],
    targets: [
        // AppKit-free. No external package dependencies.
        .target(
            name: "Core",
            path: "Core",
            exclude: [
                "README.md",
                "Agent/README.md",
                "Catalog/README.md",
                "Import/README.md",
                "Programs/README.md",
                "Render/README.md",
                "Session/README.md",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "rater-cli",
            dependencies: ["Core"],
            path: "CLI",
            exclude: ["README.md"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "CoreTests",
            exclude: ["README.md"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
