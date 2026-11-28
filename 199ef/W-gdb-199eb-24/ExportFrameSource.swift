// Picture/ExportFrameSource.swift
// Names the two candidate frame paths and records what the Codemagic measurement saw for each. Frames themselves travel through the existing ExportRGBA64FrameFeed; there is no second feed protocol.
// Uses: none
// Engine: mpv
import Foundation

public enum ExportFramePath: String, CaseIterable, Codable, Equatable { case libmpvRenderAPI = "libmpv-render-api", screenshotRawFrameStep = "screenshot-raw-frame-step" }

/// What the Codemagic measurement records per path. The winner is chosen from these numbers, not from this code.
public struct ExportFramePathMeasurement: Codable, Equatable {
    public var path: ExportFramePath
    public var frames: Int
    public var seconds: Double
    public var exactPTSMatches: Int
    public var bytesPerFrame: Int
    public init(path: ExportFramePath, frames: Int, seconds: Double, exactPTSMatches: Int, bytesPerFrame: Int) {
        self.path = path; self.frames = frames; self.seconds = seconds; self.exactPTSMatches = exactPTSMatches; self.bytesPerFrame = bytesPerFrame
    }
    public var framesPerSecond: Double { seconds > 0 ? Double(frames) / seconds : 0 }
    public var ptsExact: Bool { frames > 0 && exactPTSMatches == frames }
}
