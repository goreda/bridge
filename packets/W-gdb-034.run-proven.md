# W-gdb-034 end-of-stream signaling vectors
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-034

```packet-json
{
  "packet_id": "W-gdb-034",
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
    "signatures": "onEvent?(.ended(reason: String))",
    "types": "reason strings exactly: eof | sourceEnded | windowClosed | cancelled; one terminal event per pump run",
    "ownership_lifetime": "event log replay; synthetic streams; one terminal event per pump run",
    "caller": "EOS vector checker",
    "callee": "session event sink .ended(reason: String) with exact strings eof/sourceEnded/windowClosed/cancelled (pinned below)"
  },
  "test": {
    "command": "python3 kits/eos-vectors/check.py",
    "expected": "exit 0; stdout 'eos-vectors: all vectors PASS'; each vector matches its expected event sequence with typed reasons; a seeded early EOS fails",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "kits/eos-vectors/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/eos-vectors/check.py",
        "block": "rf1"
      },
      {
        "path": "kits/eos-vectors/vectors.json",
        "block": "rf2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/eos-vectors/check.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:05:16.203119+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "eos-vectors: all vectors PASS",
    "inline_files": [
      {
        "path": "kits/eos-vectors/check.py",
        "block": "rf1",
        "sha256": "0c2d1081f80cf94c40f6cc319bb785e8b078396328dcdc7ddcb4cb97d75cc2ba"
      },
      {
        "path": "kits/eos-vectors/vectors.json",
        "block": "rf2",
        "sha256": "222999da9b04001b5adee80489a7c0903b3e693b5a6d1db6797055694b7aa47f"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "0fd7029874406c39074f5a767cc3930bd2d97b6ba46e49214d239a38f49ac148",
    "last_5_lines": [
      "negative control early: detected (fails as required)",
      "negative control pause: detected (fails as required)",
      "negative control dup: detected (fails as required)",
      "negative control reason: detected (fails as required)",
      "eos-vectors: all vectors PASS"
    ],
    "receipt_sha256": "a913895783cd46e9771d37efdd19c596f59a3dc84658afabd35ff1a254f5ae0f"
  }
}
```

## problem (what fails for the user)
EOS must signal exactly once, at true end, with the typed reason; early EOS (during pause) or late/duplicated EOS shows as a truncated clip or a stuck-at-end player.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51; PumpEndReason excerpt below).
- real test command: the returned checker runs on Linux against a candidate pipeline log.

## expected behaviour
EOS event-ordering vectors: video-only EOF, audio-only EOF, joint EOF, late packets after one stream's EOF, EOF during pause (must not signal early), EOF exactly at a seek target; expected event sequences with typed reasons.

## exact call site and interface
PumpEndReason.endOfStream + the session's ended(reason:) vocabulary (pinned excerpt and pin) are asserted.

## pinned ABI decisions (integrator, 2026-11-15; ended(reason:) interface)
the session's terminal event is the typed enum case .ended(reason: String) on the session event sink (GorAVEmbeddedSession.swift, same pin; onEvent?(.ended(reason:))). reason strings at the pin are EXACTLY: "eof" (PumpEndReason.endOfStream), "sourceEnded", "windowClosed" (cancelled with the window closed), "cancelled" (any other cancel). mapping at the pin (session pump-end switch): .endOfStream -> "eof"; .sourceEnded -> "sourceEnded"; .cancelled + windowClosed -> "windowClosed"; .cancelled -> "cancelled"; failures ride their typed code path, not a bare string guess. EOS vectors assert these exact strings, in order, exactly one terminal event per pump run.

## behaviour that must not change
the typed-reason vocabulary stays; synthetic streams only.

## acceptance test (from the product repo)
each vector's expected event sequence matches; a seeded early EOS fails.

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

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"vector":"eof-during-pause","events":["pause","videoEOF","audioEOF","resume","trueEOF"],"expect":["<no ended before trueEOF>","ended(eof)"]}
```

```text id=rf1
#!/usr/bin/env python3
"""EOS event-ordering vector checker (python3 stdlib only). Synthetic streams only.
Reference model of the pinned mapping (W-gdb-034, product pin 2112af0d...):
  endOfStream->"eof", sourceEnded->"sourceEnded", cancelled+windowClosed->"windowClosed", cancelled->"cancelled".
Input events: videoPacket audioPacket videoEOF audioEOF trueEOF pause resume seek:<t> sourceEnded cancel cancel:windowClosed
trueEOF = demuxer drained signal; it terminates with "eof" only if every configured stream hit EOF and not paused
(paused: deferred until resume). Seek clears per-stream EOF; a seek to target >= vector duration lands at end, so all streams are at EOF (EOF exactly at seek target). Unknown tokens abort loudly. Exactly one terminal event per pump run.
Output: list of [event_index, reason]. Candidate logs: python3 check.py --log FILE
(JSON: {"<vector>": [[idx,"reason"],...], ...}) are compared against the expected sequences.
"""
import json, os, sys
VOCAB = ("eof", "sourceEnded", "windowClosed", "cancelled")
HERE = os.path.dirname(os.path.abspath(__file__))

