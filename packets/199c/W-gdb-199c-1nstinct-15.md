# W-gdb-199c-1nstinct-15 - Finite optional metric pupil distance
state: OPEN / unclaimed
lab: 1nstinct

## Product change
PupilDistanceScale.sample must publish millimetres only for finite positive focalPixels and ipdMM and a finite positive computed distance. For absent, nonfinite, nonpositive or unrepresentable calibration return nil metric distance while retaining the valid measured relative sample and pupil-reference behavior. Use numerically safe operation ordering when a result is representable. Do not invent calibration or change pose/backlash thresholds.

## Grounded gap and boundary
U2 camera distance/IPD measurement prerequisite; retained S2 Camera station. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-15.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery. Preserve later BuildID/launch-identity returns when rebasing. No GorCore edit is included in this lease.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-15",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Camera/Pose192d.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "PupilDistanceScale.sample must publish millimetres only for finite positive focalPixels and ipdMM and a finite positive computed distance. For absent, nonfinite, nonpositive or unrepresentable calibration return nil metric distance while retaining the valid measured relative sample and pupil-reference behavior. Use numerically safe operation ordering when a result is representable. Do not invent calibration or change pose/backlash thresholds.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 camera distance/IPD measurement prerequisite; retained S2 Camera station",
    "callee": "archive/gor/Sources/gor/Camera/Pose192d.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-15.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-15",
    "paths": [
      "archive/gor/Sources/gor/Camera/Pose192d.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-15.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-15.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-15.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:31:53.851671+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "e1f183edb45b320c3271a56c0638674d5971f70dcf33b02a9cd36d68b14e0319",
    "last_5_lines": [
      "PASS relative measurement retained",
      "PASS finite calibrated distance preserved",
      "semantic failures=2",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Camera/Pose192d.swift",
        "block": "source1",
        "sha256": "adda737a81e3ad5281c6331288db37992d090f1ea2f62569f0c4778b8782a499",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-15.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-15.json",
        "block": "fixtures2",
        "sha256": "edd4d105306457ad11a493b720f1f791d6053be91c2771e9c5ab07844d6c72fc"
      }
    ],
    "receipt_sha256": "bd784cbd389bef9b2749b3ed0c7a3c0d6ffd959c75a8f711dbd0e0c3b6dda3ba"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

///192d D2. Pixel coordinates preserve Euclidean distance under in-plane roll.
/// Calibrated f_px and anatomical IPD affect metric distance only; their ratio
/// cancels for relative zoom. No focal length or physical IPD is guessed.
struct PupilDistanceScale {
    private var referenceSpans:[String:Double]=[:], lastRelative=0.0
    mutating func reset() { referenceSpans=[:];lastRelative=0 }
    mutating func recenter() { reset() }
    var hasPupilReference:Bool {referenceSpans["pupil"] != nil}
    struct Sample {
        let relative: Double
        let millimetres: Double?
        let usedPupils: Bool
    }
    mutating func sample(left:(Double,Double)?,right:(Double,Double)?,yaw:Double,
                         fallbackWidth:Double,focalPixels:Double?=nil,ipdMM:Double?=nil,landmarkKind:String="pupil") -> Sample {
        if landmarkKind != "pupil",hasPupilReference {
            return Sample(relative:lastRelative,millimetres:nil,usedPupils:false)
        }
        let cy=abs(cos(yaw))
        var span:Double?
        if let a=left,let b=right,cy>Double.ulpOfOne.squareRoot() {
            let d=hypot(a.0-b.0,a.1-b.1)/cy
            if d.isFinite && d>0 {span=d}
        }
        if let span {
            // A pupil centre and an eye-outline centre are different sensors.
            // Match each sensor's first reference to the current distance, never
            // reuse a pupil baseline for an outline or mixed anatomical pair.
            if referenceSpans[landmarkKind]==nil {referenceSpans[landmarkKind]=span/(1+lastRelative)}
            lastRelative=span/(referenceSpans[landmarkKind] ?? span)-1
            let mm:Double?
            if let f=focalPixels,let ipd=ipdMM,f>0,ipd>0 {mm=f*ipd/span} else {mm=nil}
            return Sample(relative:lastRelative,millimetres:mm,usedPupils:true)
        }
        // An axis-aligned detector box changes width during roll and pitch.
        // Missing paired landmarks are missing distance evidence: hold, never
        // manufacture approach/retreat from the box. The box still drives x/y.
        _=fallbackWidth
        return Sample(relative:lastRelative,millimetres:nil,usedPupils:false)
    }
}

