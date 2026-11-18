# W-gdb-199c-1nstinct-13 - Fence invalid blink episode samples
state: OPEN / unclaimed
lab: 1nstinct

## Product change
BlinkEpisodeTracker.feed must ignore any nonfinite timestamp, backwards timestamp relative to the last accepted sample (including unusable samples), or nonfinite supplied ratio without mutating episode or cadence state. Equal timestamps keep existing behavior. Treat finite nil ratio/closing using the existing unusable-sample behavior. Add a private last-accepted timestamp if needed and clear it via reset. Preserve all provisional thresholds and recognizer classification. This is input/state safety, not measured camera accuracy or new control wiring.

## Grounded gap and boundary
U2 camera/head/blink input prerequisite; retained S2 Camera station. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-13.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery. All new test paths start under archive/gor/Tests. This packet does not touch GorCore; preserve any later BuildID/launch-identity return when rebasing. If a later rebase requires a GorCore edit, stop and obtain a refreshed source lease instead of silently changing launch identity.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-13",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Camera/BlinkEpisodes.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "BlinkEpisodeTracker.feed must ignore any nonfinite timestamp, backwards timestamp relative to the last accepted sample (including unusable samples), or nonfinite supplied ratio without mutating episode or cadence state. Equal timestamps keep existing behavior. Treat finite nil ratio/closing using the existing unusable-sample behavior. Add a private last-accepted timestamp if needed and clear it via reset. Preserve all provisional thresholds and recognizer classification. This is input/state safety, not measured camera accuracy or new control wiring.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 camera/head/blink input prerequisite; retained S2 Camera station",
    "callee": "archive/gor/Sources/gor/Camera/BlinkEpisodes.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-13.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-13",
    "paths": [
      "archive/gor/Sources/gor/Camera/BlinkEpisodes.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-13.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-13.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-13.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:21:53.644037+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "ad5cb9d8649564314b7c1e13a08e7afadd01bef5720de2b262b17752feebfc50",
    "last_5_lines": [
      "FAIL backwards reopen ignored",
      "FAIL valid reopen retains original episode",
      "semantic failures=7",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Camera/BlinkEpisodes.swift",
        "block": "source1",
        "sha256": "bdd34e9c75ee2f9da7b835e22a606c3c39f7874a12b437fb58b7d9a2e8a8ea0f",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-13.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-13.json",
        "block": "fixtures2",
        "sha256": "014750592a02a9662b5e79ad3f5f12c13ac9f4b09423b75d317afe014799f30a"
      }
    ],
    "receipt_sha256": "53d228913dee59a1b8dc05817cd892b010c5fa22dbf7f8465e17e6fd85e690e8"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

// MARK: - Blink episode bookkeeping (pure, no Vision/AppKit/clock)

struct BlinkEpisodeTracker {
    struct Event {
        let end: String            // "reopened" or "abandoned" (closed longer than abandonS)
        let t0: Double
        let t1: Double?            // time of the reopening sample; nil when abandoned
        let durS: Double           // first closed sample -> reopening sample (or last sample when abandoned)
        let closedSpanS: Double    // first -> last closed sample
        let nClosed: Int           // closed samples inside the episode
        let minRatio: Double
        let maxGapS: Double        // largest gap between consecutive USABLE samples, from the one before the first closed sample to the reopening one
        let unusableInside: Int    // unusable samples (no eyes / yaw over limit) seen while the episode was open
        let tBefore: Double?       // time of the last usable (open) sample before the first closed one; nil if none
        let baselineYoung: Bool    // fewer than youngBaseline usable samples had been seen before the episode started
        /// Duration alone: reopen within 0.10...0.40 s of the first closed sample (literature range for a spontaneous blink).
        let inBlinkRange: Bool
        /// The cadence could see the shape: enough closed samples, no gap above maxGapS, no unusable sample inside.
        var sampledWell: Bool { nClosed >= BlinkEpisodeTracker.minClosedSamples && maxGapS <= BlinkEpisodeTracker.maxGapLimitS && unusableInside == 0 }
        /// Quality only, never a detection verdict: duration in range AND sampled well AND baseline not young.
        var qualityOK: Bool { end == "reopened" && inBlinkRange && sampledWell && !baselineYoung }
    }

