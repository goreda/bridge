# W-gdb-199c-in2tinct-14 - Finite time-position rate configuration
state: OPEN / unclaimed
lab: in2tinct

## Product change
For nonfinite maxPerSecond use the documented default 4Hz rather than silently disabling rate limiting. Preserve finite positive rates and existing finite nonpositive unlimited behavior. Document this nonfinite policy in the initializer.

## Grounded gap and boundary
U2 playback observation/control prerequisites. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-14.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-in2tinct-14",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/PlayheadObservers.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "For nonfinite maxPerSecond use the documented default 4Hz rather than silently disabling rate limiting. Preserve finite positive rates and existing finite nonpositive unlimited behavior. Document this nonfinite policy in the initializer.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 playback observation/control prerequisites",
    "callee": "Sources/GorAVPlaybackCore/PlayheadObservers.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-14.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199c-in2tinct-14",
    "paths": [
      "Sources/GorAVPlaybackCore/PlayheadObservers.swift",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-14.py",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-14.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-14.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:13:47.311255+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "0e784a8a6a7a64a0547019f91da7859f70989105564248a70b266e101648d191",
    "last_5_lines": [
      "FAIL default cadence recovers",
      "PASS finite rate preserved",
      "semantic failures=6",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/PlayheadObservers.swift",
        "block": "source1",
        "sha256": "5d8c618cb6449405d528a9d9d1744d4d52ff291625ec5e0206791c93ed63ea49",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-14.py",
        "block": "fixtures1",
        "sha256": "e03d358b27bdbfa400e7bd95e500b213ee6b06958a804bc46767d841bd95d8b0"
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-14.json",
        "block": "fixtures2",
        "sha256": "a0553ab05dc960338f78f99bbd5991ed2393ce9192b5651b15a0627538fc2ca6"
      }
    ],
    "receipt_sha256": "b97132f0bf97f0ab8a702c64cf690f5829e73ade29d0baff51d76f7b31e68fc5"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
// Sources/GorAVPlaybackCore/PlayheadObservers.swift  (step 2, new)
// G6: pure helpers behind the observers. Linux only / Mac NOT_RUN.

/// Container duration from FFmpeg AVFormatContext.duration (AV_TIME_BASE ticks,
/// microseconds). nil when unknown (AV_NOPTS_VALUE passed as nil by the caller),
/// zero, negative, or not representable. Never returns 0 for unknown.
public func containerDurationSeconds(ticks: Int64?, ticksPerSecond: Int64 = 1_000_000) -> Double? {
    guard let t = ticks, t > 0, ticksPerSecond > 0 else { return nil }
    let s = Double(t) / Double(ticksPerSecond)
    return s.isFinite && s > 0 ? s : nil
}

/// timePos event gate: at most `maxPerSecond` events, only when the value changed.
public struct TimePosGate: Sendable {
    private let minInterval: Double
    private var lastEmitClock: Double?
    private var lastValue: Double?
    public init(maxPerSecond: Double = 4) {
        minInterval = maxPerSecond > 0 ? 1.0 / maxPerSecond : 0
    }
    /// Returns the value to emit, or nil to stay quiet. A generation change
    /// (seek) always emits the first value of the new generation immediately and
    /// resets the clock reference. Non-finite or backwards clockNow never emits.
    public mutating func offer(_ value: Double?, clockNow: Double, newGeneration: Bool = false) -> Double? {
        guard let v = value, v.isFinite, clockNow.isFinite else { return nil }
        if newGeneration { lastEmitClock = nil; lastValue = nil }
        if let l = lastValue, l == v { return nil }
        // A clock sample earlier than the last emit is not trusted: stay quiet
        // (never bypass the rate limit) until the clock catches up.
        if let c = lastEmitClock, clockNow < c || clockNow - c < minInterval { return nil }
        lastEmitClock = clockNow
        lastValue = v
        return v
    }
}

/// volumeChanged gate: one event per actual change, never for non-finite input.
public struct VolumeChangeGate: Sendable {
    private var last: Float?
    public init() {}
    public mutating func offer(_ v: Float) -> Float? {
        guard v.isFinite else { return nil }
        if let l = last, l == v { return nil }
        last = v
        return v
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
    "Sources/GorAVPlaybackCore/PlayheadObservers.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nfor rate in [Double.nan, Double.infinity, -Double.infinity] {\n var gate=TimePosGate(maxPerSecond: rate)\n check(gate.offer(1,clockNow: 0) == 1,\"first event\")\n check(gate.offer(2,clockNow: 0.01) == nil,\"nonfinite config does not bypass limit\")\n check(gate.offer(2,clockNow: 0.25) == 2,\"default cadence recovers\")\n}\nvar fast=TimePosGate(maxPerSecond: 10)\ncheck(fast.offer(1,clockNow: 0) == 1 && fast.offer(2,clockNow: 0.1) == 2,\"finite rate preserved\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
PASS first event
FAIL nonfinite config does not bypass limit
FAIL default cadence recovers
PASS first event
FAIL nonfinite config does not bypass limit
FAIL default cadence recovers
PASS first event
FAIL nonfinite config does not bypass limit
FAIL default cadence recovers
PASS finite rate preserved
semantic failures=6



```

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
