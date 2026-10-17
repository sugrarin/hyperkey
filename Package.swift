// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Hyperkey",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Hyperkey", path: "Sources/Hyperkey")
    ]
)
