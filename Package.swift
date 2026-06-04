// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZeroRetentionContextEngine",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "zre",
            path: "Sources/zre"
        )
    ]
)
