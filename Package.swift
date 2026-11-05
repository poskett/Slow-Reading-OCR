// swift-tools-version: 6.2
// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import PackageDescription

let package = Package(
    name: "OlmOCR",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OlmOCRCore", targets: ["OlmOCRCore"]),
        .executable(name: "olmocr", targets: ["olmocr"]),
        .executable(name: "OlmOCRApp", targets: ["OlmOCRApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3", traits: []),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "OlmOCRCore",
            dependencies: [
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .executableTarget(
            name: "olmocr",
            dependencies: ["OlmOCRCore"]
        ),
        .executableTarget(
            name: "OlmOCRApp",
            dependencies: ["OlmOCRCore"],
            resources: [.copy("Resources")]
        ),
    ]
)
