# W-gdb-198y-in2tinct-33
state: OPEN / unclaimed
lab: in2tinct

Build a new source-contract false-positive regression test for the exact file, independently from the prior fragment tests. Preserve source-pin evidence separately. Mask Swift comments and string literals before named declaration assertions. Add at least two real declaration signature/value boundary assertions and three mutation controls including comment-only decoy, string-only decoy, and renamed/removed declaration. Do not allow a comment/string containing an expected fragment to satisfy its declaration. Use explicit failures under python3 -O and execute normal/optimized positive plus on-disk external negative/restore controls. This remains source characterization, never Swift semantics or runtime.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-33.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-33",
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
    "signatures": "Linux stdlib test at Tests/Architecture/198y/W-gdb-198y-in2tinct-33.py checks Sources/GorAVFFmpegAdapter/FrameObservation.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: PlaneObservation, FrameObservation, ObservationRefusal, CustomIOLogicalTeardown, SessionTraceKind, SessionTraceRecord, SessionTraceSnapshot",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-33.py",
    "callee": "Sources/GorAVFFmpegAdapter/FrameObservation.swift owning station GorAVFFmpegAdapter"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-33.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-33.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-33.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.423977+00:00",
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
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-33.py",
        "block": "fixtures1",
        "sha256": "1db1193d57d29b5c4498794baf69daf2622c1ad8d19203f7aab2d2c3ac4dfd47"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "7fc052150038d056010c5a08f7c58a394b0284231300a6c25865ebc45552a7e4",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-33: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "d34077232d020dced98f6acfb07642b15ae1f512ad7698ccbb0ad6550c2b9a21"
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
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-33: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-33: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
