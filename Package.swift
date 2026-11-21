// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NovaRush",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NovaRush",
            path: "Sources/NovaRush",
            resources: [.copy("Resources")]
        )
    ]
)
