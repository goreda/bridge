# W-gdb-199c-in2tinct-16 - Nonfinite cue intervals cannot become visible
state: OPEN / unclaimed
lab: in2tinct

## Product change
contains(seconds:) must require finite query, finite endpoints and end > start. Preserve half-open boundaries, finite negative cue starts, text and style association. This changes the value-model guard only, not normal subtitle UI wiring.

## Grounded gap and boundary
U2 normal subtitle import/presentation prerequisite. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-16.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-in2tinct-16",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "contains(seconds:) must require finite query, finite endpoints and end > start. Preserve half-open boundaries, finite negative cue starts, text and style association. This changes the value-model guard only, not normal subtitle UI wiring.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 normal subtitle import/presentation prerequisite",
    "callee": "Sources/GorAVSubtitles/SubtitleCue.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-16.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199c-in2tinct-16",
    "paths": [
      "Sources/GorAVSubtitles/SubtitleCue.swift",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-16.py",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-16.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-16.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:13:48.239033+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "7b2ef2f78421ee03b250365437f7ff2cfa748c16b90382de54a68adb5e720efb",
    "last_5_lines": [
      "FAIL infinite query refused",
      "PASS finite half-open interval",
      "semantic failures=2",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
        "block": "source1",
        "sha256": "2311ed3052c4a66f2d7942d23624b693faa52dc509354e22fbff148aa3abaa40",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-16.py",
        "block": "fixtures1",
        "sha256": "e03d358b27bdbfa400e7bd95e500b213ee6b06958a804bc46767d841bd95d8b0"
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-16.json",
        "block": "fixtures2",
        "sha256": "b74fcdcf0f8024d849b5749012458b86728c5469a2ad58c8c2b7c49bb4e8f65a"
      }
    ],
    "receipt_sha256": "5f26626a6326b510ecd46cee7adfc040fb74f010ca3457008a30f533123700ac"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

/// One timed subtitle cue over the half-open interval [startSeconds, endSeconds).
/// Format-neutral: produced by the SRT (L5) and ASS (L6) parsers and consumed
/// by the future presenter hook (trunk-owned wiring, block-78 L8 allocation:
/// Sources/GorAVSubtitles is a new path; no trunk files touched here).
public struct SubtitleCue: Equatable, Sendable {
    public let index: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public let lines: [String]
    /// ASS Dialogue Style association, preserved for the future renderer.
    /// nil for SRT and for ASS events whose Format carries no Style field.
    /// This is an association record, not styling support.
    public let styleName: String?

    public init(index: Int, startSeconds: Double, endSeconds: Double, lines: [String], styleName: String? = nil) {
        self.index = index
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.lines = lines
        self.styleName = styleName
    }

    /// Cue text with original line breaks.
    public var text: String { lines.joined(separator: "\n") }

    /// Membership test on the half-open interval; inverted cues hold nothing.
    public func contains(seconds t: Double) -> Bool {
        t >= startSeconds && t < endSeconds
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
    "Sources/GorAVSubtitles/SubtitleCue.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nlet c=SubtitleCue(index: 1,startSeconds: -.infinity,endSeconds: .infinity,lines: [\"x\"])\ncheck(!c.contains(seconds: 1),\"infinite endpoints refused\")\ncheck(!c.contains(seconds: -.infinity),\"infinite query refused\")\nlet ok=SubtitleCue(index: 2,startSeconds: -1,endSeconds: 2,lines: [\"x\"])\ncheck(ok.contains(seconds: -1) && !ok.contains(seconds: 2),\"finite half-open interval\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL infinite endpoints refused
FAIL infinite query refused
PASS finite half-open interval
semantic failures=2



```

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
