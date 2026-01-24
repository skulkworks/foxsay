// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceFoxFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "VoiceFoxFeature",
            targets: ["VoiceFoxFeature"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "VoiceFoxFeature",
            dependencies: [
                "WhisperKit",
                "FluidAudio",
            ]
        ),
        .testTarget(
            name: "VoiceFoxFeatureTests",
            dependencies: ["VoiceFoxFeature"]
        ),
    ]
)
