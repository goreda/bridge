# W-gdb-199au-in2tinct-04 - AudioMasterClock refuses non-monotonic host-time anchors in updateAudio (pre-seek/pre-reset stragglers)
state: OPEN / unclaimed
lab: in2tinct
row: GORAV-MULTIAUDIO-PARITY (A3)

Patch + tests authored by gdb (Ops, leg A) under arch-199au item 6; in2tinct verifies and ingests per the leg/lab rules. Real production change plus semantic Linux tests, both executed against the pin before publication (run proof below). Support-only: no native/UI/playback/Darwin claims, no gorav main ref change, no paid CI; integration lands on the target lane branch only after lab verification and integrator review.

PROBLEM. updateAudio(mediaTime:hostTime:) accepted any finite sample, including one whose hostTime predates the current anchor. On the owner's shared MONOTONIC origin clock (AudioClock.swift documents the contract) such a sample is a straggler captured before the last reset/seek - e.g. an audio-thread sample in flight across a seek. Accepting it re-anchors the NEW timeline backwards: mediaTime jumps back and frames that already earned present/drop return to wait, a visible post-seek stutter.

DECISION. Refuse non-monotonic host anchors (hostTime < host) in updateAudio, failing closed like the existing non-finite guards; equal-host re-anchoring stays legal. The documented contract 'extrapolation of the most recent audio sample' is now enforced against the anchor instant. No signature change, no protocol change, classification (wait/present/drop, generation discrimination) untouched.

Scope boundaries: this packet touches only the listed files. It does not touch the returned/conflicting paths ABLoopPolicy.swift, SubtitleSelectionPolicy.swift, ASSParser.swift or the CacheAccounting.swift chain, and does not re-open their rows. No generic tooling, no label-only work, no fabricated evidence: every check below ran on this exact patch against the exact pin.

Repo goreda/gorav main pin 087c15cc068daf1e74112d436e63f07b3d254be4. Test toolchain: official Swift 6.2.3 (ubuntu22.04) on PATH, -swift-version 6 strict concurrency. Return full files on target branch lane/199au/audio-master-scheduler-straggler-refusal; the patch against the pin is derivable from the inline sources. Keep .build out of git.

```packet-json
{
  "packet_id": "W-gdb-199au-in2tinct-04",
  "lab": "in2tinct",
  "writer": "gdb",
  "code_owner": "gdb (Ops leg A) authored the patch and tests; goreda owns the gorav trunk integration decision; in2tinct verifies and ingests the listed files only",
  "product_repo": "goreda/gorav",
  "product_sha": "087c15cc068daf1e74112d436e63f07b3d254be4",
  "touched_files": [
    {
      "path": "Sources/AudioMasterScheduler/AudioMasterScheduler.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "AudioMasterClock.updateAudio(mediaTime:hostTime:) (semantics: non-monotonic hostTime refused); mediaTime(at:), decide overloads unchanged",
    "types": "VideoDecision, AudioMasterScheduler (protocol), AudioMasterClock (additive guard only)",
    "ownership_lifetime": "Owned production path Sources/AudioMasterScheduler/AudioMasterScheduler.swift only.",
    "caller": "Audio render thread anchor updates and the seek/reset paths of the session scheduler; unchanged call sites compile.",
    "callee": "Pure timeline math; no decoder, clock-core or session coupling."
  },
  "scope": "product",
  "test": {
    "command": "swiftc -swift-version 6 -o /tmp/wgdb199au04 Sources/AudioMasterScheduler/AudioMasterScheduler.swift kits/199au/in2tinct-04/main.swift && /tmp/wgdb199au04",
    "expected": "exit 0; log ends 'SEMANTIC_PASS W-gdb-199au-in2tinct-04 16 checks'",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/199au/audio-master-scheduler-straggler-refusal",
    "paths": [
      "Sources/AudioMasterScheduler/AudioMasterScheduler.swift",
      "kits/199au/in2tinct-04/main.swift"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/AudioMasterScheduler/AudioMasterScheduler.swift",
        "block": "source1"
      },
      {
        "path": "kits/199au/in2tinct-04/main.swift",
        "block": "fixtures1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "087c15cc068daf1e74112d436e63f07b3d254be4",
    "command": "swiftc -swift-version 6 -o /tmp/wgdb199au04 Sources/AudioMasterScheduler/AudioMasterScheduler.swift kits/199au/in2tinct-04/main.swift && /tmp/wgdb199au04",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-20T20:39:44.911934+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "SEMANTIC_PASS",
    "inline_files": [
      {
        "path": "Sources/AudioMasterScheduler/AudioMasterScheduler.swift",
        "block": "source1",
        "sha256": "0b147905ae4ebd9770b43e79f2f373e2b3dfd8e77fdb1bb8429174510d719349"
      },
      {
        "path": "kits/199au/in2tinct-04/main.swift",
        "block": "fixtures1",
        "sha256": "5bbd2cbaae25b38a422d20295a7987fa7ae24d13154a915c3a4faad88c664bfd"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "127a09bd86a9df6be5d531ed7fa5f012f8a87e59a362987d0b834db954a3e809",
    "last_5_lines": [
      "PASS S2 forward sample after refused straggler still anchors",
      "PASS S3 pre-seek straggler refused",
      "PASS S4 first post-seek sample anchors",
      "PASS S5 equal-host re-anchor after seek accepted",
      "SEMANTIC_PASS W-gdb-199au-in2tinct-04 16 checks"
    ],
    "receipt_sha256": "91404898e27268be25f5e10b5d24bc9be946eb7fdbdaf926c481dd8e617f34c8"
  }
}
```

