// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FoxSayFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "FoxSayFeature",
            targets: ["FoxSayFeature"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
        // 0.15.5 is the floor: earlier releases fail to compile under Swift 6.3's
        // strict concurrency checking (data-race errors inside StreamingAsrManager).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5"),
        // 3.31.4 is the first tagged release carrying the qwen3_5 and gemma4
        // architectures. Use the tag rather than "main": tracking the branch is what
        // silently broke the build when upstream moved loadModelContainer to from:/using:.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMajor(from: "3.31.4")),
        // mlx-swift-lm no longer vendors a Hugging Face client. #hubDownloader() expands
        // to HuggingFace.HubClient and #huggingFaceTokenizerLoader() to Tokenizers, so
        // both packages have to be declared here by the consumer.
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        // Held to 1.1.x to match WhisperKit, which pins .upToNextMinor(from: "1.1.6").
        // mlx-swift-lm's docs suggest 1.3.0, but #huggingFaceTokenizerLoader() only needs
        // Tokenizers.AutoTokenizer.from(modelFolder:), which 1.1.x already provides.
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.1.6")),
    ],
    targets: [
        .target(
            name: "FoxSayFeature",
            dependencies: [
                "WhisperKit",
                "FluidAudio",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "FoxSayFeatureTests",
            dependencies: ["FoxSayFeature"]
        ),
    ]
)
