// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StashKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StashKit", targets: ["StashKit"]),
        .executable(name: "stash-fixture", targets: ["stash-fixture"]),
        .executable(name: "stash-tags", targets: ["stash-tags"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(name: "StashKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "stash-fixture", dependencies: ["StashKit"]),
        .executableTarget(name: "stash-tags", dependencies: ["StashKit"]),
        .testTarget(name: "StashKitTests", dependencies: ["StashKit"]),
    ]
)
