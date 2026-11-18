# W-gdb-199c-1nstinct-14 - Finite binocular measurement output
state: OPEN / unclaimed
lab: 1nstinct

## Product change
BinocularGazeSample.measure must produce only finite fields, even when finite source coordinates overflow intermediate differences, spans or midpoint sums. Compute midpoints with overflow-safe arithmetic where representable; refuse nil when a required result cannot be represented. Preserve ordinary paired-eye measurements and thresholds. Do not change calibration fitting, persistence or camera/control wiring.

## Grounded gap and boundary
U2 camera/gaze input safety prerequisite; retained S2 Camera station. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-14.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery. Preserve later BuildID/launch-identity returns when rebasing. No GorCore edit is included in this lease.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-14",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Camera/BinocularGaze.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "BinocularGazeSample.measure must produce only finite fields, even when finite source coordinates overflow intermediate differences, spans or midpoint sums. Compute midpoints with overflow-safe arithmetic where representable; refuse nil when a required result cannot be represented. Preserve ordinary paired-eye measurements and thresholds. Do not change calibration fitting, persistence or camera/control wiring.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 camera/gaze input safety prerequisite; retained S2 Camera station",
    "callee": "archive/gor/Sources/gor/Camera/BinocularGaze.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-14.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-14",
    "paths": [
      "archive/gor/Sources/gor/Camera/BinocularGaze.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-14.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-14.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-14.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:31:53.269084+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "6ace79c46a9a5943e79ec449d634aa87c89d3581ae0a80e0aaf41fc407159cf0",
    "last_5_lines": [
      "FAIL finite inputs never yield nonfinite sample",
      "PASS normal measurement preserved",
      "semantic failures=1",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Camera/BinocularGaze.swift",
        "block": "source1",
        "sha256": "ef7d2efe1ea5db435a93b99f7d6aec4931a0699c0fb5af30e57b92a03a658841",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-14.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-14.json",
        "block": "fixtures2",
        "sha256": "c7fa8866de2d493e5c62494680a88c917586960bdb91988f0f284eb1de3d4b6d"
      }
    ],
    "receipt_sha256": "c2086f5d0205672a886c067e6f8356311e4e208f1507b933fba3064a5c36c43a"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

/// Camera-local binocular pupil displacement. This is NOT a screen gaze point.
/// Only paired pupils inside measured eye outlines can supply a sample.
struct BinocularGazeSample {
    let t:Double,x:Double,y:Double,yaw:Double,pitch:Double,roll:Double,span:Double,cx:Double,cy:Double
    init(t:Double,x:Double,y:Double,yaw:Double,pitch:Double,roll:Double=0,span:Double=1,cx:Double=0,cy:Double=0) {
        self.t=t;self.x=x;self.y=y;self.yaw=yaw;self.pitch=pitch;self.roll=roll
        self.span=span;self.cx=cx;self.cy=cy
    }
    static func measure(t:Double,pupils:[Double],eyes:[Double],widths:[Double],apertures:[Double],yaw:Double,pitch:Double,roll:Double=0)->Self? {
        guard pupils.count==4,eyes.count==4,widths.count==2,apertures.count==2,
              ([t,yaw,pitch,roll]+pupils+eyes+widths+apertures).allSatisfy({$0.isFinite}),
              widths.allSatisfy({$0>2}),apertures.allSatisfy({$0>0.10}) else{return nil}
        let dx=eyes[2]-eyes[0],dy=eyes[3]-eyes[1],span=hypot(dx,dy)
        guard span>2 else{return nil}
        let ax=dx/span,ay=dy/span
        var xs:[Double]=[],ys:[Double]=[]
        for i in 0..<2 {
            let px=pupils[i*2]-eyes[i*2],py=pupils[i*2+1]-eyes[i*2+1]
            let x=(px*ax+py*ay)/widths[i],y=(-px*ay+py*ax)/widths[i]
            guard abs(x)<0.6,abs(y)<0.35 else{return nil}
            xs.append(x);ys.append(y)
        }
        return Self(t:t,x:(xs[0]+xs[1])/2,y:(ys[0]+ys[1])/2,yaw:yaw,pitch:pitch,roll:roll,span:span,cx:(eyes[0]+eyes[2])/2,cy:(eyes[1]+eyes[3])/2)
    }
}

