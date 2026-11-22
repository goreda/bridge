import Foundation

public enum PhotonSharpRuntimeError: Error { case invalidTime, invalidRaster, invalidCommand(String), invalidValue }

/// Runtime owner port of current candidate photon-sharp.lua, not template defaults.
/// Feed values are already-smoothed by the photon owner. This type does not
/// invent a scene feed from a single frame, nor run smoothing on render redraw.
public struct PhotonSharpRuntime: Sendable {
    public struct Feed: Sendable {
        public var peak=0.5, contrast=0.35, noise=0.10, motion=0.0
        public var isCut=false, hasFeed=false
        public var smoothPeak: Double?, smoothContrast: Double?, smoothNoise: Double?
        public var block=0.0, ring=0.0, ringLevel=0.0
        public var baselinePBS: Double?, baselineContrast: Double?
        public init() {}
    }
    private struct Character: Sendable {
        var signal=0.5, committed=0.5, rendered=0.5, dwell: Double?
        mutating func track(_ raw:Double,_ now:Double,_ dt:Double,_ cut:Bool)->Double {
            signal += (1-exp(-dt/9))*(raw-signal)
            if abs(signal-committed)<=0.12 && !cut { dwell=nil }
            else {
                if dwell == nil { dwell=now }
                if cut || now-dwell! >= 2.5 { committed=signal; dwell=nil }
            }
            rendered += (1-exp(-dt/(cut ? 0.8:3)))*(committed-rendered)
            return rendered
        }
    }
    public private(set) var enabled=false
    public private(set) var targetEnabled=true
    public private(set) var temporalMode=0
    public private(set) var adaptive=true
    public private(set) var factor=1.0, halo=0.5, texture=0.5
    public private(set) var fine=1.0, medium=1.0, coarse=1.0
    public private(set) var algorithm=0, contentAdapt=1
    private var strength=1.05, strengthRendered=1.05, factorRendered=1.0
    private var fineCoarse=0.5, smoothCoarse=0.5
    private var manualFine=false, manualNoise=false, manualFineTime=0.0, manualNoiseTime=0.0
    private var smoothPeak=0.5, smoothContrast=0.35, smoothNoise=0.1, smoothMotion=0.2
    private var sceneNoise=0.1, sceneMotion=0.2, sceneBlock=0.0, sceneRing=0.0
    private var hasFeed=false, cut=false
    private var strengthTime=0.0, factorTime=0.0, motionTime=0.0, characterTime=0.0
    private var character=Character()
    private var sourceHeight:Double?, outputHeight:Double?
    public init(targetEnabled:Bool=true) { self.targetEnabled=targetEnabled }
    private func clamp(_ x:Double,_ a:Double,_ b:Double)->Double { max(a,min(b,x)) }
    private func elapsed(_ now:Double,_ last:Double)->Double { min(now-(last>0 ? last:now-0.1),12) }
    private func smooth(_ current:Double,_ target:Double,_ attack:Double,_ release:Double,_ dt:Double)->Double {
        current+(1-exp(-dt/(target>current ? attack:release)))*(target-current)
    }
    private func validateTime(_ now:Double)throws { guard now.isFinite,now>=0 else { throw PhotonSharpRuntimeError.invalidTime } }
    public mutating func setRaster(sourceHeight:Double?,outputPictureHeight:Double?)throws {
        for h in [sourceHeight,outputPictureHeight] { if let h, !h.isFinite || h<=0 { throw PhotonSharpRuntimeError.invalidRaster } }
        self.sourceHeight=sourceHeight;self.outputHeight=outputPictureHeight
    }
    public var multiplier:Double {
        guard adaptive,let sh=sourceHeight,let oh=outputHeight else { return 1 }
        var m=clamp(sqrt(oh/sh),0.5,2)
        if sh<720 { m=min(m,0.675) }
        else if sh<1440 { m=min(m,sh<1080 ? 0.55:0.40) }
        return m
    }
    public mutating func fileLoaded() {
        strength=0.78;strengthRendered=strength;fineCoarse=0.5;smoothCoarse=0.5
        algorithm=0;strengthTime=0;factorRendered=factor;factorTime=0
        character=Character();characterTime=0
        smoothPeak=0.5;smoothContrast=0.35;smoothNoise=0.1;smoothMotion=0.2
        sceneNoise=0.1;sceneMotion=0.2;sceneBlock=0;sceneRing=0;hasFeed=false;cut=false;motionTime=0
        manualFine=false;manualNoise=false
        enabled=targetEnabled
    }
    /// Geometry/target changes push the existing live parameters, not an extra
    /// time tick. The Lua target handler likewise does not call update().
    public mutating func setTarget(_ target:Bool) { targetEnabled=target;enabled=target }
    public mutating func setAdaptive(_ value:Bool) { adaptive=value }
    public mutating func sceneFeed(_ f:Feed,now:Double)throws {
        try validateTime(now)
        let numbers=[f.peak,f.contrast,f.noise,f.motion,f.block,f.ring,f.ringLevel]
        let optional=[f.smoothPeak,f.smoothContrast,f.smoothNoise,f.baselinePBS,f.baselineContrast].compactMap{$0}
        guard (numbers+optional).allSatisfy(\.isFinite) else { throw PhotonSharpRuntimeError.invalidValue }
        sceneMotion=clamp(f.motion,0,1);cut=f.isCut;hasFeed=f.hasFeed
        if let v=f.smoothPeak { smoothPeak=v };if let v=f.smoothContrast { smoothContrast=v };if let v=f.smoothNoise { smoothNoise=v }
        sceneBlock=clamp(f.block,0,1);sceneRing=clamp(f.ringLevel,0,1)
        if !manualNoise || now-manualNoiseTime>=20 { manualNoise=false;sceneNoise=smoothNoise }
        if !manualFine || now-manualFineTime>=20 { manualFine=false;fineCoarse=clamp(1-smoothContrast,0,1) }
        var base=2.5+(4-2.5)*(1-smoothPeak)
        if let baseline=f.baselinePBS { base -= clamp(((baseline-50)/50)*0.12,-0.12,0.12) }
        strength=clamp(base,0.025,128)
        update(now)
    }
    private mutating func update(_ now:Double) {
        guard enabled else { return }
        let tauRelease=max(0.09*(1-0.25*smoothMotion),0.09*0.25)
        strengthRendered=smooth(strengthRendered,strength,cut ? 0.072:27,cut ? 0.072:tauRelease,elapsed(now,strengthTime));strengthTime=now
        factorRendered=smooth(factorRendered,factor,0.45,0.45,elapsed(now,factorTime));factorTime=now
        smoothMotion=smooth(smoothMotion,sceneMotion,0.35,0.35,elapsed(now,motionTime));motionTime=now
        let dt=elapsed(now,characterTime);characterTime=now
        if manualFine { character=Character(signal:fineCoarse,committed:fineCoarse,rendered:fineCoarse,dwell:nil);smoothCoarse=fineCoarse }
        else { smoothCoarse=character.track(fineCoarse,now,dt,cut) }
    }
    /// Returns false only for unknown messages. Bad/unsupported values throw,
    /// so a host may retain the existing visible refusal instead of no-oping.
    @discardableResult public mutating func command(_ name:String,value:Double?=nil,now:Double)throws->Bool {
        try validateTime(now)
        if let value,!value.isFinite { throw PhotonSharpRuntimeError.invalidValue }
        switch name {
        case "photon-sharp-toggle":targetEnabled.toggle();enabled=targetEnabled;return true
        case "photon-sharp-up":factor=clamp(factor+0.1,0.05,128)
        case "photon-sharp-down":factor=clamp(factor-0.1,0.05,128)
        case "photon-sharp-amount":if let value { factor=clamp(value,0.05,128) }
        case "photon-sharp-set-global":guard let value else{return true};factor=clamp(value,0.05,128)
        case "photon-sharp-fine-coarse":fineCoarse=clamp(value ?? 0.5,0,1);manualFine=true;manualFineTime=now
        case "photon-sharp-noise-gate":sceneNoise=clamp(value ?? 0.1,0,1);manualNoise=true;manualNoiseTime=now
        case "photon-sharp-set-algo":algorithm=Int(clamp(floor(value ?? 0),0,4))
        case "photon-sharp-cycle-algo":algorithm=(algorithm+1)%5
        case "photon-sharp-set-halo":guard let value else{return true};halo=clamp(value,0,1)
        case "photon-sharp-set-texture":guard let value else{return true};texture=clamp(value,0,1)
        case "photon-sharp-set-fine":guard let value else{return true};fine=clamp(value,0,4)
        case "photon-sharp-set-medium":guard let value else{return true};medium=clamp(value,0,4)
        case "photon-sharp-set-coarse":guard let value else{return true};coarse=clamp(value,0,4)
        case "photon-sharp-set-content-adapt":guard let value else{return true};contentAdapt=value != 0 ? 1:0
        case "photon-sharp-set-temporal-mode":guard let value else{return true};temporalMode=value != 0 ? 1:0;return true
        default:return false
        }
        update(now);return true
    }
    /// Same fields as the actual Lua push_params payload. Values stay Double
    /// until the renderer's single Float conversion/upload.
    public var parameters:[String:Double] {
        ["PHOTON_SHARP_FRAME_PEAK":hasFeed ? smoothPeak:-1,
         "PHOTON_SHARP_SCENE_CONTRAST":smoothContrast,"PHOTON_SHARP_NOISE_LEVEL":sceneNoise,
         "PHOTON_SHARP_MOTION_LEVEL":smoothMotion,"PHOTON_SHARP_AMOUNT":strengthRendered*multiplier,
         "PHOTON_SHARP_FINE_COARSE":smoothCoarse,"PHOTON_SHARP_FACTOR_RENDERED":factorRendered,
         "PHOTON_SHARP_TEMPORAL_ALPHA":0.65*(1-0.12*halo),"PHOTON_SHARP_HALO_GUARD":halo,
         "PHOTON_SHARP_BLOCK_LEVEL":sceneBlock*0.85,"PHOTON_SHARP_RING_LEVEL":sceneRing*0.85,
         "PHOTON_SHARP_TEXTURE_BIAS":texture,"PHOTON_SHARP_FINE_STRENGTH":fine,
         "PHOTON_SHARP_MEDIUM_STRENGTH":medium,"PHOTON_SHARP_COARSE_STRENGTH":coarse,
         "PHOTON_SHARP_ALGO":Double(algorithm),"PHOTON_SHARP_CONTENT_ADAPT":Double(contentAdapt),
         "PHOTON_SHARP_MEDIUM_BAND_ACTIVE":medium>0.001 ? 1:0,"PHOTON_SHARP_COARSE_BAND_ACTIVE":coarse>0.001 ? 1:0]
    }
}
