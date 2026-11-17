# W-gdb-198y-in2tinct-29
state: OPEN / unclaimed
lab: in2tinct

Build a new source-contract false-positive regression test for the exact file, independently from the prior fragment tests. Preserve source-pin evidence separately. Mask Swift comments and string literals before named declaration assertions. Add at least two real declaration signature/value boundary assertions and three mutation controls including comment-only decoy, string-only decoy, and renamed/removed declaration. Do not allow a comment/string containing an expected fragment to satisfy its declaration. Use explicit failures under python3 -O and execute normal/optimized positive plus on-disk external negative/restore controls. This remains source characterization, never Swift semantics or runtime.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-29.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-29",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/AudioMasterScheduler/SeekQueueCoordinator.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at Tests/Architecture/198y/W-gdb-198y-in2tinct-29.py checks Sources/AudioMasterScheduler/SeekQueueCoordinator.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: SeekQueueCoordinator, decide, SeekQueueError",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-29.py",
    "callee": "Sources/AudioMasterScheduler/SeekQueueCoordinator.swift owning station AudioMasterScheduler"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-29.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-29.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-29.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.350491+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/AudioMasterScheduler/SeekQueueCoordinator.swift",
        "block": "source1",
        "sha256": "fced02bd5c04f511aa29836684624ce9ba2c938f5e09d1a2548f833b6aff9f10"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-29.py",
        "block": "fixtures1",
        "sha256": "001a1c240088cc18bfb0ef9e4b19657a15cc114e5256541241a145f1dff7bce8"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "1db33508281b8a08e315a9106134ebf116c6b8bdb426f8761efd444a03663b23",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-29: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "bfe787dfa6a73940ba26db274466e60f4cc29805cd17b9e605b4756715072a46"
  }
}
```

```swift id=source1
import Foundation

/// Serialized owner of the presentation queue and enqueue-time tokens.
/// A seek invalidates the prior generation before the provider flush.
/// Callers supply their real decoder/packet-queue flush, not a clock-only reset.
public struct SeekQueueCoordinator: Sendable {
    public private(set) var scheduler = EnqueueGenerationAdapter()
    public private(set) var pending: [EnqueuedVideoFrame] = []
    public init() {}
    public mutating func reset(audioTime: Double, hostTime: Double) {
        pending.removeAll()
        scheduler.reset(audioTime: audioTime, hostTime: hostTime)
    }
    public mutating func enqueue(videoPTS: Double) -> EnqueuedVideoFrame {
        let token = scheduler.enqueue(videoPTS: videoPTS)
        pending.append(token)
        return token
    }
    public mutating func updateAudio(mediaTime: Double, hostTime: Double) {
        scheduler.updateAudio(mediaTime: mediaTime, hostTime: hostTime)
    }
    public func decide(frame: EnqueuedVideoFrame, hostTime: Double) -> VideoDecision {
        scheduler.decide(frame: frame, hostTime: hostTime)
    }
    public mutating func seek(to seconds: Double, hostTime: Double,
                              flushDecoderAndPackets: () throws -> Void) throws {
        // Remove queued decoded frames even when provider flush fails.
        guard seconds.isFinite, seconds >= 0, hostTime.isFinite else {
            throw SeekQueueError.invalidTarget
        }
        pending.removeAll()
        // Invalidate tokens before calling the provider: failed seek cannot make
        // pre-seek frames current again. No frame receives a replacement token.
        scheduler.seek(to: seconds, hostTime: hostTime)
        try flushDecoderAndPackets()
    }
}

public enum SeekQueueError: Error { case invalidTarget }

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/AudioMasterScheduler/SeekQueueCoordinator.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='fced02bd5c04f511aa29836684624ce9ba2c938f5e09d1a2548f833b6aff9f10', 'pinned source changed: rebase and review, never bless silently'
for token in ['SeekQueueCoordinator', 'decide', 'SeekQueueError']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='fced02bd5c04f511aa29836684624ce9ba2c938f5e09d1a2548f833b6aff9f10'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-29: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-29: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