/// Reuses the shipped blink detector's0.65 open ratio, bilateral and immediate.
/// Missing/closed geometry cannot update pose or teach a distance reference.
struct PoseEyeMeasurementGate {
    private var left:[Double]=[],right:[Double]=[]
    mutating func accept(_ apertures:[Double])->Bool {
        guard apertures.count==2,apertures.allSatisfy({$0.isFinite && $0>0}) else{return false}
        if !left.isEmpty {
            let l=left.sorted()[left.count*3/4],r=right.sorted()[right.count*3/4]
            guard apertures[0]>=0.65*l,apertures[1]>=0.65*r else{return false}
        }
        left.append(apertures[0]);right.append(apertures[1])
        if left.count>121 {left.removeFirst();right.removeFirst()}
        return true
    }
}

///192d D1 continuous backlash followed by one exact critically damped step.
/// Noise bands and fixed taus are explicit measured inputs, never mode switches.
struct PoseBacklashFollow {
    let bands:[Double],taus:[Double]
    private var held:[Double]?,position:[Double]?,velocity:[Double]
    private var previousTime:Double?
    init(bands:[Double],taus:[Double]) {
        precondition(bands.count==taus.count && !bands.isEmpty)
        precondition(bands.allSatisfy{$0.isFinite && $0>=0} && taus.allSatisfy{$0.isFinite && $0>0})
        self.bands=bands;self.taus=taus;velocity=Array(repeating:0,count:bands.count)
    }
    mutating func hold(at t:Double) {if previousTime != nil {previousTime=t};velocity=Array(repeating:0,count:bands.count)}
    mutating func reset() {held=nil;position=nil;previousTime=nil;velocity=Array(repeating:0,count:bands.count)}
    mutating func accept(_ filtered:[Double],at t:Double,heldChannels:Set<Int>=[])->[Double] {
        guard filtered.count==bands.count,filtered.allSatisfy({$0.isFinite}),t.isFinite else {return position ?? Array(repeating:0,count:bands.count)}
        guard var target=held,var x=position,let pt=previousTime else {held=filtered;position=filtered;previousTime=t;return filtered}
        guard t>pt else {return x}
        let dt=t-pt
        for i in x.indices {
            if heldChannels.contains(i) {velocity[i]=0;continue}
            let e=filtered[i]-target[i]
            target[i]+=(e<0 ? -1:1)*max(0,abs(e)-bands[i])
            let omega=1/taus[i],d=x[i]-target[i],c=velocity[i]+omega*d,decay=exp(-omega*dt)
            x[i]=target[i]+(d+c*dt)*decay
            velocity[i]=(velocity[i]-omega*c*dt)*decay
        }
        held=target;position=x;previousTime=t;return x
    }
}

/// Startup noise estimate from33 filtered samples (same25% variance uncertainty
/// sample budget as the former estimator). Detrend each channel before measuring
/// its robust MAD envelope, so a slow coherent lean is not learned as noise.
/// Provisional online calibration, not a labeled owner still-head segment.
struct PoseNoiseCalibration {
    private var samples:[[Double]]=[]
    private(set) var bands:[Double]?
    mutating func interrupt() {if bands==nil {samples=[]}}
    mutating func observe(_ x:[Double]) {
        guard bands==nil,x.count==6,x.allSatisfy({$0.isFinite}) else{return}
        samples.append(x);guard samples.count==33 else{return}
        func median(_ a:[Double])->Double {let b=a.sorted();return b[b.count/2]}
        bands=(0..<6).map {j in
            let ys=samples.map{$0[j]},mid=16.0
            let mean=ys.reduce(0,+)/33
            let slope=ys.enumerated().reduce(0.0){$0+(Double($1.offset)-mid)*($1.element-mean)}/2992
            let residual=ys.enumerated().map{$0.element-mean-slope*(Double($0.offset)-mid)}
            let m=median(residual)
            return 3*median(residual.map{abs($0-m)})/0.6744897501960817
        }
    }
}

