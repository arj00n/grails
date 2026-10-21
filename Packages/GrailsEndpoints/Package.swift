// swift-tools-version: 6.0
import PackageDescription

// The site address the app, GrailsKit and GrailsSync share. No dependencies, so either package can use it without pulling in the other.
let package = Package(
    name: "GrailsEndpoints",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrailsEndpoints", targets: ["GrailsEndpoints"]),
    ],
    targets: [
        .target(name: "GrailsEndpoints"),
    ]
)