KNOWN = {"videoPacket","audioPacket","videoEOF","audioEOF","trueEOF","pause","resume","sourceEnded","cancel","cancel:windowClosed"}

def model(streams, events, bug=None, duration=None):
    eofd, paused, pend, out, done = set(), False, False, [], False
    def term(i, r):
        nonlocal done
        if not done:
            done = True; out.append([i, r])
    for i, e in enumerate(events):
        if not (e in KNOWN or (e.startswith("seek:") and float(e[5:]) >= 0)):
            raise SystemExit("unknown event token %r at index %d" % (e, i))
        if done: continue  # late events after terminal: ignored
        if bug == "early" and e.endswith("EOF") and e != "trueEOF":
            term(i, "eof"); continue            # seeded: first stream EOF ends
        if bug == "pause" and e == "trueEOF":
            term(i, "eof"); continue            # seeded: ignores pause / streams
        if bug == "dup" and e == "trueEOF" and eofd >= set(streams) and not paused:
            term(i, "eof"); out.append([i, "eof"]); continue  # seeded: duplicate
        if bug == "reason" and e == "trueEOF" and eofd >= set(streams) and not paused:
            term(i, "endOfStream"); continue    # seeded: wrong string
        if e == "videoEOF": eofd.add("video")
        elif e == "audioEOF": eofd.add("audio")
        elif e == "pause": paused = True
        elif e == "resume":
            paused = False
            if pend and eofd >= set(streams): term(i, "eof")
        elif e.startswith("seek:"):
            eofd.clear(); pend = False
            if duration is not None and float(e[5:]) >= duration: eofd.update(streams)  # landing at/after end: streams are at EOF
        elif e == "trueEOF":
            if eofd >= set(streams):
                if paused: pend = True
                else: term(i, "eof")
        elif e == "sourceEnded": term(i, "sourceEnded")
        elif e == "cancel:windowClosed": term(i, "windowClosed")
        elif e == "cancel": term(i, "cancelled")
    return out

def validate(name, got, expect):
    errs = []
    if len(got) != 1: errs.append("%s: %d terminal events, want exactly 1" % (name, len(got)))
    for _, r in got:
        if r not in VOCAB: errs.append("%s: reason %r not in %s" % (name, r, VOCAB))
    if got != expect: errs.append("%s: got %s want %s" % (name, got, expect))
    return errs

def run(vectors, bug=None):
    errs = []
    for v in vectors:
        errs += validate(v["vector"], model(v["streams"], v["events"], bug, v.get("duration")), v["expect"])
    return errs

def main():
    vectors = json.load(open(os.path.join(HERE, "vectors.json")))
    if len(sys.argv) == 3 and sys.argv[1] == "--log":
        log = json.load(open(sys.argv[2])); errs = []
        for v in vectors:
            errs += validate(v["vector"], log.get(v["vector"], []), v["expect"])
        print("\n".join(errs) or "eos-vectors: all vectors PASS"); return 1 if errs else 0
    errs = run(vectors)
    if errs:
        print("\n".join(errs)); return 1
    for bug in ("early", "pause", "dup", "reason"):   # negative controls: each seeded bug must be caught
        if not run(vectors, bug):
            print("negative control %r NOT detected" % bug); return 1
        print("negative control %s: detected (fails as required)" % bug)
    print("eos-vectors: all vectors PASS"); return 0
sys.exit(main())

