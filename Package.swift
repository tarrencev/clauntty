// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clauntty",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)  // For running tests on macOS
    ],
    products: [
        .library(
            name: "ClaunttyCore",
            targets: ["ClaunttyCore"]
        ),
    ],
    dependencies: [
        // Apple's official SSH implementation
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.9.0"),
        // Required NIO dependencies
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
    ],
    targets: [
        .target(
            name: "ClaunttyCore",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Clauntty/Core"
        ),
        .testTarget(
            name: "ClaunttyTests",
            dependencies: ["ClaunttyCore"],
            path: "Tests/ClaunttyTests"
        ),
    ]
)
