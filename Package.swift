// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Stretch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Stretch",
            path: "Sources/Stretch"
        )
    ]
)