```

```text id=rf2
[
{
"vector": "video-only-eof",
"streams": [
"video"
],
"events": [
"videoPacket",
"videoPacket",
"videoEOF",
"trueEOF"
],
"expect": [
[
3,
"eof"
]
],
"duration": 10.0
},
{
"vector": "audio-only-eof",
"streams": [
"audio"
],
"events": [
"audioPacket",
"audioEOF",
"trueEOF"
],
"expect": [
[
2,
"eof"
]
],
"duration": 10.0
},
{
"vector": "joint-eof",
"streams": [
"video",
"audio"
],
"events": [
"videoPacket",
"audioPacket",
"videoEOF",
"audioEOF",
"trueEOF"
],
"expect": [
[
4,
"eof"
]
],
"duration": 10.0
},
{
"vector": "one-stream-eof-not-terminal",
"streams": [
"video",
"audio"
],
"events": [
"videoEOF",
"audioPacket",
"audioPacket",
"audioEOF",
"trueEOF"
],
"expect": [
[
4,
"eof"
]
],
"duration": 10.0
},
{
"vector": "late-packets-after-one-eof",
"streams": [
"video",
"audio"
],
"events": [
"videoEOF",
"videoPacket",
"audioPacket",
"audioEOF",
"videoPacket",
"trueEOF",
"audioPacket"
],
"expect": [
[
5,
"eof"
]
],
"duration": 10.0
},
{
"vector": "eof-during-pause",
"streams": [
"video",
"audio"
],
"events": [
"pause",
"videoEOF",
"audioEOF",
"resume",
"trueEOF"
],
"expect": [
[
4,
"eof"
]
],
"duration": 10.0
},
{
"vector": "trueEOF-while-paused-deferred-to-resume",
"streams": [
"video",
"audio"
],
"events": [
"videoEOF",
"audioEOF",
"pause",
"trueEOF",
"resume"
],
"expect": [
[
4,
"eof"
]
],
"duration": 10.0
},
{
"vector": "seek-before-eof-terminates",
"streams": [
"video",
"audio"
],
"events": [
"videoPacket",
"seek:10.0",
"videoEOF",
"audioEOF",
"trueEOF"
],
"expect": [
[
4,
"eof"
]
],
"duration": 10.0
},
{
"vector": "seek-after-eof-resets-streams",
"streams": [
"video"
],
"events": [
"videoEOF",
"seek:0.0",
"videoPacket",
"trueEOF",
"videoEOF",
"trueEOF"
],
"expect": [
[
5,
"eof"
]
],
"duration": 10.0
},
{
"vector": "source-ended",
"streams": [
"video",
"audio"
],
"events": [
"videoPacket",
"sourceEnded",
"audioPacket",
"trueEOF"
],
"expect": [
[
1,
"sourceEnded"
]
],
"duration": 10.0
},
{
"vector": "cancel-window-closed",
"streams": [
"video"
],
"events": [
"videoPacket",
"cancel:windowClosed",
"videoEOF",
"trueEOF"
],
"expect": [
[
1,
"windowClosed"
]
],
"duration": 10.0
},
{
"vector": "cancel-other",
"streams": [
"video"
],
"events": [
"videoPacket",
"cancel",
"trueEOF"
],
"expect": [
[
1,
"cancelled"
]
],
"duration": 10.0
},
{
"vector": "cancel-then-source-ended-single-terminal",
"streams": [
"video"
],
"events": [
"cancel",
"sourceEnded",
"cancel:windowClosed"
],
"expect": [
[
0,
"cancelled"
]
],
"duration": 10.0
},
{
"vector": "early-trueEOF-before-all-streams-ignored",
"streams": [
"video",
"audio"
],
"events": [
"videoEOF",
"trueEOF",
"audioEOF",
"trueEOF"
],
"expect": [
[
3,
"eof"
]
],
"duration": 10.0
},
{
"vector": "eof-exactly-at-seek-target",
"duration": 10.0,
"streams": [
"video",
"audio"
],
"events": [
"videoPacket",
"seek:10.0",
"trueEOF"
],
"expect": [
[
2,
"eof"
]
]
},
{
"vector": "seek-to-target-at-duration-then-explicit-eofs",
"duration": 10.0,
"streams": [
"video",
"audio"
],
"events": [
"seek:10.0",
"videoEOF",
"audioEOF",
"trueEOF",
"videoPacket"
],
"expect": [
[
3,
"eof"
]
]
},
{
"vector": "seek-just-before-target-not-eof",
"duration": 10.0,
"streams": [
"video",
"audio"
],
"events": [
"seek:9.5",
"trueEOF",
"videoPacket",
"videoEOF",
"audioEOF",
"trueEOF"
],
"expect": [
[
5,
"eof"
]
]
},
{
"vector": "eof-at-seek-target-while-paused-deferred",
"duration": 10.0,
"streams": [
"video"
],
"events": [
"pause",
"seek:10.0",
"trueEOF",
"resume"
],
"expect": [
[
3,
"eof"
]
]
}
]
```

```text id=actual_run_log
negative control early: detected (fails as required)
negative control pause: detected (fails as required)
negative control dup: detected (fails as required)
negative control reason: detected (fails as required)
eos-vectors: all vectors PASS
```
