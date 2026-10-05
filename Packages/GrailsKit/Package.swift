// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrailsKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrailsKit", targets: ["GrailsKit"]),
        .executable(name: "grails-fixture", targets: ["grails-fixture"]),
        .executable(name: "grails-tags", targets: ["grails-tags"]),
        .executable(name: "grails-import", targets: ["grails-import"]),
        .executable(name: "grails-share", targets: ["grails-share"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(name: "GrailsKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "grails-fixture", dependencies: ["GrailsKit"]),
        .executableTarget(name: "grails-tags", dependencies: ["GrailsKit"]),
        .executableTarget(name: "grails-import", dependencies: ["GrailsKit"]),
        .executableTarget(name: "grails-share", dependencies: ["GrailsKit"]),
        .testTarget(name: "GrailsKitTests", dependencies: ["GrailsKit"]),
    ]
)
