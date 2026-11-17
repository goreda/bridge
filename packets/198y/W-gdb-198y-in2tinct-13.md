# W-gdb-198y-in2tinct-13
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVFFmpegAdapter/FrameObservation.swift in shipping-path engine station GorAVFFmpegAdapter. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-13.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-13",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVFFmpegAdapter/FrameObservation.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVFFmpegAdapter/FrameObservation.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: PlaneObservation, FrameObservation, ObservationRefusal, CustomIOLogicalTeardown, SessionTraceKind, SessionTraceRecord, SessionTraceSnapshot",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-13.py",
    "callee": "Sources/GorAVFFmpegAdapter/FrameObservation.swift owning station GorAVFFmpegAdapter"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-13.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-13.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-13.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:19.324865+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVFFmpegAdapter/FrameObservation.swift",
        "block": "source1",
        "sha256": "be334edb495a9558371d20bde9b301a35071bb43c1e2521dcc0ce5791ff3fa8b"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-13.py",
        "block": "fixtures1",
        "sha256": "73927eb42fccdc5306153898db8f7053362df83a3b29eb4bd7fe974772fb4c5b"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "c98344f04583c328458d9036aaa117ddb8a0474f34a6ec742b8c5d1b0ac2a358",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-13: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "f0a10eb6253d618a8a31d5ff170f6c1b19b96d9e84e6087026860c427a18e3ed"
  }
}
```

```swift id=source1
// AUTHORED_NEW source-only observation values, NOT_COMPILED / NOT_RUN.
import Foundation

public struct PlaneObservation: Equatable, Sendable {
    public let index: Int
    public let rowBytes: Int
    public let rows: Int
    public let stride: Int
    public let readableExtent: Int
    public let containingBufferExtent: UInt
    public let planeOffset: UInt
    public let coverageVerified: Bool
}
public struct FrameObservation: Equatable, Sendable {
    public let sessionEpoch: UInt64
    public let handle: UInt64
    public let selectedStreamIndex: Int32
    public let pixelFormat: String
    public let width: Int
    public let height: Int
    public let pts: Int64?
    public let duration: Int64
    /// v4.3 (R2Y trunk seam, additive): the PRODUCING stream's time_base,
    /// captured at open from AVStream.time_base and validated num>0/den>0
    /// (typed open refusal otherwise) - never inferred from pts. seconds =
    /// pts * num / den. L4 binds its reference to this exact rational.
    public let ptsTimeBaseNum: Int32
    public let ptsTimeBaseDen: Int32
    public let planes: [PlaneObservation]
}
public enum ObservationRefusal: Error, Equatable, Sendable {
    case foreignOrStaleSession
    case releasedHandle
    case unavailableHandle
    case invalidLease
    case unavailableMetadata
    case unboundedPlane
    case traceUnavailable
}
/// Logical invocation evidence only. NOT proof of native free, refcount or leaks.
/// absent = no fully initialized custom IO owner at this cleanup site.
/// called = close invoked but return not yet observed; completed = close returned.
public enum CustomIOLogicalTeardown: String, Equatable, Sendable {
    case absent, called, completed
}
public enum SessionTraceKind: String, Sendable {
    case selectedStream, demuxReadEOF, nilFlushSendResult, receiveEOF
    case terminalEOF, terminalInterrupted, terminalFailed, closed
    case customIOAbsent, customIOCloseCalled, customIOCloseCompleted
}
public struct SessionTraceRecord: Equatable, Sendable {
    public let sequence: UInt64
    public let kind: SessionTraceKind
    public let providerResult: Int32?
    public let selectedStreamIndex: Int32
}
public struct SessionTraceSnapshot: Equatable, Sendable {
    public let sessionEpoch: UInt64
    public let capacity: Int
    public let overflowed: Bool
    public let customIOLogicalTeardown: CustomIOLogicalTeardown
    public let records: [SessionTraceRecord]
    // No success assertion. Any consumer must refuse success on overflow.
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVFFmpegAdapter/FrameObservation.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='be334edb495a9558371d20bde9b301a35071bb43c1e2521dcc0ce5791ff3fa8b', 'pinned source changed: rebase and review, never bless silently'
for token in ['PlaneObservation', 'FrameObservation', 'ObservationRefusal', 'CustomIOLogicalTeardown', 'SessionTraceKind', 'SessionTraceRecord', 'SessionTraceSnapshot']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='be334edb495a9558371d20bde9b301a35071bb43c1e2521dcc0ce5791ff3fa8b'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-13: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-13: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
