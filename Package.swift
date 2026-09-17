// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AirFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AirFlow",
            targets: ["AirFlowCLI"]
        )
    ],
    targets: [
        .target(
            name: "AirFlow"
        ),
        .executableTarget(
            name: "AirFlowCLI",
            dependencies: ["AirFlow"]
        ),
        .testTarget(
            name: "AirFlowTests",
            dependencies: ["AirFlow"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
