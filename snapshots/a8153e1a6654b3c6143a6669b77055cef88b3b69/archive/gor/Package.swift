// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "gor",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(name: "gorav", path: "Packages/gorav")
    ],
    targets: [
        .executableTarget(
            name: "gor",
            dependencies: [.product(name: "GorAVEmbeddedShell", package: "gorav"), .product(name: "StereoLookNativeContract", package: "gorav")],
            path: "Sources/gor"
        ),
        .testTarget(name: "gorTests", dependencies: ["gor"], path: "Tests/gorTests")
    ]
)
