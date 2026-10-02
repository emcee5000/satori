// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Satori",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Satori", path: "Sources/Satori"),
        .testTarget(name: "SatoriTests", dependencies: ["Satori"], path: "Tests/SatoriTests"),
    ]
)
