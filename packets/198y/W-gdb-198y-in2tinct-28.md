# W-gdb-198y-in2tinct-28
state: OPEN / unclaimed
lab: in2tinct

Build a new source-contract false-positive regression test for the exact file, independently from the prior fragment tests. Preserve source-pin evidence separately. Mask Swift comments and string literals before named declaration assertions. Add at least two real declaration signature/value boundary assertions and three mutation controls including comment-only decoy, string-only decoy, and renamed/removed declaration. Do not allow a comment/string containing an expected fragment to satisfy its declaration. Use explicit failures under python3 -O and execute normal/optimized positive plus on-disk external negative/restore controls. This remains source characterization, never Swift semantics or runtime.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-28.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-28",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVFFmpegAdapter/L3Admission.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at Tests/Architecture/198y/W-gdb-198y-in2tinct-28.py checks Sources/GorAVFFmpegAdapter/L3Admission.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: L3PixelClass, L3PixelPolicy, classification",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-28.py",
    "callee": "Sources/GorAVFFmpegAdapter/L3Admission.swift owning station GorAVFFmpegAdapter"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-28.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-28.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-28.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.332285+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVFFmpegAdapter/L3Admission.swift",
        "block": "source1",
        "sha256": "a99be5ffe4480da5ebdf1565c4baf65038fc35c90f7fe5dcf46b93efb107f2b6"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-28.py",
        "block": "fixtures1",
        "sha256": "4f950e1f1f5b790bce70ff3675e4293785c5470c4fb27273b136cd1103208ccc"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "9018771684b08366fd640d0aae6e72eeecfcd9ef938f70759c45516c7d8eeccd",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-28: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "f3764e1e0809935520170c485f108c53300f06bcbecdbb13f6adc2b645ad6e18"
  }
}
```

```swift id=source1
// AUTHORED NEW (2026-10-25, L3 formats/hardware-decode lane).
// L3 codec/container admission policy and hardware-attempt policy.
// d4 close-out (queue 36): the L3AdmissionProfile forwarding layer is retired;
// admission sets and policy live only in GorAVCore AdmissionTable.
import Foundation
import CFFmpeg
import GorAVCore

/// Software pixel-format classification at retain time. Direct formats flow
/// through the trunk's bounded plane allowlist unchanged; convertible formats
/// (the 10-bit family the L3 codecs actually emit) are converted to yuv420p
/// 8-bit first; anything else is an honest refusal, no fallback.
/// Blocker 1 rework: 10-bit frames are PRESERVED ORIGINALS with their own
/// bounded lease and HDR side-data descriptor; the 8-bit SDR conversion is a
/// derived, explicitly requested product (framePlaneCopyDerived), never the
/// retained truth.
public enum L3PixelClass: Equatable, Sendable {
    case direct             // 8-bit allowlist, trunk behavior unchanged
    case preservedOriginal  // 10-bit family: retained with side data, no reduction
    case refuse
}

public enum L3PixelPolicy {
    public static func classification(_ format: Int32) -> L3PixelClass {
        switch format {
        case AV_PIX_FMT_YUV420P.rawValue, AV_PIX_FMT_YUVJ420P.rawValue,
             AV_PIX_FMT_YUV422P.rawValue, AV_PIX_FMT_YUV444P.rawValue,
             AV_PIX_FMT_NV12.rawValue, AV_PIX_FMT_RGB24.rawValue:
            return .direct
        case AV_PIX_FMT_YUV420P10LE.rawValue, AV_PIX_FMT_P010LE.rawValue:
            return .preservedOriginal
        default:
            return .refuse
        }
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVFFmpegAdapter/L3Admission.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='a99be5ffe4480da5ebdf1565c4baf65038fc35c90f7fe5dcf46b93efb107f2b6', 'pinned source changed: rebase and review, never bless silently'
for token in ['L3PixelClass', 'L3PixelPolicy', 'classification']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='a99be5ffe4480da5ebdf1565c4baf65038fc35c90f7fe5dcf46b93efb107f2b6'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-28: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-28: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
