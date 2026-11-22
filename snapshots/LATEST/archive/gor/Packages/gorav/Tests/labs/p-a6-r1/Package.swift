// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BridgeDemux",
    targets: [
        .target(name: "BridgeDemux"),
        .executableTarget(name: "BridgeDemuxProbe", dependencies: ["BridgeDemux"]),
        .testTarget(
            name: "BridgeDemuxTests",
            dependencies: ["BridgeDemux"],
            resources: [.copy("Fixtures")]
        )
    ]
)