```swift id=source1
import Foundation

public enum VideoDecision: Equatable, Sendable { case wait, present, drop }

public protocol AudioMasterScheduler {
    mutating func reset(audioTime: Double, hostTime: Double)
    mutating func seek(to seconds: Double, hostTime: Double)
    mutating func updateAudio(mediaTime: Double, hostTime: Double)
    func mediaTime(at hostTime: Double) -> Double
    @available(*, deprecated, message: "Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity")
    mutating func decide(videoPTS: Double, hostTime: Double) -> VideoDecision
}

/// Rate-one extrapolation of the most recent audio sample, in seconds.
/// Finite timestamps are required. Invalid decisions fail closed with drop;
/// invalid anchors are ignored. reset starts a new timeline and clears counters.
/// The PTS-only API tracks waiting PTS across seek, but has no frame identity.
/// Use the generation overload for complete stale-frame discrimination.
public struct AudioMasterClock: AudioMasterScheduler, Sendable {
    public static let maxLate = 0.040
    public static let tolerance = 1e-9
    public private(set) var generation: UInt64 = 0
    private var audio = 0.0
    private var host = 0.0
    private var waiting: Set<Double> = []
    private var stalePTS: Set<Double> = []
    public init() {}

    public mutating func reset(audioTime: Double, hostTime: Double) {
        guard audioTime.isFinite, hostTime.isFinite else { return }
        generation &+= 1
        waiting.removeAll(); stalePTS.removeAll()
        audio = audioTime; host = hostTime
    }
    public mutating func seek(to seconds: Double, hostTime: Double) {
        guard seconds.isFinite, hostTime.isFinite else { return }
        generation &+= 1
        stalePTS.formUnion(waiting); waiting.removeAll()
        audio = seconds; host = hostTime
    }
    /// Non-monotonic host anchors are refused: on the owner's shared monotonic
    /// origin clock, hostTime < host means the sample was captured before the
    /// current anchor (a pre-seek/pre-reset straggler), not the most recent
    /// sample. Re-anchoring from it would drag the new timeline backwards and
    /// stall frames that already earned present/drop.
    public mutating func updateAudio(mediaTime: Double, hostTime: Double) {
        guard mediaTime.isFinite, hostTime.isFinite else { return }
        guard hostTime >= host else { return }
        audio = mediaTime; host = hostTime
    }
    public func mediaTime(at hostTime: Double) -> Double {
        audio + (hostTime - host)
    }
    @available(*, deprecated, message: "Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity")
    public mutating func decide(videoPTS: Double, hostTime: Double) -> VideoDecision {
        guard videoPTS.isFinite, hostTime.isFinite else { return .drop }
        if stalePTS.contains(videoPTS) { return .drop }
        let result = classify(videoPTS: videoPTS, hostTime: hostTime)
        if result == .wait { waiting.insert(videoPTS) } else { waiting.remove(videoPTS) }
        return result
    }
    /// Capture generation when a frame is enqueued, not when it is evaluated.
    /// All pre-seek frames drop, including unseen or repeated-PTS frames.
    /// This additive overload leaves the packet's protocol unchanged.
    public func decide(videoPTS: Double, hostTime: Double, generation frameGeneration: UInt64) -> VideoDecision {
        guard frameGeneration == generation else { return .drop }
        return classify(videoPTS: videoPTS, hostTime: hostTime)
    }
    private func classify(videoPTS: Double, hostTime: Double) -> VideoDecision {
        guard videoPTS.isFinite, hostTime.isFinite else { return .drop }
        let offset = mediaTime(at: hostTime) - videoPTS
        guard offset.isFinite else { return .drop }
        if offset > Self.maxLate + Self.tolerance { return .drop }
        if offset < 0 { return .wait }
        return .present
    }
}
```

