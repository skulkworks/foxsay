// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LLMTestApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "LLMTestApp",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
    ]
)
