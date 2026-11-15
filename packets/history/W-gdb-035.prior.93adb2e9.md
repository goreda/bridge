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
  "product_sha": "c82dc6b8d46f81fc521ff93231060ea7b57b330a",
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
    "branch": "main",
    "paths": [
      "kits/avsync-goldens/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/avsync-golden-tests/AVSyncGoldenChecker.swift",
        "block": "rf0"
      },
      {
        "path": "kits/avsync-goldens/goldens.json",
        "block": "rf1"
      },
      {
        "path": "Sources/avsync-golden-tests/Runner.swift",
        "block": "rf2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "c82dc6b8d46f81fc521ff93231060ea7b57b330a",
    "command": "swift run avsync-golden-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:30:57.451200+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "avsync-golden-tests: 50 PASS, 0 FAIL",
    "inline_files": [
      {
        "path": "Sources/avsync-golden-tests/AVSyncGoldenChecker.swift",
        "block": "rf0",
        "sha256": "e25b3551ed80f29ffd3be01ddc69508d97839b8e052f9cc9adf0d071acc79abe"
      },
      {
        "path": "kits/avsync-goldens/goldens.json",
        "block": "rf1",
        "sha256": "aa4da74996c132d50b9111ea5d5dc32f5c16d7d4748e2f592a1709bc7fed77e9"
      },
      {
        "path": "Sources/avsync-golden-tests/Runner.swift",
        "block": "rf2",
        "sha256": "78d0ae9ff548d52fb3893c8effd972d017423fe7b84dad68b90b66e25f90ed7f"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "7730c3b9336f1b06168202ace54d887b811c218c481045a3527044f79ba8a884",
    "last_5_lines": [
      "FAIL late-edge+early-edge[11] early edge +1ms: pts=1.0 now=0.98 fd=0.04 want=wait(0.02100000000000002) got=wait(0.020000000000000018)",
      "FAIL late-edge+early-edge[12] early edge +2ms: pts=1.0 now=0.979 fd=0.04 want=wait(0.02200000000000002) got=wait(0.02100000000000002)",
      "FAIL late-edge+early-edge[13] early edge +3ms: pts=1.0 now=0.978 fd=0.04 want=wait(0.02300000000000002) got=wait(0.02200000000000002)",
      "FAIL drop-burst-recovery[8] lag 20ms: pts=4.32 now=4.341 fd=0.04 want=show got=drop",
      "negative-control +1ms flip caught 16 row(s) as required"
    ],
    "receipt_sha256": "e9f1a5a14ade169d26def59f0ce0fbb55a5e769c420d5ff23980014db0cda841"
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

## repair note (arch-196x item 4)
run_recipe.inline_files added by the code owner: avsync-golden-tests target sources + kits/avsync-goldens fixtures vendored on gorav main (arch-196s disposition 3/15, H0593), plus Package.swift from the pin with the product+target wiring lines for avsync-golden-tests added (same wiring as the integrator applied on main).





```text id=rf0
import Foundation
import GorAVPlaybackCore

func bitsDouble(_ v: Any?) -> Double { Double(bitPattern: UInt64(v as? String ?? "", radix: 16) ?? 0x7ff8000000000000) }

/// Named tolerance constant: the goldens sit at +/-AVSYNC_TOLERANCE_MS around each half-frame threshold.
let AVSYNC_TOLERANCE_MS: Double = 1

func avsyncDecisionString(_ d: FrameDecision) -> String {
    switch d { case .show: return "show"; case .drop: return "drop"; case .wait(let w): return "wait(\(w))" }
}
func avsyncExpectString(_ e: [String: Any]) -> String {
    switch e["decision"] as? String ?? "" {
    case "wait": return "wait(\(bitsDouble(e["waitBits"])))"
    case let s: return s
    }
}

/// flipMs: negative control. Shifts every `now` by flipMs; a shift of +/-AVSYNC_TOLERANCE_MS must flip boundary rows.
func runAVSyncGoldens(path: String, flipMs: Double) -> (pass: Int, fail: Int) {
    var pass = 0, fail = 0
    guard let data = FileManager.default.contents(atPath: path),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let maxWait = (root["maxWaitSeconds"] as? NSNumber)?.doubleValue,
          let tol = (root["toleranceMs"] as? NSNumber)?.doubleValue else { print("FAIL cannot load \(path)"); return (0, 1) }
    if tol != AVSYNC_TOLERANCE_MS { print("FAIL toleranceMs \(tol) != AVSYNC_TOLERANCE_MS"); fail += 1 }
    let decider = AVSyncDecider(maxWaitSeconds: maxWait)
    func check(_ label: String, _ t: [String: Any]) {
        let pts = bitsDouble(t["ptsBits"])
        let now = bitsDouble(t["nowBits"]) + flipMs / 1000.0
        let fd = bitsDouble(t["fdBits"])
        let got = avsyncDecisionString(decider.decide(ptsSeconds: pts, nowSeconds: now, frameDuration: fd))
        let want = avsyncExpectString(t["expect"] as! [String: Any])
        if got == want { pass += 1 } else { fail += 1; print("FAIL \(label): pts=\(pts) now=\(now) fd=\(fd) want=\(want) got=\(got)") }
    }
    for (i, t) in (root["thresholdRows"] as? [[String: Any]] ?? []).enumerated() { check("threshold[\(i)] \(t["group"] ?? "") \(t["offsetMs"] ?? "")ms", t) }
    for key in ["straddlingSequences", "dropBurstRecovery"] {
        for s in root[key] as? [[String: Any]] ?? [] {
            for (i, t) in (s["ticks"] as? [[String: Any]] ?? []).enumerated() { check("\(s["name"] ?? "?")[\(i)] \(t["note"] ?? "")", t) }
        }
    }
    return (pass, fail)
}

```

```text id=rf1
{
 "dropBurstRecovery": [
  {
   "name": "drop-burst-recovery",
   "ticks": [
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 100ms",
     "now": 4.1,
     "nowBits": "4010666666666666",
     "pts": 4.0,
     "ptsBits": "4010000000000000"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 90ms",
     "now": 4.13,
     "nowBits": "4010851eb851eb85",
     "pts": 4.04,
     "ptsBits": "401028f5c28f5c29"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 80ms",
     "now": 4.16,
     "nowBits": "4010a3d70a3d70a4",
     "pts": 4.08,
     "ptsBits": "401051eb851eb852"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 70ms",
     "now": 4.19,
     "nowBits": "4010c28f5c28f5c3",
     "pts": 4.12,
     "ptsBits": "40107ae147ae147b"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 60ms",
     "now": 4.22,
     "nowBits": "4010e147ae147ae1",
     "pts": 4.16,
     "ptsBits": "4010a3d70a3d70a4"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 50ms",
     "now": 4.25,
     "nowBits": "4011000000000000",
     "pts": 4.2,
     "ptsBits": "4010cccccccccccd"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 40ms",
     "now": 4.28,
     "nowBits": "40111eb851eb851f",
     "pts": 4.24,
     "ptsBits": "4010f5c28f5c28f6"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 30ms",
     "now": 4.3100000000000005,
     "nowBits": "40113d70a3d70a3e",
     "pts": 4.28,
     "ptsBits": "40111eb851eb851f"
    },
    {
     "expect": {
      "decision": "show"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 20ms",
     "now": 4.34,
     "nowBits": "40115c28f5c28f5c",
     "pts": 4.32,
     "ptsBits": "401147ae147ae148"
    },
    {
     "expect": {
      "decision": "show"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 10ms",
     "now": 4.37,
     "nowBits": "40117ae147ae147b",
     "pts": 4.36,
     "ptsBits": "401170a3d70a3d71"
    },
    {
     "expect": {
      "decision": "show"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag 0ms",
     "now": 4.4,
     "nowBits": "401199999999999a",
     "pts": 4.4,
     "ptsBits": "401199999999999a"
    },
    {
     "expect": {
      "decision": "show"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "lag -10ms",
     "now": 4.430000000000001,
     "nowBits": "4011b851eb851eb9",
     "pts": 4.44,
     "ptsBits": "4011c28f5c28f5c3"
    }
   ]
  }
 ],
 "maxWaitSeconds": 1.0,
 "straddlingSequences": [
  {
   "name": "late-edge+early-edge",
   "ticks": [
    {
     "expect": {
      "decision": "show"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "late edge -3ms",
     "now": 1.0170000000000001,
     "nowBits": "3ff045a1cac08313",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "show"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "late edge -2ms",
     "now": 1.018,
     "nowBits": "3ff049ba5e353f7d",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "show"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "late edge -1ms",
     "now": 1.0190000000000001,
     "nowBits": "3ff04dd2f1a9fbe8",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "late edge +0ms",
     "now": 1.02,
     "nowBits": "3ff051eb851eb852",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "late edge +1ms",
     "now": 1.021,
     "nowBits": "3ff05604189374bc",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "late edge +2ms",
     "now": 1.022,
     "nowBits": "3ff05a1cac083127",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "drop"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "late edge +3ms",
     "now": 1.023,
     "nowBits": "3ff05e353f7ced91",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "show"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "early edge -3ms",
     "now": 0.983,
     "nowBits": "3fef74bc6a7ef9db",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "show"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "early edge -2ms",
     "now": 0.982,
     "nowBits": "3fef6c8b43958106",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "show"
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "early edge -1ms",
     "now": 0.981,
     "nowBits": "3fef645a1cac0831",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "wait",
      "waitBits": "3f947ae147ae1480",
      "waitSeconds": 0.020000000000000018
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "early edge +0ms",
     "now": 0.98,
     "nowBits": "3fef5c28f5c28f5c",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "wait",
      "waitBits": "3f95810624dd2f20",
      "waitSeconds": 0.02100000000000002
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "early edge +1ms",
     "now": 0.979,
     "nowBits": "3fef53f7ced91687",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "wait",
      "waitBits": "3f96872b020c49c0",
      "waitSeconds": 0.02200000000000002
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "early edge +2ms",
     "now": 0.978,
     "nowBits": "3fef4bc6a7ef9db2",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    },
    {
     "expect": {
      "decision": "wait",
      "waitBits": "3f978d4fdf3b6460",
      "waitSeconds": 0.02300000000000002
     },
     "fdBits": "3fa47ae147ae147b",
     "frameDuration": 0.04,
     "note": "early edge +3ms",
     "now": 0.977,
     "nowBits": "3fef4395810624dd",
     "pts": 1.0,
     "ptsBits": "3ff0000000000000"
    }
   ]
  }
 ],
 "thresholdRows": [
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3fa47ae147ae147b",
   "frameDuration": 0.04,
   "group": "threshold-late",
   "now": 1.019,
   "nowBits": "3ff04dd2f1a9fbe7",
   "offsetMs": -1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "drop"
   },
   "fdBits": "3fa47ae147ae147b",
   "frameDuration": 0.04,
   "group": "threshold-late",
   "now": 1.02,
   "nowBits": "3ff051eb851eb852",
   "offsetMs": 0,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "drop"
   },
   "fdBits": "3fa47ae147ae147b",
   "frameDuration": 0.04,
   "group": "threshold-late",
   "now": 1.021,
   "nowBits": "3ff05604189374bc",
   "offsetMs": 1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3fa47ae147ae147b",
   "frameDuration": 0.04,
   "group": "threshold-early",
   "now": 0.981,
   "nowBits": "3fef645a1cac0831",
   "offsetMs": -1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "wait",
    "waitBits": "3f947ae147ae1480",
    "waitSeconds": 0.020000000000000018
   },
   "fdBits": "3fa47ae147ae147b",
   "frameDuration": 0.04,
   "group": "threshold-early",
   "now": 0.98,
   "nowBits": "3fef5c28f5c28f5c",
   "offsetMs": 0,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "wait",
    "waitBits": "3f95810624dd2f20",
    "waitSeconds": 0.02100000000000002
   },
   "fdBits": "3fa47ae147ae147b",
   "frameDuration": 0.04,
   "group": "threshold-early",
   "now": 0.979,
   "nowBits": "3fef53f7ced91687",
   "offsetMs": 1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3fa5555555555555",
   "frameDuration": 0.041666666666666664,
   "group": "threshold-late",
   "now": 1.0198333333333334,
   "nowBits": "3ff0513cc1e098eb",
   "offsetMs": -1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3fa5555555555555",
   "frameDuration": 0.041666666666666664,
   "group": "threshold-late",
   "now": 1.0208333333333333,
   "nowBits": "3ff0555555555555",
   "offsetMs": 0,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "drop"
   },
   "fdBits": "3fa5555555555555",
   "frameDuration": 0.041666666666666664,
   "group": "threshold-late",
   "now": 1.0218333333333334,
   "nowBits": "3ff0596de8ca11c0",
   "offsetMs": 1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3fa5555555555555",
   "frameDuration": 0.041666666666666664,
   "group": "threshold-early",
   "now": 0.9801666666666666,
   "nowBits": "3fef5d867c3ece2a",
   "offsetMs": -1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "wait",
    "waitBits": "3f95555555555560",
    "waitSeconds": 0.02083333333333337
   },
   "fdBits": "3fa5555555555555",
   "frameDuration": 0.041666666666666664,
   "group": "threshold-early",
   "now": 0.9791666666666666,
   "nowBits": "3fef555555555555",
   "offsetMs": 0,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "wait",
    "waitBits": "3f965b7a32847000",
    "waitSeconds": 0.02183333333333337
   },
   "fdBits": "3fa5555555555555",
   "frameDuration": 0.041666666666666664,
   "group": "threshold-early",
   "now": 0.9781666666666666,
   "nowBits": "3fef4d242e6bdc80",
   "offsetMs": 1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3fa1111111111111",
   "frameDuration": 0.03333333333333333,
   "group": "threshold-late",
   "now": 1.0156666666666667,
   "nowBits": "3ff0402bb0cf87da",
   "offsetMs": -1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3fa1111111111111",
   "frameDuration": 0.03333333333333333,
   "group": "threshold-late",
   "now": 1.0166666666666666,
   "nowBits": "3ff0444444444444",
   "offsetMs": 0,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "drop"
   },
   "fdBits": "3fa1111111111111",
   "frameDuration": 0.03333333333333333,
   "group": "threshold-late",
   "now": 1.0176666666666667,
   "nowBits": "3ff0485cd7b900af",
   "offsetMs": 1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3fa1111111111111",
   "frameDuration": 0.03333333333333333,
   "group": "threshold-early",
   "now": 0.9843333333333333,
   "nowBits": "3fef7fa89e60f04c",
   "offsetMs": -1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "wait",
    "waitBits": "3f91111111111120",
    "waitSeconds": 0.01666666666666672
   },
   "fdBits": "3fa1111111111111",
   "frameDuration": 0.03333333333333333,
   "group": "threshold-early",
   "now": 0.9833333333333333,
   "nowBits": "3fef777777777777",
   "offsetMs": 0,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "wait",
    "waitBits": "3f921735ee402bc0",
    "waitSeconds": 0.01766666666666672
   },
   "fdBits": "3fa1111111111111",
   "frameDuration": 0.03333333333333333,
   "group": "threshold-early",
   "now": 0.9823333333333333,
   "nowBits": "3fef6f46508dfea2",
   "offsetMs": 1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3f91111111111111",
   "frameDuration": 0.016666666666666666,
   "group": "threshold-late",
   "now": 1.0073333333333334,
   "nowBits": "3ff01e098ead65b8",
   "offsetMs": -1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3f91111111111111",
   "frameDuration": 0.016666666666666666,
   "group": "threshold-late",
   "now": 1.0083333333333333,
   "nowBits": "3ff0222222222222",
   "offsetMs": 0,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "drop"
   },
   "fdBits": "3f91111111111111",
   "frameDuration": 0.016666666666666666,
   "group": "threshold-late",
   "now": 1.0093333333333334,
   "nowBits": "3ff0263ab596de8d",
   "offsetMs": 1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3f91111111111111",
   "frameDuration": 0.016666666666666666,
   "group": "threshold-early",
   "now": 0.9926666666666667,
   "nowBits": "3fefc3ece2a53491",
   "offsetMs": -1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "show"
   },
   "fdBits": "3f91111111111111",
   "frameDuration": 0.016666666666666666,
   "group": "threshold-early",
   "now": 0.9916666666666667,
   "nowBits": "3fefbbbbbbbbbbbc",
   "offsetMs": 0,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  },
  {
   "expect": {
    "decision": "wait",
    "waitBits": "3f831d5acb6f4640",
    "waitSeconds": 0.009333333333333305
   },
   "fdBits": "3f91111111111111",
   "frameDuration": 0.016666666666666666,
   "group": "threshold-early",
   "now": 0.9906666666666667,
   "nowBits": "3fefb38a94d242e7",
   "offsetMs": 1,
   "pts": 1.0,
   "ptsBits": "3ff0000000000000"
  }
 ],
 "toleranceConstant": "AVSYNC_TOLERANCE_MS",
 "toleranceMs": 1
}

```

```text id=rf2
import Foundation

// Runner for the vendored AVSyncGoldenChecker (arch-196y item 4 re-pin):
// replays the pinned goldens, then proves the +/-1ms negative control bites.
@main
struct AVSyncGoldenRunner {
    static func main() {
        let goldensPath = "kits/avsync-goldens/goldens.json"
        let base = runAVSyncGoldens(path: goldensPath, flipMs: 0)
        print("avsync-golden-tests: \(base.pass) PASS, \(base.fail) FAIL")
        let flipped = runAVSyncGoldens(path: goldensPath, flipMs: 1)
        if flipped.fail == 0 {
            print("NEGATIVE-CONTROL-ERROR: +1ms flip did not fail any boundary row")
            Foundation.exit(1)
        }
        print("negative-control +1ms flip caught \(flipped.fail) row(s) as required")
        Foundation.exit(base.fail == 0 ? 0 : 1)
    }
}

```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-oaihkknu/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-oaihkknu/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-oaihkknu/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--9C6B84B6E025C5B.txt
[7/15] Emitting module GorAVCore
[8/15] Compiling GorAVCore AdmissionTable.swift
[9/15] Compiling GorAVCore Boundary.swift
[10/16] Compiling GorAVCore OpenURLRouter.swift
[11/17] Wrapping AST for GorAVCore for debugging
[13/21] Emitting module GorAVNativeProbeKit
[14/23] Compiling GorAVNativeProbeKit NativeProbe.swift
[15/23] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[16/23] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[17/23] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[18/23] Compiling GorAVNativeProbeKit LeaseTable.swift
[19/24] Wrapping AST for GorAVNativeProbeKit for debugging
[21/47] Emitting module GorAVPlaybackCore
[22/68] Compiling GorAVPlaybackCore LabYtdlpAdapter.swift
[23/68] Compiling GorAVPlaybackCore Lane0Contract.swift
[24/68] Compiling GorAVPlaybackCore LifetimeRegistry.swift
[25/68] Compiling GorAVPlaybackCore ObservationSurface.swift
[26/68] Compiling GorAVPlaybackCore PlayArguments.swift
[27/68] Compiling GorAVPlaybackCore PlaybackCore.swift
[28/68] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[29/68] Compiling GorAVPlaybackCore PlayheadObservers.swift
[30/68] Compiling GorAVPlaybackCore PlayheadPosition.swift
[31/68] Compiling GorAVPlaybackCore PreparedAdoption.swift
[32/68] Compiling GorAVPlaybackCore PreparedShotSession.swift
[33/68] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[34/68] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[35/68] Compiling GorAVPlaybackCore RenderGraph.swift
[36/68] Compiling GorAVPlaybackCore SPSC.swift
[37/68] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[38/68] Compiling GorAVPlaybackCore StageGeometry.swift
[39/68] Compiling GorAVPlaybackCore TapCropDetector.swift
[40/68] Compiling GorAVPlaybackCore TimingLedger.swift
[41/68] Compiling GorAVPlaybackCore UniformPacking.swift
[42/68] Compiling GorAVPlaybackCore WindowModePlan.swift
[43/68] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[44/68] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[45/68] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[46/68] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[47/68] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[48/68] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[49/68] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[50/68] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[51/68] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[52/68] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[53/68] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[54/68] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[55/68] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[56/68] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[57/68] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[58/68] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[59/68] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[60/68] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[61/68] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[62/68] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[63/68] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[64/68] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-oaihkknu/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[65/69] Wrapping AST for GorAVPlaybackCore for debugging
[67/71] Emitting module avsync_golden_tests
[68/71] Compiling avsync_golden_tests AVSyncGoldenChecker.swift
[69/72] Compiling avsync_golden_tests Runner.swift
[70/73] Wrapping AST for avsync-golden-tests for debugging
[71/73] Write Objects.LinkFileList
[72/73] Linking avsync-golden-tests
Build complete! (7.24s)
avsync-golden-tests: 50 PASS, 0 FAIL
FAIL threshold[4] threshold-early 0ms: pts=1.0 now=0.981 fd=0.04 want=wait(0.020000000000000018) got=show
FAIL threshold[5] threshold-early 1ms: pts=1.0 now=0.98 fd=0.04 want=wait(0.02100000000000002) got=wait(0.020000000000000018)
FAIL threshold[7] threshold-late 0ms: pts=1.0 now=1.0218333333333331 fd=0.041666666666666664 want=show got=drop
FAIL threshold[10] threshold-early 0ms: pts=1.0 now=0.9801666666666666 fd=0.041666666666666664 want=wait(0.02083333333333337) got=show
FAIL threshold[11] threshold-early 1ms: pts=1.0 now=0.9791666666666666 fd=0.041666666666666664 want=wait(0.02183333333333337) got=wait(0.02083333333333337)
FAIL threshold[13] threshold-late 0ms: pts=1.0 now=1.0176666666666665 fd=0.03333333333333333 want=show got=drop
FAIL threshold[16] threshold-early 0ms: pts=1.0 now=0.9843333333333333 fd=0.03333333333333333 want=wait(0.01666666666666672) got=show
FAIL threshold[17] threshold-early 1ms: pts=1.0 now=0.9833333333333333 fd=0.03333333333333333 want=wait(0.01766666666666672) got=wait(0.01666666666666672)
FAIL threshold[19] threshold-late 0ms: pts=1.0 now=1.0093333333333332 fd=0.016666666666666666 want=show got=drop
FAIL threshold[23] threshold-early 1ms: pts=1.0 now=0.9916666666666667 fd=0.016666666666666666 want=wait(0.009333333333333305) got=show
FAIL late-edge+early-edge[2] late edge -1ms: pts=1.0 now=1.02 fd=0.04 want=show got=drop
FAIL late-edge+early-edge[10] early edge +0ms: pts=1.0 now=0.981 fd=0.04 want=wait(0.020000000000000018) got=show
FAIL late-edge+early-edge[11] early edge +1ms: pts=1.0 now=0.98 fd=0.04 want=wait(0.02100000000000002) got=wait(0.020000000000000018)
FAIL late-edge+early-edge[12] early edge +2ms: pts=1.0 now=0.979 fd=0.04 want=wait(0.02200000000000002) got=wait(0.02100000000000002)
FAIL late-edge+early-edge[13] early edge +3ms: pts=1.0 now=0.978 fd=0.04 want=wait(0.02300000000000002) got=wait(0.02200000000000002)
FAIL drop-burst-recovery[8] lag 20ms: pts=4.32 now=4.341 fd=0.04 want=show got=drop
negative-control +1ms flip caught 16 row(s) as required
```
