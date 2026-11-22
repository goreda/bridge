import Foundation

/// Live sharp/grain parameters, never values inferred from an encode receipt.
public struct PhotonProducerSnapshot: Sendable {
    public let token:UUID
    public let epoch:UInt64
    public let revision:UInt64
    public let sourceWidth:Int,sourceHeight:Int,outputWidth:Int,outputHeight:Int
    public let sharp:[String:Double],grain:[String:Double]
    public let hasSceneFeed:Bool
}

/// Serial owner used by the renderer under its lock. No render callback drives
/// scene smoothing. Before a real scene feed, Lua's explicit no-feed state is used.
public struct PhotonPresenterProducer: Sendable {
    public enum Failure:Error {case invalidRaster,staleEpoch,invalidTime}
    public let token=UUID()
    private var epoch:UInt64?
    private var sharp=PhotonSharpRuntime(),grain=PhotonGrainRuntime()
    private var sharpPublisher=PhotonParameterPublisher(),grainPublisher=PhotonParameterPublisher()
    private var feedPresent=false
    private var revision:UInt64=0
    public init() {}
    public mutating func reset() {self=Self()}
    public mutating func sceneFeed(_ feed:PhotonSceneFeed,epoch expected:UInt64,now:Double,position:Double?)throws {
        guard epoch==expected else {throw Failure.staleEpoch}
        guard now.isFinite,now>=0 else {throw Failure.invalidTime}
        try sharp.sceneFeed(feed,now:now)
        try grain.sceneFeed(feed,now:now,position:position,estimatedFrameNumber:nil,cachePaused:false)
        feedPresent=feed.hasFeed
    }
    public mutating func snapshot(epoch next:UInt64,sourceWidth:Int,sourceHeight:Int,
                                  outputWidth:Int,outputHeight:Int,position:Double,now:Double,pictureWidth:Double?=nil,pictureHeight:Double?=nil)throws->PhotonProducerSnapshot {
        guard [sourceWidth,sourceHeight,outputWidth,outputHeight].allSatisfy({$0>0 && $0<=16384}) else {throw Failure.invalidRaster}
        guard now.isFinite,now>=0,position.isFinite else {throw Failure.invalidTime}
        if epoch != next {
            self=Self();epoch=next
            sharp.fileLoaded();try grain.fileLoaded(now:now)
        }
        try sharp.setRaster(sourceHeight:Double(sourceHeight),outputPictureHeight:pictureHeight ?? Double(outputHeight))
        try grain.setRaster(sourceWidth:Double(sourceWidth),sourceHeight:Double(sourceHeight),outputPictureWidth:pictureWidth ?? Double(outputWidth))
        grain.clock.timePosition(position,cachePaused:false)
        _=try sharpPublisher.publish(sharp.parameters)
        _=try grainPublisher.publish(grain.parameters)
        _=try grainPublisher.grainBucket(grain.clock.bucket)
        revision &+= 1
        return PhotonProducerSnapshot(token:token,epoch:next,revision:revision,sourceWidth:sourceWidth,sourceHeight:sourceHeight,
            outputWidth:outputWidth,outputHeight:outputHeight,sharp:sharpPublisher.current,grain:grainPublisher.current,hasSceneFeed:feedPresent)
    }
}

/// Created only after the command buffer finishes successfully. Header metadata
/// is supplied separately by the host, not guessed by this producer.
public struct PhotonPresentedTelemetry: Sendable {
    public let snapshot:PhotonProducerSnapshot
    public let frameSequence:UInt64
    public init(snapshot:PhotonProducerSnapshot,frameSequence:UInt64) {self.snapshot=snapshot;self.frameSequence=frameSequence}
    public var rows:[String] {
        let s=snapshot
        func f(_ value:Double?)->String {value.map{String(format:"%.6f",$0)} ?? "unavailable"}
        return ["photon\tgrain/sharp GPU completed | "+(s.hasSceneFeed ? "scene feed":"no scene feed"),
                "sharp\tamount "+f(s.sharp["PHOTON_SHARP_AMOUNT"])+" | factor "+f(s.sharp["PHOTON_SHARP_FACTOR_RENDERED"]),
                "grain\tamount "+f(s.grain["GR_AMOUNT"])+" | strength "+f(s.grain["BASE_STRENGTH"])+" | bucket "+f(s.grain["GR_ANIM_BUCKET"])]
    }
}
