# W-gdb-198y-in2tinct-09
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/AudioMasterScheduler/SeekQueueCoordinator.swift in shipping-path engine station AudioMasterScheduler. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-09.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-09",
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
    "signatures": "Source-only characterization script reads Sources/AudioMasterScheduler/SeekQueueCoordinator.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: SeekQueueCoordinator, decide, SeekQueueError",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-09.py",
    "callee": "Sources/AudioMasterScheduler/SeekQueueCoordinator.swift owning station AudioMasterScheduler"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-09.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-09.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-09.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.775626+00:00",
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
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-09.py",
        "block": "fixtures1",
        "sha256": "e5f5e3a519d1a3ced5cc7b4e5eef88d50b08b7185e4679564b0b73a34abd0d61"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "0835eec0aeb22a6d2c0a6207a0eeab4150b949f79ba2b973d44cd291530bdb31",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-09: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "d6c3a63652fce5125112750fbc0469a6d2ea615b7b93330f54cc3d663967e490"
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
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-09: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-09: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
