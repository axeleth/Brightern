// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Brightern",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "Brightern", path: "Sources/Brightern")
    ]
)
