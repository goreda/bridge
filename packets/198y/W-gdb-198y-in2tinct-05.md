# W-gdb-198y-in2tinct-05
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift in shipping-path engine station GorAVPlaybackCore. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-05.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-05",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: ReadinessAnchorSession",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-05.py",
    "callee": "Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-05.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-05.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-05.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:17.116139+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift",
        "block": "source1",
        "sha256": "84ab7c80c17d441405756e2fe7d4ed61d54a7c9219c496c3fcf61a9b249e2db3"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-05.py",
        "block": "fixtures1",
        "sha256": "39853aba12e82b33d8bca9e05bd7fac8896445d1dc100bc2eeed3f82dc85ba82"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "ebc18f4f3d43041117ef687c4ca4fa53b3d66bc50c2051fe0a5f32ebabfebb86",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-05: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "dc810fb9a5cac49fbcb0b3934118b613b672f68f90dc8676c0369d8ef9efd8be"
  }
}
```

```swift id=source1
import Foundation

/// 189k PERMANENT ENGINE RULE (owner block 189k, 2026-11-07 01:50 +03):
/// the audio clock starts only after frame 0 is decoded AND presented;
/// after every seek: flush the queue, present the first frame, then
/// restart the clock. Frame 0 of each generation is the readiness anchor
/// and never receives a scheduler decision. maxLate and all downstream
/// asserts are unchanged by this type; it owns ONLY the ordering state so
/// no harness or shell can reimplement (or skip) the rule.
///
/// The session is deliberately small and platform-neutral (Linux-testable):
/// callers perform the real decode/present/clock work and move the session
/// through its typed gates. A clock start requested before the anchor is
/// presented is REFUSED (typed), never silently permitted.
public struct ReadinessAnchorSession: Sendable, Equatable {
    /// Seek fence: bumped on every seek; frames from older generations are stale.
    public private(set) var generation: UInt64 = 0
    /// True while the current generation's first frame has not been both
    /// decoded and presented. An anchor-pending frame takes NO scheduler
    /// decision: it IS the timeline zero.
    public private(set) var anchorPending = true
    /// True after requestClockStart() succeeded for the current generation.
    public private(set) var clockRunning = false
    public init() {}

    /// Start of playback (generation 0).
    public mutating func begin() {
        generation = 0; anchorPending = true; clockRunning = false
    }

    /// The readiness anchor frame for the current generation was decoded
    /// AND presented. Idempotent within a generation.
    public mutating func anchorPresentedNow() { anchorPending = false }

    /// Typed clock-start gate: succeeds only after the anchor is presented.
    /// Returns false (refusal) when the anchor is still pending.
    public mutating func requestClockStart() -> Bool {
        guard !anchorPending else { return false }
        clockRunning = true
        return true
    }

    /// Seek: the queue is flushed by the caller; the clock stops; the first
    /// frame of the new generation is again a readiness anchor that must be
    /// presented before the clock restarts. Returns the new generation.
    @discardableResult
    public mutating func seek() -> UInt64 {
        generation &+= 1
        anchorPending = true
        clockRunning = false
        return generation
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='84ab7c80c17d441405756e2fe7d4ed61d54a7c9219c496c3fcf61a9b249e2db3', 'pinned source changed: rebase and review, never bless silently'
for token in ['ReadinessAnchorSession']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='84ab7c80c17d441405756e2fe7d4ed61d54a7c9219c496c3fcf61a9b249e2db3'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-05: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-05: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
