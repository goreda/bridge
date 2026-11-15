# W-gdb-035 A/V sync boundary decision goldens
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-035

```packet-json
{
 "packet_id": "W-gdb-035",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/GorAVPlaybackCore/PlaybackCore.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "decide(ptsSeconds: Double, nowSeconds: Double, frameDuration: Double) -> FrameDecision",
  "types": "FrameDecision { drop, wait(Double), show }; half-frame-duration thresholds, wait clamped to maxWaitSeconds",
  "ownership_lifetime": "value type; thresholds: drop past half a frame late, wait (clamped) past half a frame early",
  "caller": "A/V sync golden checker",
  "callee": "AVSyncDecider.decide(ptsSeconds:nowSeconds:frameDuration:) -> FrameDecision (PlaybackCore excerpt in packet)"
 },
 "test": {
  "command": "swift run avsync-golden-tests",
  "expected": "exit 0; final line matches '^avsync-golden-tests: [1-9][0-9]* PASS, 0 FAIL$'; goldens replay green against the pinned function; a +/-1ms flip is caught and printed",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/avsync-goldens/"
  ],
  "return_form": "full-files"
 }
}
```

## problem (what fails for the user)
wait/present/drop decisions at the tolerance boundary are where frame-drop and desync bugs live; the decision function exists but lacks boundary-precision goldens.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51; FrameDecision + AVSyncDecider.decide below, lines 17-75).
- real test command: the returned checker runs on Linux; existing ledger/pacing suites stay green.

## expected behaviour
goldens at +/-1ms around the thresholds: straddling sequences, drop-burst recovery; expected decision per frame with the tolerance constant named explicitly; JSON fixtures + checker.

## exact call site and interface
AVSyncDecider.decide's signature and FrameDecision's cases (pinned excerpt) are the asserted interface.

## behaviour that must not change
the decision function's semantics at the pin stay; no physical-device claims.

## acceptance test (from the product repo)
goldens replay green against the pinned function; a +/-1ms flip is caught.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, lines 17-75 of 1382)
```swift id=source1
public enum FrameDecision: Equatable, Sendable { case show, drop, wait(Double) }

/// Shared post-seek media/wall anchor (M4): ONE authority maps media pts to
/// wall time for BOTH video frame scheduling and the audio resume, so a
/// legitimate media offset (e.g. +100ms edit-list audio start) is preserved
/// as an actual A/V offset, never collapsed by independent arrival anchoring.
public struct MediaWallAnchor: Sendable, Equatable {
    public let mediaSeconds: Double
    public let wallSeconds: Double
    public init(mediaSeconds: Double, wallSeconds: Double) {
        self.mediaSeconds = mediaSeconds; self.wallSeconds = wallSeconds
    }
    public func scheduledWall(forMediaSeconds pts: Double) -> Double {
        wallSeconds + (pts - mediaSeconds)
    }
}

/// Sync master visibility (K6 review r2 item 5): audio-master sync is
/// NOT_IMPLEMENTED. mpv masters sync to audio when an audio track is live;
/// gorav's core currently decides against the wall/display clock only. The
/// seam is explicit so the shell cannot silently assume audio-mastered pts.
public enum SyncMaster: Sendable, Equatable {
    case clock
    case audioNotImplemented // NOT_IMPLEMENTED: do not select
}

public struct AVSyncDecider: Sendable {
    public let maxWaitSeconds: Double
    public let master: SyncMaster
    public init(maxWaitSeconds: Double = 1.0, master: SyncMaster = .clock) {
        self.maxWaitSeconds = maxWaitSeconds
        self.master = master
    }
    // mpv-flavored thresholds: a frame more than half a frame-duration late
    // is dropped; more than half early waits (clamped, K6 review r2 item 2);
    // inside the window it shows.
    public func decide(ptsSeconds: Double, nowSeconds: Double, frameDuration: Double) -> FrameDecision {
        let delta = ptsSeconds - nowSeconds
        if delta < -frameDuration / 2 { return .drop }
        if delta > frameDuration / 2 { return .wait(Swift.min(delta, maxWaitSeconds)) }
        return .show
    }
}

/// Optional pixel payload for display sinks. Pure value type; Linux tests
/// leave it nil, the macOS shell's FrameSource wrapper attaches RGBA bytes.
public struct PixelPayload: Sendable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8] // RGBA, width*4 stride
    public init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width; self.height = height; self.bytes = bytes
    }
}

public struct SourceFrame: Sendable {
    public let ptsSeconds: Double
    public let durationSeconds: Double
    public let digest: String
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"ticks":[{"pts":1.0,"now":0.981,"frameDuration":0.04,"expect":"show"},{"pts":1.0,"now":1.021,"frameDuration":0.04,"expect":"drop"},{"pts":1.0,"now":0.979,"frameDuration":0.04,"expect":"wait(0.021)"}],"toleranceMs":1}
```
