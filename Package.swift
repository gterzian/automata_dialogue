// swift-tools-version: 6.0
import Foundation
import PackageDescription

// SwiftPM is the iteration and test path (xcodebuild is unavailable in the
// sandbox). The Xcode project in project.yml builds the app bundle from the
// same sources.
//
// The MLX `Agent` target is a large C++/Metal build, so it is opt-in here and
// the default package stays the fast, model-free Core path. Set RATER_AGENT=1
// to include it; the Xcode project always includes it.
let buildAgent = ProcessInfo.processInfo.environment["RATER_AGENT"] == "1"

let packageDependencies: [Package.Dependency] = buildAgent
    ? [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
    ]
    : []

let agentTarget = Target.target(
    name: "Agent",
    dependencies: [
        "Core",
        .product(name: "MLXVLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "HuggingFace", package: "swift-huggingface"),
        .product(name: "Tokenizers", package: "swift-transformers"),
    ],
    path: "Agent",
    exclude: ["README.md"],
    swiftSettings: [
        .swiftLanguageMode(.v6),
    ]
)

let package = Package(
    name: "Rater",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .executable(name: "rater-cli", targets: ["rater-cli"]),
    ] + (buildAgent ? [.library(name: "Agent", targets: ["Agent"])] : []),
    dependencies: packageDependencies,
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
            dependencies: ["Core"] + (buildAgent ? ["Agent"] : []),
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
    ] + (buildAgent ? [agentTarget] : [])
)
