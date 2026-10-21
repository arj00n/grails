// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrailsSync",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrailsSync", targets: ["GrailsSync"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.8.0"),
        .package(path: "../GrailsEndpoints"),
    ],
    targets: [
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(
            name: "GrailsSync",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                "CZlib",
                "GrailsEndpoints",
            ]
        ),
        .testTarget(name: "GrailsSyncTests", dependencies: ["GrailsSync", "GrailsEndpoints"]),
    ]
)
