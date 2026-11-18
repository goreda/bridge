# W-gdb-199c-in2tinct-11 - Recover from invalid first-frame anchors
state: OPEN / unclaimed
lab: in2tinct

## Product change
Reject nonfinite firstFrame anchors without consuming the generation. Normalize nonfinite seekCommitted anchors to absent, so a later finite first frame can bind. Preserve pause intent, stale-generation refusal, finite negative-anchor behavior and monotonic reads.

## Grounded gap and boundary
U2 playback observation/control prerequisites. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-11.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-in2tinct-11",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/PlayheadPosition.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "Reject nonfinite firstFrame anchors without consuming the generation. Normalize nonfinite seekCommitted anchors to absent, so a later finite first frame can bind. Preserve pause intent, stale-generation refusal, finite negative-anchor behavior and monotonic reads.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 playback observation/control prerequisites",
    "callee": "Sources/GorAVPlaybackCore/PlayheadPosition.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-11.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199c-in2tinct-11",
    "paths": [
      "Sources/GorAVPlaybackCore/PlayheadPosition.swift",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-11.py",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-11.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-11.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:13:46.037038+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "632d97fcf3d26864706fd7976c016a50c8ab0db9da55c8ed682a840461f6aaf3",
    "last_5_lines": [
      "FAIL seek invalid anchor permits recovery",
      "FAIL pause preserved",
      "semantic failures=5",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/PlayheadPosition.swift",
        "block": "source1",
        "sha256": "0376f99fffa86c3433093a40ecadecea461d934782b787b2f546b76d8716bb15",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-11.py",
        "block": "fixtures1",
        "sha256": "e03d358b27bdbfa400e7bd95e500b213ee6b06958a804bc46767d841bd95d8b0"
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-11.json",
        "block": "fixtures2",
        "sha256": "78ba78ac35a01d43425533a5ae49bab698f0ccded15e09939a45ce8f5e574170"
      }
    ],
    "receipt_sha256": "cf70b8bc2fa244bbc04745dca769bf1b82040b087488a2df6093a7269f1259c8"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
// Sources/GorAVPlaybackCore/PlayheadPosition.swift  (step 2; replaces step 1b file)
// G6: pure time-pos arithmetic and tracker. No clock reads, no I/O. Linux only / Mac NOT_RUN.

/// Pure position: anchor + elapsed play time, clamped. nil if anything is non-finite
/// or there is no anchor. Never publishes a non-finite value, never invents zero.
public func playheadSeconds(anchor: Double?, playedSeconds: Double, durationSeconds: Double?) -> Double? {
    guard let a = anchor, a.isFinite else { return nil }
    var e = playedSeconds
    if !e.isFinite || e < 0 { e = 0 }
    var t = a + e
    if !t.isFinite { return nil }
    if t < 0 { t = 0 }
    if let d = durationSeconds, d.isFinite, d > 0, t > d { t = d }
    return t
}

/// Tracks one session's playhead against ONE clock (the caller passes that clock's seconds to every
/// call; mixing clock sources breaks the arithmetic). Pause freezes the position (played time is
/// carried). The pause intent is remembered across a seek and before the first frame. A non-finite
/// clock sample (lost audio master) never publishes NaN: the run start is adopted from the next
/// finite sample.
public struct PlayheadTracker: Sendable {
    public private(set) var generation: Int = 0
    public private(set) var paused: Bool = false
    private var anchor: Double?
    private var carriedPlayed: Double = 0      // play time accumulated before the current run
    private var running = false                // playing with an anchor
    private var runStartClock: Double?         // nil while running means: adopt the next finite clock
    private var lastValue: Double?
    public init() {}

    /// First frame of generation `generation`, decided at media time `anchor`.
    /// Ignored (returns false, no state change) unless `generation` equals the tracker's
    /// current generation: a late first frame from before a seek, or from a generation the
    /// tracker has not been told about, never binds the wrong anchor. One per generation.
    /// Starts running only if not paused.
    @discardableResult
    public mutating func firstFrame(anchor: Double, clockNow: Double, generation: Int) -> Bool {
        guard generation == self.generation, self.anchor == nil else { return false }
        self.anchor = anchor
        carriedPlayed = 0
        running = !paused
        runStartClock = (running && clockNow.isFinite) ? clockNow : nil
        lastValue = nil
        return true
    }
    public mutating func pause(clockNow: Double) {
        paused = true
        guard running else { return }
        if let s = runStartClock {
            let d = clockNow - s
            if d.isFinite, d > 0 { carriedPlayed += d }
        }
        running = false
        runStartClock = nil
    }
    public mutating func resume(clockNow: Double) {
        paused = false
        guard anchor != nil, !running else { return }
        running = true
        runStartClock = clockNow.isFinite ? clockNow : nil
    }
    /// Committed seek: new generation. `anchor` nil = reads nil until the next
    /// firstFrame(generation: new). The pause state at seek entry is carried.
    public mutating func seekCommitted(anchor: Double?, clockNow: Double, wasPaused: Bool) {
        generation += 1
        paused = wasPaused
        self.anchor = anchor
        carriedPlayed = 0
        running = anchor != nil && !wasPaused
        runStartClock = (running && clockNow.isFinite) ? clockNow : nil
        lastValue = nil
    }
    /// nil before the first frame. Monotonic within a generation; duration cap wins.
    public mutating func read(clockNow: Double, durationSeconds: Double?) -> Double? {
        if running, runStartClock == nil, clockNow.isFinite { runStartClock = clockNow }
        var played = carriedPlayed
        if running, let s = runStartClock {
            let d = clockNow - s
            if d.isFinite, d > 0 { played += d }
        }
        guard let v = playheadSeconds(anchor: anchor, playedSeconds: played, durationSeconds: durationSeconds) else { return nil }
        var out = v
        if let l = lastValue, v < l { out = l }
        if let d = durationSeconds, d.isFinite, d > 0, out > d { out = d }
        lastValue = out
        return out
    }
}

```

```python id=fixtures1
from pathlib import Path
import os,subprocess,tempfile,sys,json,resource,shutil
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[3]
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
    "Sources/GorAVPlaybackCore/PlayheadPosition.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nvar p = PlayheadTracker()\ncheck(!p.firstFrame(anchor: .nan, clockNow: 0, generation: 0), \"NaN first frame refused\")\ncheck(p.firstFrame(anchor: 2, clockNow: 0, generation: 0), \"finite recovery binds\")\ncheck(p.read(clockNow: 1, durationSeconds: nil) == 3, \"recovered position\")\np.seekCommitted(anchor: .infinity, clockNow: 2, wasPaused: true)\ncheck(p.firstFrame(anchor: 4, clockNow: 3, generation: 1), \"seek invalid anchor permits recovery\")\ncheck(p.paused && p.read(clockNow: 4, durationSeconds: nil) == 4, \"pause preserved\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL NaN first frame refused
FAIL finite recovery binds
FAIL recovered position
FAIL seek invalid anchor permits recovery
FAIL pause preserved
semantic failures=5



```

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