```swift id=fixtures1
import Foundation

// W-gdb-199au-in2tinct-04 semantic tests for AudioMasterClock updateAudio
// non-monotonic host-anchor refusal. Compiles against the PATCHED production
// file Sources/AudioMasterScheduler/AudioMasterScheduler.swift (same module,
// no source-copy stage). Exit 0 only when every check passes.

var failures = 0
@MainActor func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " " + info))
    if !ok { failures += 1 }
}

var c = AudioMasterClock()

// B-series: baseline anchoring and classification preserved
c.reset(audioTime: 10, hostTime: 100)
check("B1 reset anchors timeline", c.mediaTime(at: 101) == 11, "\(c.mediaTime(at: 101))")
c.updateAudio(mediaTime: 11.5, hostTime: 101.5)
check("B2 forward sample re-anchors", c.mediaTime(at: 102) == 12, "\(c.mediaTime(at: 102))")
c.updateAudio(mediaTime: 12.0, hostTime: 101.5)
check("B3 equal-host sample accepted", c.mediaTime(at: 102) == 12.5, "\(c.mediaTime(at: 102))")
c.updateAudio(mediaTime: .nan, hostTime: 103)
check("B4 non-finite mediaTime refused", c.mediaTime(at: 103) == 13.5, "\(c.mediaTime(at: 103))")
c.updateAudio(mediaTime: 13.5, hostTime: .infinity)
check("B5 non-finite hostTime refused", c.mediaTime(at: 104) == 14.5, "\(c.mediaTime(at: 104))")
let genBefore = c.generation
c.reset(audioTime: .nan, hostTime: 200)
check("B6 non-finite reset ignored, generation unchanged", c.generation == genBefore && c.mediaTime(at: 104) == 14.5)

c.reset(audioTime: 10, hostTime: 100)
check("B7 future frame waits", c.decide(videoPTS: 11, hostTime: 100) == .wait)
check("B8 on-time frame presents", c.decide(videoPTS: 10.0, hostTime: 100) == .present)
check("B9 late frame drops", c.decide(videoPTS: 9.9, hostTime: 100) == .drop)
let g0 = c.generation
c.reset(audioTime: 10, hostTime: 100)
check("B10 stale-generation frame drops", c.decide(videoPTS: 10.01, hostTime: 100, generation: g0) == .drop)
check("B11 current-generation frame still classified", c.decide(videoPTS: 10.0, hostTime: 100, generation: c.generation) == .present)

// S-series: straggler refusal (the patch)
c.reset(audioTime: 30, hostTime: 500)
c.updateAudio(mediaTime: 29.9, hostTime: 499.5)
check("S1 pre-reset straggler refused", c.mediaTime(at: 600) == 130, "\(c.mediaTime(at: 600))")
c.updateAudio(mediaTime: 31, hostTime: 501)
check("S2 forward sample after refused straggler still anchors", c.mediaTime(at: 502) == 32, "\(c.mediaTime(at: 502))")
c.seek(to: 5, hostTime: 800)
c.updateAudio(mediaTime: 4.0, hostTime: 799.9)
check("S3 pre-seek straggler refused", c.mediaTime(at: 800.5) == 5.5, "\(c.mediaTime(at: 800.5))")
c.updateAudio(mediaTime: 5.5, hostTime: 800.5)
check("S4 first post-seek sample anchors", c.mediaTime(at: 801) == 6.0, "\(c.mediaTime(at: 801))")
c.updateAudio(mediaTime: 6.0, hostTime: 800.5)
check("S5 equal-host re-anchor after seek accepted", c.mediaTime(at: 801) == 6.5, "\(c.mediaTime(at: 801))")

if failures == 0 {
    print("SEMANTIC_PASS W-gdb-199au-in2tinct-04 16 checks")
} else {
    print("SEMANTIC_FAIL W-gdb-199au-in2tinct-04 \(failures) failures")
    exit(1)
}
```

