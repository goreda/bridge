// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MediaFacadeKit",
    products: [
        .library(name: "MediaFacadeKit", targets: ["MediaFacadeKit"])
    ],
    targets: [
        .target(name: "MediaFacadeKit"),
        .testTarget(
            name: "MediaFacadeKitTests",
            dependencies: ["MediaFacadeKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
