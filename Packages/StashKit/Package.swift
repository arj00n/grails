// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StashKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StashKit", targets: ["StashKit"]),
    ],
    targets: [
        .target(name: "StashKit"),
        .testTarget(name: "StashKitTests", dependencies: ["StashKit"]),
    ]
)
