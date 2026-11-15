# W-gdb-030 frame-pump terminal-state vectors
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-030

target branch: ohal/gorav @ 2112af0d (lab does not push; gdb integrator integrates)
return: patch or full source + fixtures + test runner files
publication check: pinned excerpts independently matched; product tests NOT_RUN by publisher; candidate open, unclaimed.

## problem (what fails for the user)
the pump's terminal reason (endOfStream/sourceEnded/cancelled/failed) and frozen terminal counters drive the gate's EOF and close assertions; a wrong terminal mapping ships as a false PASS or a hang at clip end.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51; PumpEndReason and ResumeReceipt excerpts below).
- real test command: the returned checker runs on Linux against a candidate pump log.

## expected behaviour
vectors for each terminal state: expected reason, counters frozen at finish (presented/dropped), terminal values persisting after finish; checker replays a candidate pump's event/snapshot log.

## exact call site and interface
PumpEndReason's cases (pinned excerpt) are the asserted vocabulary.

## behaviour that must not change
terminal semantics at the pin stay; virtual clock, synthetic frames.

## acceptance test (from the product repo)
each vector's expected terminal state matches; a perturbed reason mapping fails.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, lines 233-245 of 1382)
```swift
public enum PumpEndReason: Sendable, Equatable {
    case none            // pre-finalization only; impossible after run()
    case endOfStream
    case sourceEnded
    case cancelled
    case failed(Int32)
    public var rawValue: String {
        switch self {
        case .none: return "none"
        case .endOfStream: return "endOfStream"
        case .sourceEnded: return "sourceEnded"
        case .cancelled: return "cancelled"
        case .failed(let c): return "failed:\(c)"
```

### Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, lines 641-655 of 1382)
```swift
    public struct ResumeReceipt: Sendable, Equatable {
        public let changedState: Bool
        public let paceAnchorCleared: Bool
    }
    @discardableResult
    public func resume() -> ResumeReceipt {
        guard paused, let began = pauseBeganWall else {
            return ResumeReceipt(changedState: false, paceAnchorCleared: false)
        }
        let pausedWall = Swift.max(0, ProcessInfo.processInfo.systemUptime - began)
        paused = false
        pauseBeganWall = nil
        pausedWallTotal += pausedWall
        paceAnchorPts = nil
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
