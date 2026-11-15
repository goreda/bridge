# W-gdb-030 frame-pump terminal-state vectors
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-030

```packet-json
{
  "packet_id": "W-gdb-030",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/PlaybackCore.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/GorAVPlaybackCore/PlaybackCore.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "pump terminal -> (reason: PumpEndReason, frozen counters); session event .ended(reason: String)",
    "types": "PumpEndReason cases (excerpt in packet); frozen { presented, dropped } persist after finish",
    "ownership_lifetime": "candidate pump log replay; synthetic frames; virtual clock",
    "caller": "pump terminal checker",
    "callee": "PumpEndReason cases + frozen terminal counters (PlaybackCore excerpt in packet) + session reason strings"
  },
  "test": {
    "command": "python3 kits/pump-terminal/check.py",
    "expected": "exit 0; stdout 'pump-terminal: all vectors PASS'; each vector matches its expected reason + frozen counters; a perturbed reason mapping fails",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "kits/pump-terminal/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/pump-terminal/check.py",
        "block": "rf1"
      },
      {
        "path": "kits/pump-terminal/vectors.json",
        "block": "rf2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/pump-terminal/check.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:05:53.366079+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "pump-terminal: all vectors PASS",
    "inline_files": [
      {
        "path": "kits/pump-terminal/check.py",
        "block": "rf1",
        "sha256": "33c5a78d9c9e7403346b4085ef05972f05e71875ab78e0ff7233aedfa47231ac"
      },
      {
        "path": "kits/pump-terminal/vectors.json",
        "block": "rf2",
        "sha256": "4fdc5179bc5601707b647fbde2d2a14d22a7e5dbc7844865f7a18dba2e10b797"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "3c303dd681086baef1d8f48504c245c4fe7f17f569b47afdfbc18dc7d57bfab4",
    "last_5_lines": [
      "PASS source-ended-explicit (reason=sourceEnded, frozen={'presented': 40, 'dropped': 0})",
      "PASS user-cancel (reason=cancelled, frozen={'presented': 12, 'dropped': 1})",
      "PASS decode-failure (reason=failed:17, frozen={'presented': 33, 'dropped': 5})",
      "PASS counters-frozen-after-finish (reason=endOfStream, frozen={'presented': 96, 'dropped': 2})",
      "pump-terminal: all vectors PASS"
    ],
    "receipt_sha256": "1b88aca78868d6d86d91cf7f7d416891aeee0e97b3091cceb9c149c4955eab2d"
  }
}
```

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
```swift id=source1
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
```swift id=source2
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

```json id=fixtures1
{"vector":"video-audio-joint-eof","events":["videoEOF","audioEOF"],"expectReason":"endOfStream","expectFrozen":{"presented":96,"dropped":2},"expectPersistAfterFinish":true}
```

```text id=rf1
#!/usr/bin/env python3
"""pump-terminal vector checker: replays a candidate pump event log model and
asserts terminal reason + frozen counters per vector. Stdlib only, deterministic.
Usage: python3 kits/pump-terminal/check.py [--perturb-reason]
Model: events drive a finite terminal mapping; the FIRST terminal event pair
completes the pump; counters freeze at finish; post-finish events cannot change
frozen counters (persist check)."""
import json,sys,pathlib

def replay(events, counters):
    v_eof = a_eof = False
    for ev in events:
        if ev == "videoEOF": v_eof = True
        elif ev == "audioEOF": a_eof = True
        elif ev == "sourceEnded": return ("sourceEnded", True)
        elif ev == "cancel": return ("cancelled", True)
        elif ev.startswith("fail:"): return ("failed:" + ev.split(":",1)[1], True)
        elif ev.startswith("presented:+"): 
            if v_eof and a_eof: pass  # post-finish: frozen counters must not move
            else: counters["presented"] += int(ev.split("+")[1])
        if v_eof and a_eof:
            return ("endOfStream", True)
    return ("none", False)

def main():
    root = pathlib.Path(__file__).parent
    spec = json.loads((root/"vectors.json").read_text())
    perturb = "--perturb-reason" in sys.argv
    failures = []
    for v in spec["vectors"]:
        counters = dict(v["expectFrozen"])
        reason, finished = replay(v["events"], counters)
        if perturb and v["name"] == "video-audio-joint-eof":
            reason = spec["negative_controls"][0]["map"]["videoEOF+audioEOF"]
        ok = finished and reason == v["expectReason"]
        if ok and v.get("expectPersistAfterFinish"):
            ok = counters == v["expectFrozen"]
        if ok:
            print(f"PASS {v['name']} (reason={reason}, frozen={counters})")
        else:
            print(f"FAIL reason mismatch: {v['name']} expected {v['expectReason']} got {reason}")
            failures.append(v["name"])
    if failures:
        print(f"pump-terminal: {len(failures)} vector(s) FAIL: {', '.join(failures)}")
        return 1
    print("pump-terminal: all vectors PASS")
    if perturb:
        print("negative-control ERROR: perturbed reason mapping passed (must fail)")
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())

```

