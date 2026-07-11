// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "yapper",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "YapperKit",
            targets: ["YapperKit"]
        ),
        .executable(
            name: "yapper",
            targets: ["yapper"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
        // Using our fork until upstream accepts PR #13 (remove type: .dynamic)
        // Upstream: https://github.com/mlalma/MisakiSwift
        .package(url: "https://github.com/tigger04/MisakiSwift", branch: "remove-dynamic-type"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "YapperKit",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "MisakiSwift", package: "MisakiSwift"),
            ]
        ),
        .executableTarget(
            name: "yapper",
            dependencies: [
                "YapperKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
            ],
            exclude: ["Commands/ContextPOC.swift"]
        ),
        .testTarget(
            name: "YapperKitTests",
            dependencies: ["YapperKit"],
            path: "Tests/regression/YapperKitTests"
        ),
        .testTarget(
            name: "YapperOneOffTests",
            dependencies: ["YapperKit"],
            path: "Tests/one_off"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
