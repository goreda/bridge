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
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Package.swift",
        "block": "rf0"
      },
      {
        "path": "Sources/avsync-golden-tests/AVSyncGoldenChecker.swift",
        "block": "rf1"
      },
      {
        "path": "kits/avsync-goldens/goldens.json",
        "block": "rf2"
      },
      {
        "path": "Sources/avsync-golden-tests/main.swift",
        "block": "rfR"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "swift run avsync-golden-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:22:01.688915+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "avsync-golden-tests: 50 PASS, 0 FAIL",
    "inline_files": [
      {
        "path": "Package.swift",
        "block": "rf0",
        "sha256": "3139ba775088cf2276d8dfb4e4661a175622eea1bfb0424ad0e98bac37a4b452"
      },
      {
        "path": "Sources/avsync-golden-tests/AVSyncGoldenChecker.swift",
        "block": "rf1",
        "sha256": "e25b3551ed80f29ffd3be01ddc69508d97839b8e052f9cc9adf0d071acc79abe"
      },
      {
        "path": "kits/avsync-goldens/goldens.json",
        "block": "rf2",
        "sha256": "aa4da74996c132d50b9111ea5d5dc32f5c16d7d4748e2f592a1709bc7fed77e9"
      },
      {
        "path": "Sources/avsync-golden-tests/main.swift",
        "block": "rfR",
        "sha256": "0747e0321183cb597e81f9a8182e1cc73c502de1431068b8c6a8d180f5cac297"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "565bcd837b2c3aa4ad01bbba95f2240b5996a17a1486ed52b24856733d253f9f",
    "last_5_lines": [
      "FAIL late-edge+early-edge[11] early edge +1ms: pts=1.0 now=0.98 fd=0.04 want=wait(0.02100000000000002) got=wait(0.020000000000000018)",
      "FAIL late-edge+early-edge[12] early edge +2ms: pts=1.0 now=0.979 fd=0.04 want=wait(0.02200000000000002) got=wait(0.02100000000000002)",
      "FAIL late-edge+early-edge[13] early edge +3ms: pts=1.0 now=0.978 fd=0.04 want=wait(0.02300000000000002) got=wait(0.02200000000000002)",
      "FAIL drop-burst-recovery[8] lag 20ms: pts=4.32 now=4.341 fd=0.04 want=show got=drop",
      "negative-control +1ms flip caught 16 row(s) as required"
    ],
    "receipt_sha256": "c261f2b2184739c9f5322555f66011fbd9e99e2f71ec8ad6ad53ec483b1a3be0"
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

```text id=rf1
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

```text id=rf2
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

```text id=rf0
// swift-tools-version: 5.9
// SOURCE-ONLY PROPOSAL. Isolated decoder tree, NOT a production replacement.
// Locked include/library search paths must come from a verified provider lock.
import PackageDescription

let package = Package(
    name: "GorAVDecoderOnlyCandidate",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "frame-lease-tests", targets: ["frame-lease-tests"]), .executable(name: "audio-interrupt-tests", targets: ["audio-interrupt-tests"]), .executable(name: "cue-output-tests", targets: ["cue-output-tests"]), .executable(name: "render-graph-tests", targets: ["render-graph-tests"]), .executable(name: "decoder-inventory-tests", targets: ["decoder-inventory-tests"]), .executable(name: "color-stage-tests", targets: ["color-stage-tests"]), .executable(name: "crop-tests", targets: ["crop-tests"]), .executable(name: "frame-tap-tests", targets: ["frame-tap-tests"]), .executable(name: "media-inventory-tests", targets: ["media-inventory-tests"]), .executable(name: "remote-source-tests", targets: ["remote-source-tests"]), .executable(name: "prepared-shot-tests", targets: ["prepared-shot-tests"]), .executable(name: "hosttransform-tests", targets: ["hosttransform-tests"]), .executable(name: "timepos-tests", targets: ["timepos-tests"]), .executable(name: "avsync-golden-tests", targets: ["avsync-golden-tests"]), .executable(name: "controlbus-tests", targets: ["controlbus-tests"]), .executable(name: "gorav-probe", targets: ["gorav-probe"]), .library(name: "BridgeVTDecode", targets: ["BridgeVTDecode"]), .library(name: "AudioMasterScheduler", targets: ["AudioMasterScheduler"]), .executable(name: "gorav-sink-check", targets: ["gorav-sink-check"]), .executable(name: "gorav-first-frame", targets: ["gorav-first-frame"]), .executable(name: "refusal-tests", targets: ["refusal-tests"]), .executable(name: "playback-test", targets: ["playback-test"]), .executable(name: "audio-test", targets: ["audio-test"]), .executable(name: "seek-test", targets: ["seek-test"]), .executable(name: "audio-refusal-tests", targets: ["audio-refusal-tests"]), .executable(name: "video-refusal-tests", targets: ["video-refusal-tests"]), .executable(name: "coexist-test", targets: ["coexist-test"]), .executable(name: "isolation-test", targets: ["isolation-test"]), .executable(name: "trace-dump", targets: ["trace-dump"]), .executable(name: "core-seek-tests", targets: ["core-seek-tests"]), .executable(name: "real-seek-tests", targets: ["real-seek-tests"]), .executable(name: "seek-ring-reset-tests", targets: ["seek-ring-reset-tests"]), .executable(name: "seek-pacing-tests", targets: ["seek-pacing-tests"]), .executable(name: "seek-composition-tests", targets: ["seek-composition-tests"]), .executable(name: "audio-seek-tests", targets: ["audio-seek-tests"]), .executable(name: "audio-baseline-tests", targets: ["audio-baseline-tests"]), .executable(name: "demux-parity-tests", targets: ["demux-parity-tests"]), .executable(name: "seek-contract-tests", targets: ["seek-contract-tests"]), .executable(name: "adversarial-seek-tests", targets: ["adversarial-seek-tests"]), .executable(name: "shell-seek-bridge-tests", targets: ["shell-seek-bridge-tests"]), .executable(name: "k9-adversarial", targets: ["k9-adversarial"]), .executable(name: "shell-mac-test", targets: ["shell-mac-test"]), .executable(name: "frame-dump", targets: ["frame-dump"]), .executable(name: "gorav-play", targets: ["gorav-play"]), .executable(name: "l4-hwdecode-tests", targets: ["l4-hwdecode-tests"]), .executable(name: "timing-ledger-tests", targets: ["timing-ledger-tests"]), .executable(name: "race-witness-tests", targets: ["race-witness-tests"]), .executable(name: "gorav-metal-check", targets: ["gorav-metal-check"]), .library(name: "GorAVFFmpegAdapter", targets: ["GorAVFFmpegAdapter"]), .library(name: "GorAVAudioClockSwift", targets: ["GorAVAudioClockSwift"]), .library(name: "GorAVSubtitles", targets: ["GorAVSubtitles"]), .executable(name: "subtitle-srt-tests", targets: ["subtitle-srt-tests"]), .executable(name: "subtitle-ass-tests", targets: ["subtitle-ass-tests"]), .executable(name: "subtitle-track-tests", targets: ["subtitle-track-tests"]), .library(name: "GorAVEmbeddedShell", targets: ["GorAVEmbeddedShell"]), .executable(name: "admission-tests", targets: ["admission-tests"]), .executable(name: "session-venue-tests", targets: ["session-venue-tests"]), .executable(name: "b-gate-tests", targets: ["b-gate-tests"]), .executable(name: "seek-restart-probe", targets: ["seek-restart-probe"])],
    targets: [
        .executableTarget(name: "n6-native-tests", dependencies: ["GorAVMetalPresenter", "GorAVPlaybackCore", "GorAVSubtitles"], path: "Sources/n6-native-tests"),
        .executableTarget(name: "uniform-packing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/uniform-packing-tests"),
        .executableTarget(name: "active-transport-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter", "GorAVNativeProbeKit", "CFFmpeg"], path: "Sources/active-transport-tests"),
        .executableTarget(name: "frame-lease-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVCore"], path: "Sources/frame-lease-tests"),
        .executableTarget(name: "audio-interrupt-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/audio-interrupt-tests"),
        .executableTarget(name: "cue-output-tests", dependencies: ["GorAVSubtitles", "GorAVPlaybackCore"], path: "Sources/cue-output-tests"),
        .executableTarget(name: "render-graph-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/render-graph-tests"),
        .executableTarget(name: "decoder-lifetime-tests", dependencies: ["GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore"], path: "Sources/decoder-lifetime-tests"),
        .executableTarget(name: "decoder-inventory-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/decoder-inventory-tests"),
        .testTarget(name: "PreparedVideoSwapTests", dependencies: ["GorAVPlaybackCore"], path: "Tests/PreparedVideoSwapTests"),
        .testTarget(name: "EmbeddedPreparedShotTests", dependencies: [.target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS])), "GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Tests/EmbeddedPreparedShotTests"),
        .executableTarget(name: "color-stage-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/color-stage-tests"),
        .executableTarget(name: "crop-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/crop-tests"),
        .executableTarget(name: "frame-tap-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/frame-tap-tests"),
        .executableTarget(name: "active-media-inventory-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/active-media-inventory-tests"),
        .executableTarget(name: "media-inventory-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/media-inventory-tests"),
        .executableTarget(name: "video-remote-open-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/video-remote-open-tests"),
        .executableTarget(name: "remote-source-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/remote-source-tests"),
        .executableTarget(name: "subtitle-controller-tests", dependencies: ["GorAVSubtitles"], path: "Sources/subtitle-tests", sources: ["SubtitleControllerTests.swift"]),
        .executableTarget(name: "prepared-shot-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/prepared-shot-tests"),
        .executableTarget(name: "hosttransform-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/hosttransform-tests"),
        .executableTarget(name: "timepos-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/timepos-tests"),
        .executableTarget(name: "avsync-golden-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/avsync-golden-tests"),
        .executableTarget(name: "controlbus-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/controlbus-tests"),
        .target(name: "BridgeDemux", path: "Tests/labs/p-a1-r2/Sources/BridgeDemux"),
        .target(name: "BridgeVTDecode", dependencies: ["BridgeDemux"], path: "Sources/BridgeVTDecode"),
        .target(name: "AudioMasterScheduler", path: "Sources/AudioMasterScheduler"),
        .testTarget(name: "EngineContractTests", dependencies: ["BridgeVTDecode", "BridgeDemux", "AudioMasterScheduler"], path: "Tests/EngineContractTests"),
        .executableTarget(name: "e1-headless-tests", dependencies: ["BridgeDemux", "AudioMasterScheduler", "CFFmpeg", "GorAVPlaybackCore", "GorAVMetalPresenter"], path: "Sources/e1-headless-tests"),
        .executableTarget(name: "gorav-probe", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/gorav-probe"),


        .target(name: "GorAVCore", dependencies: ["GorAVCAtomics"], path: "Sources/GorAVCore", sources: ["Boundary.swift", "AdmissionTable.swift", "OpenURLRouter.swift"]),
        // L5/L6 u7 wiring candidate (coordinator-owned landing): parser/model library +
        // three SEPARATE @main consumer suites (one file each, never one merged target).
        .target(name: "GorAVSubtitles", path: "Sources/GorAVSubtitles", sources: ["ASSParser.swift", "SRTParser.swift", "SubtitleCue.swift", "SubtitlePlan.swift", "SubtitleSchedule.swift", "SubtitleTrack.swift", "SubtitleAutoLoad.swift", "SubtitleController.swift", "SubtitleCueOutput.swift", "SubtitleCueDelivery.swift", "SubtitleSidecarSession.swift"]),
        .executableTarget(name: "subtitle-srt-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SRTTests.swift"]),
        .executableTarget(name: "subtitle-ass-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["ASSTests.swift"]),
        .executableTarget(name: "subtitle-track-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SubtitleTrackTests.swift"]),
        .executableTarget(name: "subtitle-plan-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SubtitlePlanTests.swift"]),
        .target(name: "GorAVNativeProbeKit", dependencies: ["GorAVCore"],
                path: "Sources/GorAVNativeProbeKit",
                sources: ["GorAVSeekContract.swift", "NativeProbe.swift", "LeaseTable.swift", "PacketFeedMachine.swift", "DemuxerPolicy.swift"]),
        .systemLibrary(name: "CFFmpeg", path: "Sources/CFFmpeg"),
        // L6 Dolby Vision lane (block 78d L6; new lane dirs only, milestone-gated M4)
        .target(name: "GorAVDVRPU",
                path: "Sources/GorAVDVRPU",
                sources: ["src"],
                publicHeadersPath: "include"),
        .target(name: "GorAVDolbyVision",
                dependencies: ["GorAVDVRPU", "CFFmpeg", "GorAVCore",
                               "GorAVFFmpegAdapter"],
                path: "Sources/GorAVDolbyVision"),
        .executableTarget(name: "dovi-selftest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-selftest",
                exclude: ["swift"]),
        .executableTarget(name: "dovi-hdrtest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-hdrtest",
                exclude: ["gen_ref_fields.py"]),
        .executableTarget(name: "dovi-vectest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-vectest"),
        .executableTarget(name: "dovi-fuzz",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-fuzz"),
        .target(name: "GorAVFFmpegAdapter", dependencies: ["CFFmpeg", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/GorAVFFmpegAdapter", sources: ["FFmpegSoftwareDecoder.swift", "SnapshotInput.swift", "SnapshotAVIOOwner.swift", "FrameObservation.swift", "FFmpegSoftwareAudioDecoder.swift", "L3Admission.swift", "L3SampleConvert.swift", "L3PixelConvert.swift", "L3HardwareDecode.swift", "L3AVCoordinator.swift", "SourceOpenOptions.swift", "MediaInventory.swift", "ActiveTransportSnapshot.swift"]),        .executableTarget(name: "l4-hwdecode-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "CFFmpeg"],
                path: "Sources/l4-hwdecode-tests", sources: ["L4HWDecodeTests.swift"]),

        .executableTarget(name: "gorav-first-frame", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/gorav-first-frame", sources: ["FirstFrame.swift"]),
        .executableTarget(name: "refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/refusal-tests", sources: ["RefusalTests.swift"]),
        .executableTarget(name: "playback-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/playback-test", sources: ["PlaybackTest.swift"]),
        .executableTarget(name: "audio-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/audio-test", sources: ["AudioTest.swift"]),
        .executableTarget(name: "seek-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/seek-test", sources: ["SeekTest.swift"]),
        .executableTarget(name: "seek-restart-probe", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/seek-restart-probe", sources: ["main.swift"]),
        .executableTarget(name: "audio-refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/audio-refusal-tests", sources: ["AudioRefusalTests.swift"]),
        .executableTarget(name: "video-refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/video-refusal-tests", sources: ["VideoRefusalTests.swift"]),
        .executableTarget(name: "coexist-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/coexist-test", sources: ["CoexistTest.swift"]),
        .executableTarget(name: "isolation-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/isolation-test", sources: ["IsolationTest.swift"]),
        .executableTarget(name: "trace-dump", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/trace-dump", sources: ["TraceDump.swift"]),
        .executableTarget(name: "core-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/core-seek-tests"),
        .executableTarget(name: "real-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/real-seek-tests"),
        .executableTarget(name: "seek-ring-reset-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/seek-ring-reset-tests"),
        .target(name: "GorAVSeekComposition", dependencies: ["GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/GorAVSeekComposition"),
        .executableTarget(name: "seek-pacing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/seek-pacing-tests"),
        .executableTarget(name: "seek-composition-tests", dependencies: ["GorAVSeekComposition", "GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/seek-composition-tests"),
        .executableTarget(name: "audio-seek-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/audio-seek-tests"),
        .executableTarget(name: "demux-parity-tests", dependencies: ["BridgeDemux", "CFFmpeg"], path: "Sources/demux-parity-tests"),
        .executableTarget(name: "audio-baseline-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/audio-baseline-tests"),
        .executableTarget(name: "seek-contract-tests", dependencies: ["GorAVNativeProbeKit", "GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/seek-contract-tests"),
        .executableTarget(name: "adversarial-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/adversarial-seek-tests"),
        .executableTarget(name: "shell-seek-bridge-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/shell-seek-bridge-tests"),
        .executableTarget(name: "k9-adversarial", dependencies: ["GorAVPlaybackCore"],
                path: "Sources/k9-adversarial", sources: ["K9Adversarial.swift"]),
        .executableTarget(name: "shell-mac-test", dependencies: ["GorAVMacShell", "GorAVPlaybackCore"],
                path: "Sources/shell-mac-test", sources: ["ShellMacTest.swift"]),
        .executableTarget(name: "frame-dump", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/frame-dump", sources: ["FrameDump.swift", "ConverterVariants.swift", "RawPlaneDump.swift"]),
        .target(name: "GorAVCAtomics", path: "Sources/GorAVCAtomics", publicHeadersPath: "."),
        .target(name: "GorAVAudioClock",
                path: "Sources/GorAVAudioClock",
                sources: ["src"],
                publicHeadersPath: "include"),
        .target(name: "GorAVAudioClockSwift",
                dependencies: ["GorAVAudioClock", "GorAVCAtomics", "GorAVPlaybackCore"],
                path: "Sources/GorAVAudioClockSwift"),
        // r3 (architect r2 BLOCKER): NO explicit sources list - an explicit
        // list silently omitted Lane0Contract.swift + LifetimeRegistry.swift
        // (AudioSink/AudioStopResult/PlaybackRegistry unresolved in a real
        // package build; manual swiftc had masked it). Default = every file.
        .target(name: "GorAVPlaybackCore", dependencies: ["GorAVCAtomics", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/GorAVPlaybackCore"),
        .executableTarget(name: "session-venue-tests",
                          dependencies: ["GorAVPlaybackCore", .target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS]))],
                          path: "Sources/session-venue-tests"),
        // native87 Stage B entrypoint (B1-B3): pause-hold counter witnesses,
        // parked seek, close-from-paused report on the REAL embedded session.
        // macOS legs only; UNRUN (exit 77) elsewhere.
        .executableTarget(name: "b-gate-tests",
                          dependencies: ["GorAVPlaybackCore", .target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS]))],
                          path: "Sources/b-gate-tests"),
        .testTarget(name: "GorAVAudioClockTests",
                    dependencies: ["GorAVAudioClockSwift"],
                    path: "Tests/GorAVAudioClockTests"),
        .testTarget(name: "ReadinessAnchorTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/ReadinessAnchorTests"),
        .testTarget(name: "AudioPacingTests",
                    dependencies: ["GorAVAudioClockSwift", "GorAVPlaybackCore"],
                    path: "Tests/AudioPacingTests"),
        .testTarget(name: "J3AudioControlTests",
                    dependencies: ["GorAVAudioClockSwift", "GorAVPlaybackCore"],
                    path: "Tests/J3AudioControlTests"),
        .testTarget(name: "DecodeHeartbeatTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/DecodeHeartbeatTests"),
        .testTarget(name: "PlayerControlPlaneTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/PlayerControlPlaneTests"),
        .executableTarget(name: "pause-resume-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/pause-resume-tests"),
        .executableTarget(name: "race-witness-tests", dependencies: ["GorAVPlaybackCore"],
                          path: "Sources/race-witness-tests"),
        .executableTarget(name: "admission-tests", dependencies: ["GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"],
                          path: "Sources/admission-tests"),
        .executableTarget(name: "open-url-tests", dependencies: ["GorAVCore"], path: "Sources/open-url-tests"),
        .executableTarget(name: "audio-delay-tests", dependencies: ["GorAVPlaybackCore", "GorAVAudioClockSwift"], path: "Sources/audio-delay-tests"),
        .executableTarget(name: "window-mode-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/window-mode-tests"),
        .executableTarget(name: "observation-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/observation-tests"),
        .executableTarget(name: "timing-ledger-tests", dependencies: ["GorAVPlaybackCore"],
                path: "Sources/timing-ledger-tests", sources: ["TimingLedgerTests.swift", "SPSCTests.swift"]),
        .executableTarget(name: "gorav-sink-check", dependencies: ["GorAVMacShell"], path: "Sources/gorav-sink-check", sources: ["SinkCheck.swift"]),
        .executableTarget(name: "gorav-play", dependencies: ["GorAVMacShell", "GorAVMetalPresenter", "GorAVPlaybackCore"], path: "Sources/gorav-play", sources: ["GorAVPlay.swift"]),
        // L7 embedded shell (block 168 factory gap): the E1 host-NSView embed
        // session. Whole body is canImport(AppKit)-gated - compiles empty
        // off-Mac; a Linux build is NOT a Mac compile claim. Explicit
        // sources pin: exactly the reviewed session file; a stray file
        // dropped into the dir is uncompiled, never silently wired.
        .target(name: "GorAVEmbeddedShell",
                dependencies: ["GorAVSubtitles", "GorAVCore", "GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVMacShell", "GorAVMetalPresenter", "GorAVFFmpegAdapter", "GorAVSeekComposition", "GorAVAudioClockSwift"],
                path: "Sources/GorAVEmbeddedShell", sources: ["GorAVEmbeddedSession.swift"]),
        .target(name: "GorAVMacShell", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVSeekComposition", "GorAVAudioClockSwift"],
                path: "Sources/GorAVMacShell", sources: ["ShellClock.swift", "DisplaySink.swift", "AudioUnitSink.swift", "ShellFrameSource.swift", "FrameTap.swift", "TappedFrameLuma.swift", "WindowModeController.swift"]),
        // L2 Metal presenter lane, r7 landing (block 168 L3): new target dir
        // only; every Metal/AppKit source is canImport-gated so off-Mac
        // builds compile the target empty. GorAVMetalShellApp mirrors the
        // trunk shell contract (owner-issued session, shared CancelCommit,
        // audio-master pacing).
        .target(name: "GorAVMetalPresenter",
                dependencies: ["GorAVMacShell", "GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVSubtitles"],
                path: "Sources/GorAVMetalPresenter/core",
                sources: ["AspectFit.swift", "MetalPresenterTelemetry.swift", "SurfaceContract.swift", "MetalRenderer.swift", "MetalPresenter.swift", "GorAVMetalShellApp.swift", "StagePass.swift", "CVPixelBufferTap.swift"]),
        .executableTarget(name: "gorav-metal-check", dependencies: ["GorAVMetalPresenter", "GorAVMacShell", "GorAVPlaybackCore"],
                path: "Sources/GorAVMetalPresenter/cli", sources: ["MetalCheck.swift"])
    ]
)

```

```text id=rfR
import Foundation

// Runner for the vendored AVSyncGoldenChecker (arch-196x item 4 repair):
// replays the pinned goldens, then proves the +/-1ms negative control bites.
let goldensPath = "kits/avsync-goldens/goldens.json"
let base = runAVSyncGoldens(path: goldensPath, flipMs: 0)
print("avsync-golden-tests: \(base.pass) PASS, \(base.fail) FAIL")
let flipped = runAVSyncGoldens(path: goldensPath, flipMs: 1)
if flipped.fail == 0 {
    print("NEGATIVE-CONTROL-ERROR: +1ms flip did not fail any boundary row")
    exit(1)
}
print("negative-control +1ms flip caught \(flipped.fail) row(s) as required")
exit(base.fail == 0 ? 0 : 1)

```

```text id=actual_run_log
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-hawy90gs/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
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
[21/41] Emitting module GorAVPlaybackCore
[22/57] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[23/57] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[24/57] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[25/57] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[26/57] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[27/57] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[28/57] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[29/57] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[30/57] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[31/57] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[32/57] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[33/57] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[34/57] Compiling GorAVPlaybackCore Lane0Contract.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[35/57] Compiling GorAVPlaybackCore LifetimeRegistry.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[36/57] Compiling GorAVPlaybackCore ObservationSurface.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[37/57] Compiling GorAVPlaybackCore PlayArguments.swift
/tmp/packet-proof-hawy90gs/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[38/57] Compiling GorAVPlaybackCore PlaybackCore.swift
[39/57] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[40/57] Compiling GorAVPlaybackCore PlayheadObservers.swift
[41/57] Compiling GorAVPlaybackCore PlayheadPosition.swift
[42/57] Compiling GorAVPlaybackCore PreparedAdoption.swift
[43/57] Compiling GorAVPlaybackCore PreparedShotSession.swift
[44/57] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[45/57] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[46/57] Compiling GorAVPlaybackCore RenderGraph.swift
[47/57] Compiling GorAVPlaybackCore SPSC.swift
[48/57] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[49/57] Compiling GorAVPlaybackCore StageGeometry.swift
[50/57] Compiling GorAVPlaybackCore TapCropDetector.swift
[51/57] Compiling GorAVPlaybackCore TimingLedger.swift
[52/57] Compiling GorAVPlaybackCore UniformPacking.swift
[53/57] Compiling GorAVPlaybackCore WindowModePlan.swift
[54/58] Wrapping AST for GorAVPlaybackCore for debugging
[56/60] Compiling avsync_golden_tests AVSyncGoldenChecker.swift
[57/60] Emitting module avsync_golden_tests
[58/61] Compiling avsync_golden_tests main.swift
[59/62] Wrapping AST for avsync-golden-tests for debugging
[60/62] Write Objects.LinkFileList
[61/62] Linking avsync-golden-tests
Build complete! (6.19s)
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
