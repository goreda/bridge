// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BridgeVTDecode",
    targets: [
        // Vendored byte-identical copy of the P-A1-R2 BridgeDemux sources
        // (tag P-A1-R2; the original P-A1/P-A1-FMP4/P-A1-R1/P-A1-R2 packages
        // are unchanged). Vendored so this package stays self-contained.
        .target(name: "BridgeDemux"),
        .target(name: "BridgeVTDecode", dependencies: ["BridgeDemux"]),
        .testTarget(
            name: "BridgeVTDecodeTests",
            dependencies: ["BridgeVTDecode", "BridgeDemux"],
            resources: [.copy("Fixtures")]
        )
    ]
)
