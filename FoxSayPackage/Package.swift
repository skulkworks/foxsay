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
        // Pinned to an explicit revision rather than tracking "main". Upstream main is
        // mid-migration: loadModelContainer now requires from:/using: parameters whose
        // #hubDownloader macro expands to a HubClient that main does not yet vendor,
        // so tracking the branch breaks the build without warning. This is the revision
        // v1.0.9 shipped from. Revisit when upstream cuts a tagged release.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", revision: "2c700546340c37f275d23302163701b77c4dcbd9"),
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
