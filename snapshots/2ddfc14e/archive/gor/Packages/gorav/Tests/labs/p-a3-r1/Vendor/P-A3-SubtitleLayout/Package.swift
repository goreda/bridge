// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "P-A3-SubtitleLayout",
    products: [
        .library(name: "SubtitleLayout", targets: ["SubtitleLayout"])
    ],
    targets: [
        .target(name: "SubtitleLayout", path: "Sources/SubtitleLayout"),
        .testTarget(
            name: "SubtitleLayoutTests",
            dependencies: ["SubtitleLayout"],
            path: "Tests/SubtitleLayoutTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
