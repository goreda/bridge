# W-gdb-020 clock/scheduler scenario extension pack
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-020

```packet-json
{
 "packet_id": "W-gdb-020",
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
  "types": "FrameDecision { drop, wait(Double), show }; SyncMaster { clock, audioNotImplemented /* never selected */ }; maxWaitSeconds default 1.0; master fixed at init",
  "ownership_lifetime": "value type; virtual clock injected; master never switches mid-run",
  "caller": "FramePump pacing loop",
  "callee": "AVSyncDecider.decide(ptsSeconds:nowSeconds:frameDuration:) -> FrameDecision; SyncMaster fixed at init"
 },
 "test": {
  "command": "swift run timing-ledger-tests && swift run seek-pacing-tests",
  "expected": "exit 0 for both; existing checks stay green; new scenario rows replay green; a perturbed drift constant fails its scenario with the row printed",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/clock-scenarios/",
   "Sources/timing-ledger-tests/",
   "Sources/seek-pacing-tests/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
the pacing loop's clock handling is covered for the 600s/25fps and five-seek scenarios; sustained drift, jitter bursts, host-clock jumps and paused-span removal are uncovered, and the audio-master seam is unasserted (no mid-run master switch exists in the product), so a scheduler regression there ships as A/V desync.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, 75946B) - FramePump, AVSyncDecider, SyncMaster; Sources/timing-ledger-tests/TimingLedgerTests.swift (sha256 df7a440e) and Sources/seek-pacing-tests/SeekPacingTests.swift (sha256 da6f453c) - the existing deterministic-clock suites.
- real test command: swift run timing-ledger-tests + swift run seek-pacing-tests (Linux, Swift 6.1.2).

## expected behaviour
new deterministic JSON scenarios (virtual-clock ticks only, no sleeps) for the four uncovered classes plus one master-seam honesty scenario, with expected wait/present/drop tables per scenario and a runner that replays them against the production decision path.

## exact call site and interface
the AVSyncDecider/SyncMaster decision interface in the pinned PlaybackCore; fixtures + runner extend the existing ledger/pacing suites.

## pinned ABI decisions (integrator, 2026-11-15; master-switch contradiction resolved)
- SyncMaster (PlaybackCore.swift, same pin): public enum SyncMaster { case clock; case audioNotImplemented /* NOT_IMPLEMENTED: do not select */ }; AVSyncDecider carries `public let master: SyncMaster` FIXED at init (default .clock). there is no mid-run master switch in the product; the earlier "master switch mid-run" scenario class is REPLACED by a master-seam honesty scenario: decide() is wall/display-clock only and never reads master; the shell must never select .audioNotImplemented.
- the decide table the scenarios assert: delta = ptsSeconds - nowSeconds; delta < -frameDuration/2 -> .drop; delta > +frameDuration/2 -> .wait(min(delta, maxWaitSeconds)); otherwise .show; maxWaitSeconds default 1.0 (mpv-flavored, K6 review r2 item 2 clamp).
- the four real scenario classes (sustained drift, jitter bursts, host-clock jumps, paused-span removal) assert exactly this table under virtual-clock ticks.

## behaviour that must not change
the existing ledger/pacing checks stay green; scheduler evidence stays virtual-clock - never physical-device claims.

## acceptance test (from the product repo)
the new scenarios replay green; a perturbed drift constant fails the affected scenario (negative control shown); fixtures byte-deterministic.

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
{"scenario":"sustained-drift","ticks":[{"pts":1.000,"now":0.990,"frameDuration":0.04,"expect":"show"},{"pts":1.000,"now":0.980,"frameDuration":0.04,"expect":"wait(0.020000000000000018)"},{"pts":1.040,"now":1.071,"frameDuration":0.04,"expect":"drop"},{"pts":1.125,"now":1.000,"frameDuration":0.04,"expect":"wait(0.125)"}],"masterSeam":"clock-only; audioNotImplemented never selected","boundaryNote":"1.0-0.98 is 0.020000000000000018 in Double, strictly greater than frameDuration/2, so the pinned decide table waits; the exact half-frame tick is kept as a documented boundary row"}
```
