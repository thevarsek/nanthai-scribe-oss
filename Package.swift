// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NanthAiScribe",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScribeCore", targets: ["ScribeCore"]),
        .library(name: "ScribeUI", targets: ["ScribeUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.5"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3", traits: []),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.32.3"),
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.7", traits: []),
    ],
    targets: [
        // Platform-neutral dictation pipeline: mic → on-device speech → cleanup.
        .target(name: "ScribeCore", dependencies: [
            .product(name: "Tokenizers", package: "swift-transformers"),
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "FluidAudio", package: "FluidAudio"),
        ], resources: [.process("Models/Catalog")]),
        // Brand tokens and shared components. See docs/DESIGN.md.
        .target(name: "ScribeUI"),
        .target(name: "ScribeMacCore", dependencies: ["ScribeCore"]),
        .executableTarget(name: "ScribeMac", dependencies: ["ScribeCore", "ScribeUI", "ScribeMacCore",
            .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS])),
        ]),
        .executableTarget(name: "model-download", dependencies: ["ScribeCore"], path: "Tools/model-download"),
        .executableTarget(name: "speech-e2e", dependencies: ["ScribeCore"], path: "Tools/speech-e2e"),
        .testTarget(name: "ScribeCoreTests", dependencies: ["ScribeCore"]),
        .testTarget(name: "ScribeMacCoreTests", dependencies: ["ScribeMacCore"]),
        .testTarget(name: "ScribeMacTests", dependencies: ["ScribeMac"]),
    ]
)
