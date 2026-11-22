// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BridgeTimeMath",
    targets: [
        .target(name: "BridgeTimeMath"),
        .testTarget(
            name: "BridgeTimeMathTests",
            dependencies: ["BridgeTimeMath"],
            resources: [.copy("Fixtures")]
        )
    ]
)
