// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PicoShop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PicoShop",
            path: "Sources/PicoShop"
        )
    ]
)