/// Five measured screen targets fit an affine local mapping. It is an estimate,
/// valid for the calibrated window geometry and nearby head orientation only.
/// No eye/head substitution, fixed sensitivity, persisted biometric data or cursor control.
struct BinocularGazeCalibration {
    static let targets:[CGPoint]=[CGPoint(x:0.5,y:0.5),CGPoint(x:0.2,y:0.25),CGPoint(x:0.8,y:0.75),CGPoint(x:0.2,y:0.75),CGPoint(x:0.8,y:0.25)]
    enum State:Equatable {case off,calibrating(Int),tracking,failed}
    private(set) var state:State = .off
    private var rows:[(Double,Double)]=[],batch:[BinocularGazeSample]=[]
    private var entered:Double?,lastT:Double?,anchor:BinocularGazeSample?
    private var cx:[Double]=[],cy:[Double]=[]
    mutating func start(){self=Self();state = .calibrating(0)}
    mutating func stop(){self=Self()}
    mutating func feed(_ sample:BinocularGazeSample?,now:Double)->CGPoint? {
        guard let s=sample,now.isFinite,now-s.t>=0,now-s.t<0.2 else{batch=[];entered=nil;return nil}
        guard lastT==nil || s.t>lastT! else{return nil};lastT=s.t
        if anchor==nil {anchor=s}
        guard let anchor,abs(s.yaw-anchor.yaw)<0.15,abs(s.pitch-anchor.pitch)<0.15,
              abs(s.roll-anchor.roll)<0.15,anchor.span>0,abs(s.span/anchor.span-1)<0.12,
              hypot(s.cx-anchor.cx,s.cy-anchor.cy)/anchor.span<0.25 else{batch=[];entered=nil;return nil}
        switch state {
        case .calibrating(let index):
            if entered==nil {entered=now}
            guard now-(entered ?? now)>0.7 else{return nil} // target acquisition, not training data
            batch.append(s)
            guard batch.count>=12,now-(entered ?? now)>1.2 else{return nil}
            func median(_ a:[Double])->Double {let b=a.sorted();return b[b.count/2]}
            rows.append((median(batch.map{$0.x}),median(batch.map{$0.y})))
            batch=[];entered=nil
            if index+1<Self.targets.count {state = .calibrating(index+1)}
            else {state=fit() ? .tracking:.failed}
            return nil
        case .tracking:
            guard cx.count==3,cy.count==3 else{return nil}
            let x=cx[0]+cx[1]*s.x+cx[2]*s.y,y=cy[0]+cy[1]*s.x+cy[2]*s.y
            guard x.isFinite,y.isFinite,x>=0,x<=1,y>=0,y<=1 else{return nil}
            return CGPoint(x:x,y:y)
        default:return nil
        }
    }
    private mutating func fit()->Bool {
        guard rows.count==Self.targets.count else{return false}
        var a=[[Double]](repeating:[Double](repeating:0,count:5),count:3)
        for (i,row) in rows.enumerated() {
            let v=[1.0,row.0,row.1],p=Self.targets[i]
            for r in 0..<3 {for c in 0..<3 {a[r][c]+=v[r]*v[c]};a[r][3]+=v[r]*Double(p.x);a[r][4]+=v[r]*Double(p.y)}
        }
        for k in 0..<3 {
            let pivot=(k..<3).max(by:{abs(a[$0][k])<abs(a[$1][k])})!
            guard abs(a[pivot][k])>1e-6 else{return false}
            a.swapAt(k,pivot);let d=a[k][k];for c in k..<5 {a[k][c]/=d}
            for r in 0..<3 where r != k {let m=a[r][k];for c in k..<5 {a[r][c]-=m*a[k][c]}}
        }
        cx=a.map{$0[3]};cy=a.map{$0[4]}
        for (i,row) in rows.enumerated() {
            let p=Self.targets[i],x=cx[0]+cx[1]*row.0+cx[2]*row.1,y=cy[0]+cy[1]*row.0+cy[2]*row.1
            guard hypot(x-Double(p.x),y-Double(p.y))<0.12 else{cx=[];cy=[];return false}
        }
        return true
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
    "archive/gor/Sources/gor/Camera/BinocularGaze.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nlet large=Double.greatestFiniteMagnitude * 0.75\nlet measured=BinocularGazeSample.measure(t: 1,pupils: [large,0,large+1e293,0],eyes: [large,0,large+1e293,0],widths: [1e294,1e294],apertures: [1,1],yaw: 0,pitch: 0)\nif let s=measured { check([s.x,s.y,s.span,s.cx,s.cy].allSatisfy{$0.isFinite},\"finite inputs never yield nonfinite sample\") }\nlet normal=BinocularGazeSample.measure(t: 1,pupils: [10,10,30,10],eyes: [10,10,30,10],widths: [10,10],apertures: [1,1],yaw: 0,pitch: 0)\ncheck(normal?.cx == 20 && normal?.cy == 10 && normal?.span == 20,\"normal measurement preserved\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL finite inputs never yield nonfinite sample
PASS normal measurement preserved
semantic failures=1



```

Claim lease: 2h under existing earliest-claim workflow, refreshed only by verified progress. OPEN/unclaimed. Starter RED is not acceptance; own compiler rerun NOT_RUN.
