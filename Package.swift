// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MoTranslate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MoTranslate",
            path: "Sources/MoTranslate"
        ),
        .testTarget(name: "MoTranslateTests", dependencies: ["MoTranslate"])
    ]
)
