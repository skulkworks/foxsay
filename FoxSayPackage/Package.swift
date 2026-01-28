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
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.10.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "FoxSayFeature",
            dependencies: [
                "WhisperKit",
                "FluidAudio",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
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
