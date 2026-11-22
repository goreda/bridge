// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BridgeDemux",
    products: [.library(name: "BridgeDemux", targets: ["BridgeDemux"])],
    targets: [
        .target(name: "BridgeDemux"),
        .testTarget(
            name: "BridgeDemuxTests",
            dependencies: ["BridgeDemux"],
            resources: [.copy("Fixtures")]
        )
    ]
)
