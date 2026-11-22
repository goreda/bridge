// swift-tools-version: 5.9
// Local package for the GORAV-CACHE-PARITY row (root Package.swift stays
// unchanged this round, per Main's ruling). The policy source enters through
// the relative symlink Sources/cache-parity-tests/CacheTuningPolicy.swift ->
// ../../../GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift, so the test
// builds standalone without dragging in GorAVPlaybackCore's dependencies.
import PackageDescription
let package = Package(
    name: "cache-parity-tests",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "cache-parity-tests", targets: ["cache-parity-tests"])],
    targets: [.executableTarget(name: "cache-parity-tests", path: "Sources/cache-parity-tests")]
)