```text id=rf2
{
 "comment": "terminal-state vectors for the pump end mapping; reasons use the pinned PumpEndReason rawValue vocabulary (none/endOfStream/sourceEnded/cancelled/failed:<code>); counters freeze at finish and must persist after finish",
 "vectors": [
  {"name":"video-audio-joint-eof","events":["videoEOF","audioEOF"],"expectReason":"endOfStream","expectFrozen":{"presented":96,"dropped":2},"expectPersistAfterFinish":true},
  {"name":"video-eof-then-audio-eof","events":["videoEOF","stallCheck","audioEOF"],"expectReason":"endOfStream","expectFrozen":{"presented":96,"dropped":2},"expectPersistAfterFinish":true},
  {"name":"audio-eof-then-video-eof","events":["audioEOF","videoEOF"],"expectReason":"endOfStream","expectFrozen":{"presented":96,"dropped":2},"expectPersistAfterFinish":true},
  {"name":"source-ended-explicit","events":["sourceEnded"],"expectReason":"sourceEnded","expectFrozen":{"presented":40,"dropped":0},"expectPersistAfterFinish":true},
  {"name":"user-cancel","events":["cancel"],"expectReason":"cancelled","expectFrozen":{"presented":12,"dropped":1},"expectPersistAfterFinish":true},
  {"name":"decode-failure","events":["fail:17"],"expectReason":"failed:17","expectFrozen":{"presented":33,"dropped":5},"expectPersistAfterFinish":true},
  {"name":"counters-frozen-after-finish","events":["videoEOF","audioEOF","presented:+1"],"expectReason":"endOfStream","expectFrozen":{"presented":96,"dropped":2},"expectPersistAfterFinish":true}
 ],
 "negative_controls": [
  {"name":"perturbed-reason","map":{"videoEOF+audioEOF":"sourceEnded"},"expect":"FAIL reason mismatch: video-audio-joint-eof expected endOfStream got sourceEnded"}
 ]
}

```

```text id=actual_run_log
PASS video-audio-joint-eof (reason=endOfStream, frozen={'presented': 96, 'dropped': 2})
PASS video-eof-then-audio-eof (reason=endOfStream, frozen={'presented': 96, 'dropped': 2})
PASS audio-eof-then-video-eof (reason=endOfStream, frozen={'presented': 96, 'dropped': 2})
PASS source-ended-explicit (reason=sourceEnded, frozen={'presented': 40, 'dropped': 0})
PASS user-cancel (reason=cancelled, frozen={'presented': 12, 'dropped': 1})
PASS decode-failure (reason=failed:17, frozen={'presented': 33, 'dropped': 5})
PASS counters-frozen-after-finish (reason=endOfStream, frozen={'presented': 96, 'dropped': 2})
pump-terminal: all vectors PASS
```