```text id=actual_run_log
kits/199au/in2tinct-04/main.swift:32:34: warning: 'decide(videoPTS:hostTime:)' is deprecated: Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity [#DeprecatedDeclaration]
30 | 
31 | c.reset(audioTime: 10, hostTime: 100)
32 | check("B7 future frame waits", c.decide(videoPTS: 11, hostTime: 100) == .wait)
   |                                  `- warning: 'decide(videoPTS:hostTime:)' is deprecated: Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity [#DeprecatedDeclaration]
33 | check("B8 on-time frame presents", c.decide(videoPTS: 10.0, hostTime: 100) == .present)
34 | check("B9 late frame drops", c.decide(videoPTS: 9.9, hostTime: 100) == .drop)

kits/199au/in2tinct-04/main.swift:33:38: warning: 'decide(videoPTS:hostTime:)' is deprecated: Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity [#DeprecatedDeclaration]
31 | c.reset(audioTime: 10, hostTime: 100)
32 | check("B7 future frame waits", c.decide(videoPTS: 11, hostTime: 100) == .wait)
33 | check("B8 on-time frame presents", c.decide(videoPTS: 10.0, hostTime: 100) == .present)
   |                                      `- warning: 'decide(videoPTS:hostTime:)' is deprecated: Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity [#DeprecatedDeclaration]
34 | check("B9 late frame drops", c.decide(videoPTS: 9.9, hostTime: 100) == .drop)
35 | let g0 = c.generation

kits/199au/in2tinct-04/main.swift:34:32: warning: 'decide(videoPTS:hostTime:)' is deprecated: Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity [#DeprecatedDeclaration]
32 | check("B7 future frame waits", c.decide(videoPTS: 11, hostTime: 100) == .wait)
33 | check("B8 on-time frame presents", c.decide(videoPTS: 10.0, hostTime: 100) == .present)
34 | check("B9 late frame drops", c.decide(videoPTS: 9.9, hostTime: 100) == .drop)
   |                                `- warning: 'decide(videoPTS:hostTime:)' is deprecated: Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity [#DeprecatedDeclaration]
35 | let g0 = c.generation
36 | c.reset(audioTime: 10, hostTime: 100)

[#DeprecatedDeclaration]: <https://docs.swift.org/compiler/documentation/diagnostics/deprecated-declaration>
PASS B1 reset anchors timeline
PASS B2 forward sample re-anchors
PASS B3 equal-host sample accepted
PASS B4 non-finite mediaTime refused
PASS B5 non-finite hostTime refused
PASS B6 non-finite reset ignored, generation unchanged
PASS B7 future frame waits
PASS B8 on-time frame presents
PASS B9 late frame drops
PASS B10 stale-generation frame drops
PASS B11 current-generation frame still classified
PASS S1 pre-reset straggler refused
PASS S2 forward sample after refused straggler still anchors
PASS S3 pre-seek straggler refused
PASS S4 first post-seek sample anchors
PASS S5 equal-host re-anchor after seek accepted
SEMANTIC_PASS W-gdb-199au-in2tinct-04 16 checks
```
