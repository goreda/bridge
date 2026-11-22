import Foundation

/// Film-frame grain seed clock. No wall-time/render/HUD ticks advance it.
/// Matches the current photon-grain.lua frame/position/cut state machine.
public struct PhotonGrainClock: Sendable {
    public private(set) var bucket=0.0
    public private(set) var offset=0.0
    public private(set) var fps=24.0
    public private(set) var frameNumberAvailable=false
    private var position:Double?,lastFeedPosition:Double?
    private var pauseWas=false,cacheWas=false
    public init() {}
    public var rate:Double { fps>=5 ? fps:fps*0.75 }
    /// Diagnostic fallback poll cadence, not a request to poll from the UI.
    public var pollInterval:Double { min(max(1/(max(rate,4)*2),0.005),0.25) }
    /// Lua intentionally keeps frameNumberAvailable and pause/cache edge
    /// memory across a file load. Mirror it, rather than "fixing" the source.
    public mutating func fileLoaded() { bucket=0;offset=0;position=nil;lastFeedPosition=nil }
    private mutating func applyFrame(_ frame:Double?) {
        guard let frame,frame.isFinite else{return}
        frameNumberAvailable=true;bucket=floor(frame+0.5)+offset
    }
    private func frameIndex(_ pos:Double)->Double { floor(max(pos,0)*rate+(fps>=5 ? 0.5:0)) }
    private mutating func updatePosition(_ pos:Double?,cachePaused:Bool) {
        guard let pos,pos.isFinite,!cachePaused,pos != position else{return}
        position=pos;bucket=frameIndex(pos)+offset
    }
    public mutating func timePosition(_ pos:Double?,cachePaused:Bool) {
        guard !frameNumberAvailable else{return};updatePosition(pos,cachePaused:cachePaused)
    }
    public mutating func pollFrame(_ frame:Double?,paused:Bool,cachePaused:Bool) {
        guard !paused,!cachePaused else{return};applyFrame(frame)
    }
    public mutating func playbackRestart(frame:Double?,paused:Bool,cachePaused:Bool) {
        guard paused,!cachePaused else{return};applyFrame(frame)
    }
    /// pauseEvent is nil for a cache-edge observer, Bool for an actual pause
    /// observer. A false->true edge is the actual frame-step completion event.
    public mutating func pauseOrCacheChanged(pauseEvent:Bool?,paused:Bool,cachePaused:Bool,
                                             frame:Double?,position:Double?) {
        if cacheWas && !cachePaused && paused { applyFrame(frame) }
        cacheWas=cachePaused
        if !cachePaused {
            if frameNumberAvailable {
                if !paused { pollFrame(frame,paused:paused,cachePaused:cachePaused) }
                else if pauseEvent == true && !pauseWas { applyFrame(frame) }
            } else { updatePosition(position,cachePaused:cachePaused) }
        }
        if let pauseEvent {pauseWas=pauseEvent}
    }
    /// A stale feed cannot reseed the frozen image. Rate changes reanchor
    /// only the position fallback; a known frame number is rate-free.
    public mutating func sceneFeed(fps nextFPS:Double?,isCut:Bool,position:Double?,
                                    frame:Double?,cachePaused:Bool) {
        if let nextFPS,nextFPS.isFinite,nextFPS>=1,nextFPS<=240,nextFPS != fps {
            fps=nextFPS
            if !frameNumberAvailable {self.position=nil;updatePosition(position,cachePaused:cachePaused)}
        }
        if isCut,let position,position.isFinite,position != lastFeedPosition,!cachePaused {
            offset += 137
            if frameNumberAvailable,let frame,frame.isFinite {bucket=floor(frame+0.5)+offset}
            else {bucket=frameIndex(position)+offset}
        }
        if !cachePaused {lastFeedPosition=position}
    }
}
