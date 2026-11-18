# W-gdb-199c-1nstinct-16 - Reject unrepresentable face rectangle endpoints
state: OPEN / unclaimed
lab: 1nstinct

## Product change
Both rectangleReason and reason must return existing structural reason3 when positive finite rectangle dimensions/origin imply nonfinite maxX or maxY. Validate the whole rectangle extent before declaring it structurally valid. Preserve existing reason precedence for face-count and missing-vector cases, all normal finite boxes, and the current confidence policy. No confidence threshold retuning or camera lifecycle change.

## Grounded gap and boundary
U2 camera structural-input prerequisite; retained S2 Camera station. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-16.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery. Preserve later BuildID/launch-identity returns when rebasing. No GorCore edit is included in this lease.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-16",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Camera/PoseMeasurementValidity.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "Both rectangleReason and reason must return existing structural reason3 when positive finite rectangle dimensions/origin imply nonfinite maxX or maxY. Validate the whole rectangle extent before declaring it structurally valid. Preserve existing reason precedence for face-count and missing-vector cases, all normal finite boxes, and the current confidence policy. No confidence threshold retuning or camera lifecycle change.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 camera structural-input prerequisite; retained S2 Camera station",
    "callee": "archive/gor/Sources/gor/Camera/PoseMeasurementValidity.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-16.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-16",
    "paths": [
      "archive/gor/Sources/gor/Camera/PoseMeasurementValidity.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-16.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-16.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-16.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:31:54.217052+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "803cda4f1932adfede7372bae990f4cd60bc2780b092bc98161b240809f303af",
    "last_5_lines": [
      "PASS normal box retained",
      "PASS reason precedence retained",
      "semantic failures=4",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Camera/PoseMeasurementValidity.swift",
        "block": "source1",
        "sha256": "8a063f2298953d8e7ade1063677d9e7e349580c00c79afa7b57b56e8f7115317",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-16.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-16.json",
        "block": "fixtures2",
        "sha256": "cea218f34a52690fee0d777561eb87863db00c4ed6fca8c6a35ff29e7918a8a2"
      }
    ],
    "receipt_sha256": "5beff0286dc50eca9e34acecf3a6010e2e3df7e56e5de70c72d5324f68f52aae"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

/// Structural invalidity is independent of lighting or a confidence threshold.
/// Semantic conditions (dark room, hand, glare) require measured frame evidence.
enum PoseMeasurementValidity {
    /// Rectangle pose has measured angles/box but makes no pupil, gaze or eyelid claim.
    static func rectangleReason(faceCount:Int,angles:[Double],box:CGRect)->Int {
        guard faceCount==1 else {return 1}
        guard angles.count==3 else {return 2}
        guard angles.allSatisfy({$0.isFinite}),box.minX.isFinite,box.minY.isFinite,
              box.width.isFinite,box.height.isFinite,box.width>0,box.height>0 else {return 3}
        return 0
    }
    //0 valid structure;1 missing/ambiguous face;2 absent landmarks/pose;3 nonfinite.
    static func reason(faceCount:Int,landmarkFaceCount:Int,angles:[Double],box:CGRect,
                       pupils:[Double],landmarkConfidence:Double)->Int {
        guard faceCount==1,landmarkFaceCount==1 else{return 1}
        guard angles.count==3,pupils.count==4 else{return 2}
        guard angles.allSatisfy({$0.isFinite}),pupils.allSatisfy({$0.isFinite}),
              landmarkConfidence.isFinite,landmarkConfidence>0,
              box.minX.isFinite,box.minY.isFinite,box.width.isFinite,box.height.isFinite,
              box.width>0,box.height>0 else{return 3}
        return 0
    }
}

```

```python id=fixtures1
from pathlib import Path
import os,subprocess,tempfile,sys,json,resource,shutil
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5]
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
    "archive/gor/Sources/gor/Camera/PoseMeasurementValidity.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nlet m=Double.greatestFiniteMagnitude\nfor box in [CGRect(x: m,y: 0,width: m,height: 1),CGRect(x: 0,y: m,width: 1,height: m)] {\n check(PoseMeasurementValidity.rectangleReason(faceCount: 1,angles: [0,0,0],box: box) == 3,\"rectangle overflow refused\")\n check(PoseMeasurementValidity.reason(faceCount: 1,landmarkFaceCount: 1,angles: [0,0,0],box: box,pupils: [0,0,0,0],landmarkConfidence: 1) == 3,\"landmark rectangle overflow refused\")\n}\ncheck(PoseMeasurementValidity.rectangleReason(faceCount: 1,angles: [0,0,0],box: CGRect(x: 0,y: 0,width: 1,height: 1)) == 0,\"normal box retained\")\ncheck(PoseMeasurementValidity.rectangleReason(faceCount: 0,angles: [],box: .zero) == 1,\"reason precedence retained\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL rectangle overflow refused
FAIL landmark rectangle overflow refused
FAIL rectangle overflow refused
FAIL landmark rectangle overflow refused
PASS normal box retained
PASS reason precedence retained
semantic failures=4



```

Claim lease: 2h under existing earliest-claim workflow, refreshed only by verified progress. OPEN/unclaimed. Starter RED is not acceptance; own compiler rerun NOT_RUN.
