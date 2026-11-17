# W-gdb-198y-in2tinct-08
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVFFmpegAdapter/L3Admission.swift in shipping-path engine station GorAVFFmpegAdapter. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-08.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-08",
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
    "signatures": "Source-only characterization script reads Sources/GorAVFFmpegAdapter/L3Admission.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: L3PixelClass, L3PixelPolicy, classification",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-08.py",
    "callee": "Sources/GorAVFFmpegAdapter/L3Admission.swift owning station GorAVFFmpegAdapter"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-08.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-08.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-08.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.756663+00:00",
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
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-08.py",
        "block": "fixtures1",
        "sha256": "84af2156f348af5b8030240dd681c7e76a902c48f14246ec006fe98438b5b6f3"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "b3980bb1a4f53e7a86cbf45de4ed5dc5cd166ae1e30622a8a9c63f434a85d513",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-08: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "ec5d797aa9eedfa0653abf067723375db52120bf552638b3e03dfd465dff4a85"
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
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-08: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-08: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
