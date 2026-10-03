// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OtterCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OtterCore", targets: ["OtterCore"]),
    ],
    targets: [
        .target(name: "OtterCore"),
        .testTarget(name: "OtterCoreTests", dependencies: ["OtterCore"]),
    ]
)