    static let abandonS = 0.6          // PROVISIONAL
    static let maxGapLimitS = 0.05     // PROVISIONAL: half of the shortest 100 ms blink
    static let minClosedSamples = 3    // PROVISIONAL
    static let youngBaseline = 10      // PROVISIONAL: usable samples before the open baseline counts as established

    private var usableSeen = 0
    private var prevUsableT: Double? = nil
    private var t0: Double? = nil
    private var lastClosedT = 0.0
    private var n = 0
    private var minR = 1.0
    private var maxGap = 0.0
    private var unusable = 0
    private var youngAtStart = true
    private var abandoned = false
    private var tBeforeStart: Double? = nil

    mutating func reset() { self = BlinkEpisodeTracker() }

    /// Feed one sample. `ratio` and `closing` are nil together when the sample is unusable. Returns whether a new
    /// episode started on this sample and the finished event, if this sample ended one.
    mutating func feed(t: Double, ratio: Double?, closing: Bool?) -> (started: Bool, event: Event?) {
        guard let r = ratio, let c = closing else {
            if t0 != nil { unusable += 1 }
            return (false, nil)
        }
        let gap = prevUsableT.map { t - $0 } ?? 0
        let prevT = prevUsableT
        prevUsableT = t
        usableSeen += 1
        if c {
            if abandoned { return (false, nil) }          // long closure: wait for a reopen
            var started = false
            if t0 == nil {
                t0 = t; tBeforeStart = prevT; n = 0; minR = r; maxGap = gap; unusable = 0; youngAtStart = (usableSeen - 1) < Self.youngBaseline; started = true
            }
            n += 1; minR = min(minR, r); lastClosedT = t; maxGap = max(maxGap, gap)
            if let s = t0, t - s > Self.abandonS {
                let e = makeEvent(end: "abandoned", t1: nil, now: t)
                t0 = nil; abandoned = true
                return (started, e)
            }
            return (started, nil)
        }
        if abandoned { abandoned = false; return (false, nil) }
        guard let s = t0 else { return (false, nil) }
        maxGap = max(maxGap, gap)
        let e = makeEvent(end: "reopened", t1: t, now: t)
        _ = s; t0 = nil
        return (false, e)
    }

