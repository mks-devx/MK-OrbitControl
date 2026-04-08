// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MKOrbitControl",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "MKOrbitControl",
            dependencies: ["HotKey"],
            path: "Sources/MKOrbitControl"
        )
    ]
)
