// swift-tools-version: 6.0
import PackageDescription

// SwiftPM is the only build path (xcodebuild is unavailable in the sandbox).
// It builds the CLI, `Core`, and the two agent backends. Core AI ships only for
// macOS 27, so the package as a whole requires it.
let packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
    .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
    .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
    // No tags upstream, so the revision is the pin.
    .package(
        url: "https://github.com/apple/coreai-models.git",
        revision: "0aff93881d1f774592392de9b4819858da2a5714"),
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

let coreAIAgentTarget = Target.target(
    name: "AgentCoreAI",
    dependencies: [
        "Core",
        .product(name: "CoreAILM", package: "coreai-models"),
    ],
    path: "AgentCoreAI",
    exclude: ["README.md"],
    swiftSettings: [
        .swiftLanguageMode(.v6),
    ]
)

let package = Package(
    name: "Rater",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Agent", targets: ["Agent"]),
        .library(name: "AgentCoreAI", targets: ["AgentCoreAI"]),
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
                "Render/README.md",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "rater-cli",
            dependencies: ["Core", "Agent", "AgentCoreAI"],
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
    ] + [agentTarget, coreAIAgentTarget]
)
