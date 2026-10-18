// swift-tools-version: 6.2
import PackageDescription

// Build-only: avoids Finder automation while preserving native disk-image metadata.
let package = Package(
    name: "ScribeDMGLayout",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/DSStore", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(name: "dmg-layout", dependencies: [.product(name: "DSStore", package: "DSStore")], path: "Sources",
                          linkerSettings: [.linkedFramework("Carbon")]),
    ]
)
