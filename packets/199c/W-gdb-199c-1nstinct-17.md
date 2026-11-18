# W-gdb-199c-1nstinct-17 - Finite fail-closed subtitle tilt placement
state: OPEN / unclaimed
lab: 1nstinct

## Product change
SubtitleTiltGeometry.place must validate finite CGRect origins/extents/endpoints, positive screen dimensions, nonnegative ink dimensions, and all scalar inputs (including left and offset). Return a documented neutral Placement with all five fields zero for invalid or nonrepresentable input/output. Preserve valid rotation/spacing geometry exactly and use no font scaling. Guard intermediate overflow rather than returning NaN/infinity in a placement. No SubtitleView/UI edits.

## Grounded gap and boundary
U2 subtitle position/depth input prerequisite; retained S2 Subtitles station. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-17.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery. Preserve later BuildID/launch-identity returns when rebasing. No GorCore edit is included in this lease.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-17",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Subtitles/SubtitleTiltGeometry.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "SubtitleTiltGeometry.place must validate finite CGRect origins/extents/endpoints, positive screen dimensions, nonnegative ink dimensions, and all scalar inputs (including left and offset). Return a documented neutral Placement with all five fields zero for invalid or nonrepresentable input/output. Preserve valid rotation/spacing geometry exactly and use no font scaling. Guard intermediate overflow rather than returning NaN/infinity in a placement. No SubtitleView/UI edits.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 subtitle position/depth input prerequisite; retained S2 Subtitles station",
    "callee": "archive/gor/Sources/gor/Subtitles/SubtitleTiltGeometry.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-17.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-17",
    "paths": [
      "archive/gor/Sources/gor/Subtitles/SubtitleTiltGeometry.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-17.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-17.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-17.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:31:54.673826+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "a75fb962145bd0b00ce515f7e53484cb75449835ea705d26ce455a6c0c1e9bfd",
    "last_5_lines": [
      "PASS invalid offset gets neutral placement",
      "PASS normal placement unchanged",
      "semantic failures=4",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Subtitles/SubtitleTiltGeometry.swift",
        "block": "source1",
        "sha256": "204496360f173b50ed42f399e79b14cf77cb9d7b3c0833247f4e30d1af064abe",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-17.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-17.json",
        "block": "fixtures2",
        "sha256": "c83fd80fac273d7800ecaae3f05219eb630ec6e66ce1196a41c678d11773b150"
      }
    ],
    "receipt_sha256": "ee66b656485d9c3b1fbe4791127ca7e99733409be5e003e5efa25c72f24621c8"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

///192d subtitle overlay: rigid glyph rotation, stereo baseline along the tracked
/// interocular axis, translation-only safety placement. No font-size/ink scaling.
enum SubtitleTiltGeometry {
    struct Placement {
        let angle:Double
        let leftX:Double,leftY:Double,replicaX:Double,replicaY:Double
    }
    static func place(ink:CGRect,screen:CGRect,shift:Double,left:Double,offset:Double,
                      roll:Double,pairRoll:Double)->Placement {
        guard roll.isFinite,pairRoll.isFinite,shift.isFinite,screen.width>0,screen.height>0 else {
            return Placement(angle:0,leftX:left,leftY:0,replicaX:shift+offset,replicaY:0)
        }
        // Film angles are measured in the shader's Y-up output. The
        // AppKit-backed compositor displays layer Y in the opposite direction.
        // Convert BOTH glyph rotation and replica-axis placement at this boundary.
        let layerRoll = -roll, layerPairRoll = -pairRoll
        let c=cos(layerRoll),s=sin(layerRoll),pc=cos(layerPairRoll),ps=sin(layerPairRoll)
        let hw=Double(ink.width)*0.5,hh=Double(ink.height)*0.5
        let ex=abs(c)*hw+abs(s)*hh,ey=abs(s)*hw+abs(c)*hh
        // Reserve the rotated ink first, then use the available width/height
        // for eye spacing. Keeping the glyphs at their existing size is preferred.
        let requested=max(0,shift+offset)
        let xLimit=max(0,(Double(screen.width)-2*ex)/max(abs(pc),1e-12))
        let yLimit=max(0,(Double(screen.height)-2*ey)/max(abs(ps),1e-12))
        let spacing=min(requested,min(xLimit,yLimit))
        let dx=spacing*pc,dy=spacing*ps
        var cx=Double(ink.midX)+left+(requested-dx)*0.5
        var cy=Double(ink.midY)-dy*0.5
        // One common correction keeps both eyes' corners visible, without
        // changing their relative depth/angle or clipping a rotated baseline.
        cx=max(Double(screen.minX)+ex,min(cx,Double(screen.maxX)-ex-dx))
        cy=max(Double(screen.minY)+ey-min(0,dy),min(cy,Double(screen.maxY)-ey-max(0,dy)))
        return Placement(angle:layerRoll,leftX:cx-Double(ink.midX),leftY:cy-Double(ink.midY),replicaX:dx,replicaY:dy)
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
    "archive/gor/Sources/gor/Subtitles/SubtitleTiltGeometry.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nlet ink=CGRect(x: 10,y: 10,width: 100,height: 20),screen=CGRect(x: 0,y: 0,width: 800,height: 600)\nfor bad in [Double.nan,Double.infinity,-Double.infinity] {\n let p=SubtitleTiltGeometry.place(ink: ink,screen: screen,shift: 10,left: bad,offset: 0,roll: 0,pairRoll: 0)\n check(p.angle == 0 && p.leftX == 0 && p.leftY == 0 && p.replicaX == 0 && p.replicaY == 0,\"invalid left gets neutral placement\")\n let q=SubtitleTiltGeometry.place(ink: ink,screen: screen,shift: 10,left: 0,offset: bad,roll: 0,pairRoll: 0)\n check(q.angle == 0 && q.leftX == 0 && q.leftY == 0 && q.replicaX == 0 && q.replicaY == 0,\"invalid offset gets neutral placement\")\n}\nlet ok=SubtitleTiltGeometry.place(ink: ink,screen: screen,shift: 10,left: 0,offset: 0,roll: 0,pairRoll: 0)\ncheck(ok.angle == 0 && ok.leftX == 0 && ok.leftY == 0 && ok.replicaX == 10 && ok.replicaY == 0,\"normal placement unchanged\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL invalid left gets neutral placement
PASS invalid offset gets neutral placement
FAIL invalid left gets neutral placement
FAIL invalid offset gets neutral placement
FAIL invalid left gets neutral placement
PASS invalid offset gets neutral placement
PASS normal placement unchanged
semantic failures=4



```

Claim lease: 2h under existing earliest-claim workflow, refreshed only by verified progress. OPEN/unclaimed. Starter RED is not acceptance; own compiler rerun NOT_RUN.
