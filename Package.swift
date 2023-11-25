// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LCLPing",
    platforms: [
        .macOS(.v10_15), .iOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "LCLPing",
            targets: ["LCLPing"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.25.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.4")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "LCLPing",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Collections", package: "swift-collections")
            ]),
        .testTarget(
            name: "LCLPingTests",
            dependencies: ["LCLPing"]),
        .testTarget(
            name: "UtilitiesTests",
            dependencies: ["LCLPing"]
        ),
        .testTarget(
            name: "TimerTests",
            dependencies: ["LCLPing"]
        ),
        .testTarget(
            name: "ModelTests",
            dependencies: ["LCLPing"]
        ),
        .testTarget(
            name: "ICMPChannelTests",
            dependencies: ["LCLPing"]
        )
    ]
)
