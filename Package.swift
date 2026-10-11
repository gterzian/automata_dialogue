// swift-tools-version: 6.0
import PackageDescription

// SwiftPM is the iteration and test path (xcodebuild is unavailable in the
// sandbox). The Xcode project in project.yml builds the app bundle from the
// same sources. Both include the MLX `Agent` target.
let packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
    .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
    .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
]

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
        .library(name: "Agent", targets: ["Agent"]),
        .executable(name: "rater-cli", targets: ["rater-cli"]),
    ],
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
            dependencies: ["Core", "Agent"],
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
    ] + [agentTarget]
)
