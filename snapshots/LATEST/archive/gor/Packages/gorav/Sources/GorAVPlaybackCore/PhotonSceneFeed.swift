import Foundation

/// Shared values produced by current photon.lua's photon_publish_scene_feed.
/// Consume only for the currently admitted source generation; the host owns
/// that source/reset fence and must discard retired asynchronous samples.
/// Field meanings preserve the Lua wire contract, including omitted optionals.
public struct PhotonSceneFeed: Sendable {
    public var peak=0.5, contrast=0.35, noise=0.10
    public var block=0.0, ring=0.0, ringLevel=0.0, saturation = -1.0
    public var motion=0.20, smoothPeak=0.5, smoothContrast=0.35, smoothNoise=0.10
    public var fps=24.0
    public var isHDR=false, isCut=false, hasFeed=false
    public var baselinePBS:Double?, baselineContrast:Double?
    /// 0...1 ffmpeg hue circle. Missing is not hue 0 (red).
    public var hue:Double?
    /// -1...1 source blue/yellow balance. Missing is not neutral.
    public var warmth:Double?
    public init() {}
}

public extension PhotonSharpRuntime {
    mutating func sceneFeed(_ source:PhotonSceneFeed,now:Double)throws {
        var f=Feed();f.peak=source.peak;f.contrast=source.contrast;f.noise=source.noise
        f.motion=source.motion;f.isCut=source.isCut;f.hasFeed=source.hasFeed
        f.smoothPeak=source.smoothPeak;f.smoothContrast=source.smoothContrast;f.smoothNoise=source.smoothNoise
        f.block=source.block;f.ring=source.ring;f.ringLevel=source.ringLevel
        f.baselinePBS=source.baselinePBS;f.baselineContrast=source.baselineContrast
        try sceneFeed(f,now:now)
    }
}