/// Dimensionless anatomy consistency, not motion rejection. The shipped33sample
/// statistical budget and3MAD envelope learn ratios that uniform scaling cannot change.
private struct PoseDistanceRatioCalibration {
    private var samples:[[Double]]=[]
    private var centres:[Double]?,bands:[Double]?
    var calibrated:Bool {centres != nil}
    mutating func accept(pupils:[Double],eyeGeometry:[Double],eyeWidths:[Double],yaw:Double,pitch:Double)->Bool {
        guard pupils.count==4,eyeGeometry.count==4,eyeWidths.count==2,
              (pupils+eyeGeometry+eyeWidths).allSatisfy({$0.isFinite}),eyeWidths.allSatisfy({$0>0}) else {return false}
        let width=(eyeWidths[0]+eyeWidths[1])/2
        let ratios=[hypot(pupils[2]-pupils[0],pupils[3]-pupils[1])/width,
                    hypot(eyeGeometry[2]-eyeGeometry[0],eyeGeometry[3]-eyeGeometry[1])/width]
        guard ratios.allSatisfy({$0.isFinite && $0>0}) else{return false}
        // Orthographic projection of a rigid face plane has singular values1
        // and |normal.z|. A ratio of two planar lengths can change only within
        // [ratio*s,ratio/s]. Roll and uniform real distance scaling cancel.
        let foreshortening=abs(cos(yaw)*cos(pitch))
        guard foreshortening.isFinite,foreshortening>Double.ulpOfOne.squareRoot() else{return false}
        let bounds: [Double] = ratios.flatMap { ratio -> [Double] in
            [ratio * foreshortening, ratio / foreshortening]
        }
        if let centres, let bands {
            return (0..<2).allSatisfy { j -> Bool in
                let lowerIndex: Int = j * 2
                let upperIndex: Int = lowerIndex + 1
                let lowerLimit: Double = centres[lowerIndex] - bands[lowerIndex]
                let upperLimit: Double = centres[upperIndex] + bands[upperIndex]
                let reachesLower: Bool = bounds[upperIndex] >= lowerLimit
                return reachesLower && bounds[lowerIndex] <= upperLimit
            }
        }
        samples.append(bounds)
        if samples.count==33 {
            func median(_ xs:[Double])->Double {xs.sorted()[xs.count/2]}
            centres=(0..<4).map{j in median(samples.map{$0[j]})}
            bands=(0..<4).map{j in let c=centres![j];return max(3*median(samples.map{abs($0[j]-c)})/0.6744897501960817,abs(c)*Double.ulpOfOne.squareRoot())}
        }
        return true
    }
}

/// Pupil and outline-centre routes retain independent anatomy calibrations,
/// just as PupilDistanceScale retains independent references for these sensors.
struct PoseDistanceConsistency {
    private var pupil=PoseDistanceRatioCalibration(),eye=PoseDistanceRatioCalibration()
    var calibrated:Bool {pupil.calibrated || eye.calibrated}
    func ready(for kind:String)->Bool {kind=="pupil" ? pupil.calibrated:(kind=="eye" && eye.calibrated)}
    mutating func accept(pupils:[Double],eyeGeometry:[Double],eyeWidths:[Double],yaw:Double,pitch:Double,landmarkKind:String="pupil")->Bool {
        if landmarkKind=="pupil" {return pupil.accept(pupils:pupils,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,yaw:yaw,pitch:pitch)}
        if landmarkKind=="eye" {return eye.accept(pupils:pupils,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,yaw:yaw,pitch:pitch)}
        return false
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
    "archive/gor/Sources/gor/Camera/Pose192d.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nfor focal in [Double.infinity,Double.nan,Double.greatestFiniteMagnitude] {\n var scale=PupilDistanceScale()\n let s=scale.sample(left: (0,0),right: (10,0),yaw: 0,fallbackWidth: 100,focalPixels: focal,ipdMM: Double.greatestFiniteMagnitude)\n check(s.millimetres == nil,\"invalid metric output absent\")\n check(s.usedPupils && s.relative == 0,\"relative measurement retained\")\n}\nvar normal=PupilDistanceScale()\nlet s=normal.sample(left: (0,0),right: (10,0),yaw: 0,fallbackWidth: 100,focalPixels: 100,ipdMM: 60)\ncheck(s.millimetres == 600,\"finite calibrated distance preserved\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL invalid metric output absent
PASS relative measurement retained
PASS invalid metric output absent
PASS relative measurement retained
FAIL invalid metric output absent
PASS relative measurement retained
PASS finite calibrated distance preserved
semantic failures=2



```

Claim lease: 2h under existing earliest-claim workflow, refreshed only by verified progress. OPEN/unclaimed. Starter RED is not acceptance; own compiler rerun NOT_RUN.