    private func makeEvent(end: String, t1: Double?, now: Double) -> Event {
        let s = t0 ?? now
        let dur = (t1 ?? now) - s
        return Event(end: end, t0: s, t1: t1, durS: dur, closedSpanS: lastClosedT - s, nClosed: n, minRatio: minR,
                     maxGapS: maxGap, unusableInside: unusable, tBefore: tBeforeStart, baselineYoung: youngAtStart,
                     inBlinkRange: dur >= 0.10 && dur <= 0.40)
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Blink recognizer (pure). Turns one finished episode into a detection, aware of the sampling cadence. It binds no
// command. Every number is either the literature blink range already used above or a PROVISIONAL hypothesis; none is
// validated on a real recording, so a detection here is "the provisional rule fired", not a measured accuracy.
struct BlinkDetection {
    enum Kind: String {
        case confirmed = "confirmed"   // >= 2 closed samples, nothing unusable inside, baseline established, duration compatible
        case possible = "possible"     // compatible duration but a single closed sample, an unusable sample inside or a young baseline
        case held = "held"             // eye stayed closed past the blink range (>= 2 closed samples): an eye closure, not a blink
    }
    let kind: Kind
    let t0: Double
    let durMinS: Double                // conservative bound: point samples alone prove no continuous duration
    let durMaxS: Double                // longest it can have been (previous open sample -> reopening sample)
    let nClosed: Int
    let minRatio: Double
}

enum BlinkRecognizer {
    static let blinkMinS = 0.10        // literature range, same as BlinkEpisodeTracker.Event.inBlinkRange
    static let blinkMaxS = 0.40
    static let maxConfirmedGapS = 0.15 // provisional upper bound; sparse episodes remain possible, never confirmed
    static let minClosedForConfirmed = 2   // PROVISIONAL: one dipping sample cannot be told from landmark jitter

    /// Cadence-aware PROVISIONAL rule. Closed-span continuity is a heuristic, not a physical lower bound:
    /// an unseen reopening may occur between point samples. durMinS remains zero. The enum name
    /// confirmed means only that this stricter heuristic fired, never validated camera ground truth.
    static func classify(_ e: BlinkEpisodeTracker.Event) -> BlinkDetection? {
        if e.end == "abandoned" {
            guard e.nClosed >= minClosedForConfirmed, e.unusableInside == 0, !e.baselineYoung, e.maxGapS <= maxConfirmedGapS else { return nil }
            return BlinkDetection(kind: .held, t0: e.t0, durMinS: 0, durMaxS: e.durS, nClosed: e.nClosed, minRatio: e.minRatio)
        }
        guard let t1 = e.t1 else { return nil }
        let dMin = e.closedSpanS
        let dMax = e.tBefore.map { t1 - $0 } ?? e.durS
        guard dMin <= blinkMaxS, dMax >= blinkMinS else { return nil }
        let sure = e.nClosed >= minClosedForConfirmed && e.unusableInside == 0 && !e.baselineYoung
            && e.maxGapS <= maxConfirmedGapS && dMin >= blinkMinS && dMax <= blinkMaxS
        return BlinkDetection(kind: sure ? .confirmed : .possible, t0: e.t0, durMinS: 0, durMaxS: dMax, nClosed: e.nClosed, minRatio: e.minRatio)
    }
}


```

```python id=fixtures1
from pathlib import Path
import os,subprocess,tempfile,sys,json,resource,shutil
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5]
CFG=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:
 print('NOT_RUN: Swift compiler unavailable'); sys.exit(77)
with tempfile.TemporaryDirectory() as d:
 d=Path(d); main=d/'main.swift'; main.write_text(CFG['test_source']); exe=d/'test'
 args=[swift]+[str(ROOT/p) for p in CFG['sources']]+[str(main),'-o',str(exe)]
 c=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('compile_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 if c.returncode: sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=15)
 print('semantic_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "sources": [
    "archive/gor/Sources/gor/Camera/BlinkEpisodes.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nvar tracker=BlinkEpisodeTracker()\ncheck(!tracker.feed(t: .nan,ratio: 0.1,closing: true).started,\"NaN timestamp ignored\")\ncheck(tracker.feed(t: 1,ratio: 0.1,closing: true).started,\"finite sample can begin after rejected sample\")\ncheck(tracker.feed(t: 1.25,ratio: 1,closing: false).event?.durS == 0.25,\"episode duration unaffected\")\ntracker.reset()\ncheck(!tracker.feed(t: 1,ratio: .nan,closing: true).started,\"NaN ratio ignored\")\ncheck(tracker.feed(t: 2,ratio: 0.1,closing: true).started,\"finite recovery after ratio rejection\")\ntracker.reset()\ncheck(tracker.feed(t: 2,ratio: 0.1,closing: true).started,\"independent chronology episode\")\ncheck(tracker.feed(t: 1.5,ratio: 1,closing: false).event == nil,\"backwards reopen ignored\")\ncheck(tracker.feed(t: 2.25,ratio: 1,closing: false).event?.durS == 0.25,\"valid reopen retains original episode\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL NaN timestamp ignored
FAIL finite sample can begin after rejected sample
FAIL episode duration unaffected
FAIL NaN ratio ignored
FAIL finite recovery after ratio rejection
PASS independent chronology episode
FAIL backwards reopen ignored
FAIL valid reopen retains original episode
semantic failures=7



```

Claim lease: 2h under existing earliest-claim workflow, refreshed only by verified progress. OPEN/unclaimed. Starter RED is not acceptance; own compiler rerun NOT_RUN.
