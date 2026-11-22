// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CaptureStatsTests", platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CaptureStats", path: ".",
                exclude: ["CaptureStatsTests.swift", "HUDFeedTests.swift", "HeatProducerTests.swift", "HeatComparisonTests.swift", "HeatTrialCaptureTests.swift", "Package.swift", "run-mutants.py"],
                sources: ["CaptureStats.swift", "CaptureHUDFeed.swift", "CaptureHeatReport.swift", "HeatProducer.swift", "PlatformHeatSources.swift", "HeatComparison.swift", "HeatTrialCapture.swift", "MetalPresenterTelemetry.swift"]),
        .testTarget(name: "CaptureStatsTests", dependencies: ["CaptureStats"],
                    path: ".", exclude: ["CaptureStats.swift", "CaptureHUDFeed.swift", "CaptureHeatReport.swift", "HeatProducer.swift", "PlatformHeatSources.swift", "HeatComparison.swift", "HeatTrialCapture.swift", "MetalPresenterTelemetry.swift", "Package.swift", "run-mutants.py"],
                    sources: ["CaptureStatsTests.swift", "HUDFeedTests.swift", "HeatProducerTests.swift", "HeatComparisonTests.swift", "HeatTrialCaptureTests.swift"])
    ])
