// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "HDRReference",
    products: [
        .library(name: "HDRReference", targets: ["HDRReference"])
    ],
    targets: [
        .target(name: "HDRReference"),
        .testTarget(
            name: "HDRReferenceTests",
            dependencies: ["HDRReference"]
        )
    ]
)
