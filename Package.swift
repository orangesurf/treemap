// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "treemap",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "Treemap",
            path: ".",
            exclude: ["Tests", "README.md", "LICENSE", "treemap", "main.swift", "Makefile"],
            sources: ["treemap.swift"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "TreemapTests",
            dependencies: ["Treemap"],
            path: "Tests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
