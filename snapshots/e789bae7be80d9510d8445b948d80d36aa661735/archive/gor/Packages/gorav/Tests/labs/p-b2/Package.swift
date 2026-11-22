// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ParityKit",
    products: [
        .library(name: "ParityCore", targets: ["ParityCore"]),
        .executable(name: "parity-runner", targets: ["ParityRunnerCLI"]),
    ],
    targets: [
        .target(name: "ParityCore"),
        .executableTarget(name: "ParityRunnerCLI", dependencies: ["ParityCore"]),
        .testTarget(
            name: "ParityCoreTests",
            dependencies: ["ParityCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
