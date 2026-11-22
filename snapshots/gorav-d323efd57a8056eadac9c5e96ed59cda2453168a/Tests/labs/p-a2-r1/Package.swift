// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AudioMasterScheduler", products: [
    .library(name: "AudioMasterScheduler", targets: ["AudioMasterScheduler"])
], targets: [
    .target(name: "AudioMasterScheduler"),
    .testTarget(name: "AudioMasterSchedulerTests", dependencies: ["AudioMasterScheduler"], resources: [.copy("Fixtures")])
])
