// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "openHue",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "openHue",
            path: "Sources/openHue",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "openHueTests",
            dependencies: ["openHue"],
            path: "Tests/openHueTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
