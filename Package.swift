// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenHue",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OpenHue",
            path: "Sources/OpenHue",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OpenHueTests",
            dependencies: ["OpenHue"],
            path: "Tests/OpenHueTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
