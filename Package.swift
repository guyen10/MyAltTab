// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyAltTab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MyAltTab", path: "Sources/MyAltTab")
    ]
)
