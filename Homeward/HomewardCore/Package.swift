// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HomewardCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HomewardCore", targets: ["HomewardCore"]),
    ],
    targets: [
        .target(name: "HomewardCore"),
        .testTarget(name: "HomewardCoreTests", dependencies: ["HomewardCore"]),
    ]
)
