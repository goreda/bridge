// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "P-A3-R1-SubtitleLayout",
    products: [
        .library(name: "SubtitleLayoutStrict", targets: ["SubtitleLayoutStrict"])
    ],
    dependencies: [
        // Original P-A3 package, vendored byte-identical (hash-pinned).
        .package(path: "Vendor/P-A3-SubtitleLayout")
    ],
    targets: [
        .target(
            name: "SubtitleLayoutStrict",
            dependencies: [.product(name: "SubtitleLayout", package: "P-A3-SubtitleLayout")],
            path: "Sources/SubtitleLayoutStrict"
        ),
        .testTarget(
            name: "SubtitleLayoutStrictTests",
            dependencies: ["SubtitleLayoutStrict", .product(name: "SubtitleLayout", package: "P-A3-SubtitleLayout")],
            path: "Tests/SubtitleLayoutStrictTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
