// swift-tools-version:5.9
// Isolated test package for W-gdb-199r-1nstinct-02. No shared root Package.swift edits.
// The runner first verifies byte equality of Sources/GorAVPlaybackCore against the
// pinned production paths (tools/verify-pinned.sh) before any build.
import PackageDescription

let package = Package(
    name: "Kit199r1nstinct02",
    products: [],
    targets: [
        .target(name: "GorAVPlaybackCore", path: "Sources/GorAVPlaybackCore"),
        .testTarget(name: "GorAVPlaybackCoreTests", dependencies: ["GorAVPlaybackCore"], path: "Tests/GorAVPlaybackCoreTests"),
    ]
)
