# W-gdb-199c-1nstinct-11 - Reject invalid stereo frame dimensions without integer traps
state: OPEN / unclaimed
lab: 1nstinct

## Product change
SBSEyeCrop.scan and circularEdge must validate positive usable dimensions, even eye splits where applicable, and overflow-safe width-times-height before comparing Data length or indexing. Invalid dimensions return nil from scan and false from circularEdge. Preserve valid 32x32 and larger pixel scan behavior and existing topBottom split. Audit both entry points; do not change packing policy, calibration, disparity or UI wiring.

## Grounded gap and boundary
U2 stereo/crop frame-input prerequisite; retained S2 Stereo station. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-11.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery. All new test paths start under archive/gor/Tests. This packet does not touch GorCore; preserve any later BuildID/launch-identity return when rebasing. If a later rebase requires a GorCore edit, stop and obtain a refreshed source lease instead of silently changing launch identity.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-11",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Stereo/StereoGeometry.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "SBSEyeCrop.scan and circularEdge must validate positive usable dimensions, even eye splits where applicable, and overflow-safe width-times-height before comparing Data length or indexing. Invalid dimensions return nil from scan and false from circularEdge. Preserve valid 32x32 and larger pixel scan behavior and existing topBottom split. Audit both entry points; do not change packing policy, calibration, disparity or UI wiring.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 stereo/crop frame-input prerequisite; retained S2 Stereo station",
    "callee": "archive/gor/Sources/gor/Stereo/StereoGeometry.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-11.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-11",
    "paths": [
      "archive/gor/Sources/gor/Stereo/StereoGeometry.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-11.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-11.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-11.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:21:52.695384+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "8030956fa12092f1c66e8249eb9f5d8dba951b96bfb14f85c754047d1eb45326",
    "last_5_lines": [
      "0x0000560d192e8000\u20130x0000560d192f6d00 <no build ID> test /tmp/tmpopksmw2i/test",
      "",
      "Backtrace took 0.00s",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Stereo/StereoGeometry.swift",
        "block": "source1",
        "sha256": "9b96e486e91573033d62319bc60b82a54b77869ab4efd595a292de585ac365b9",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-11.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-11.json",
        "block": "fixtures2",
        "sha256": "4d3b536fdccc9929a200b7893eeb12a4a08400b483d945eadf54433b1a50fe56"
      }
    ],
    "receipt_sha256": "a563ca4dc1edad1a091565ba044f0112675b516d02f5b2d62ea0602d4b2ffaf6"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

// MARK: - SBSGeometry
/// Separates coded storage, anamorphic packing and post-crop eye geometry.
enum SBSGeometry {
    static func parseCrop(_ crop:String?)->(Double,Double)? {
        guard let crop,let re=try? NSRegularExpression(pattern:#"^([0-9]+(?:\.[0-9]+)?)x([0-9]+(?:\.[0-9]+)?)(?:\+|$)"#),
              let match=re.firstMatch(in:crop,range:NSRange(crop.startIndex...,in:crop)),
              let a=Range(match.range(at:1),in:crop),let b=Range(match.range(at:2),in:crop),
              let w=Double(crop[a]),let h=Double(crop[b]),w>0,h>0 else{return nil}
        return (w,h)
    }
    /// One authority for full versus half packing: explicit filename token first, else frame layout.
    static func packing(width:Double,height:Double,filename:String)->(full:Bool,basis:String) {
        let name=URL(fileURLWithPath:filename).lastPathComponent.lowercased()
        func token(_ pattern:String)->Bool {name.range(of:pattern,options:.regularExpression) != nil}
        if token(#"(?:^|[^a-z])(?:full[ ._-]*sbs|fsbs)(?:[^a-z]|$)"#) {return (true,"explicitFullToken")}
        if token(#"(?:^|[^a-z])(?:half[ ._-]*sbs|hsbs)(?:[^a-z]|$)"#) {return (false,"explicitHalfToken")}
        return (height>0 && width/height>=3.0,"block185FrameLayout")
    }
    struct Result:Equatable {let aspect:Double;let packing:String;let basis:String}
    static func resolve(width:Double,height:Double,pixelAspect:Double,filename:String,stereoProven:Bool,fullByContract:Bool=false,cropWidth:Double?=nil,cropHeight:Double?=nil)->Result? {
        guard stereoProven,width>0,height>0,width.isFinite,height.isFinite else{return nil}
        let par=pixelAspect.isFinite && pixelAspect>0 ? pixelAspect:1
        let (full,basis)=packing(width:width,height:height,filename:filename)
        // Half SBS stores each eye at half horizontal sampling. Correct that compression once.
        // Crop dimensions are the complete packed frame; each eye retains half its columns.
        let w=(cropWidth ?? width),h=(cropHeight ?? height)
        guard w>0,h>0,w<=width,h<=height else{return nil}
        return Result(aspect:w*par/h/(full ? 2:1),packing:full ? "full":"half",basis:basis)
    }
}

/// Menu ratios describe one displayed picture, independent of storage packing.
/// Crop changes the visible bounds; aspect override changes display proportions.
/// The stereo window contains two copies of that result, with the existing gap.
enum StereoMenuGeometry {
    struct Plan: Equatable {
        let scaleX: Double
        let scaleY: Double
        let eyeAspect: Double
        let windowAspect: Double
    }
    struct Viewport {
        let scaleX:Double,scaleY:Double,centerX:Double,centerY:Double,windowAspect:Double
        var key:String {"\(scaleX):\(scaleY):\(centerX):\(centerY):\(windowAspect)"}
    }
    /// Crop is a viewport, not a new source aspect. Preserve the accepted centre on every refresh.
    static func viewport(_ plan:Plan,detected:CGRect?,menuOwns:Bool) -> Viewport {
        let rect=menuOwns ? nil:detected
        let x=rect.map {Double($0.width)} ?? plan.scaleX,y=rect.map {Double($0.height)} ?? plan.scaleY
        return Viewport(scaleX:x,scaleY:y,centerX:rect.map {Double($0.midX)} ?? 0.5,
            centerY:rect.map {Double($0.midY)} ?? 0.5,windowAspect:plan.windowAspect * (rect == nil ? 1:x/y))
    }
    static func plan(sourceAspect: Double, aspectOverride: Double?, cropAspect: Double?, gap: Double) -> Plan? {
        guard sourceAspect.isFinite, sourceAspect > 0, gap.isFinite else { return nil }
        let display = aspectOverride.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? sourceAspect
        let crop = cropAspect.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let x = crop.map { min(1, $0 / display) } ?? 1
        let y = crop.map { min(1, display / $0) } ?? 1
        let eye = display * x / y
        let fraction = 0.5 - min(0.2, max(0, gap)) * 0.25
        return Plan(scaleX:x, scaleY:y, eyeAspect:eye, windowAspect:eye / fraction)
    }
}

// MARK: - SBSEyeCrop
/// scan each half independently, then retain a common eye crop.
/// No aspect-film labels. Bounds are measured in source pixels; SAR is applied once at display.
enum SBSEyeCrop {
    struct Bounds:Equatable {let x:Int;let y:Int;let width:Int;let height:Int}
    static func scan(_ frame:Data,width:Int,height:Int,topBottom:Bool=false)->[Bounds]? {
        guard width>=32,height>=32,width%2==0,height%2==0,frame.count==width*height else{return nil}
        let a=[UInt8](frame),w=topBottom ? width:width/2,h=topBottom ? height/2:height
        var out:[Bounds]=[]
        for eye in 0...1 {
            let ox=topBottom ? 0:eye*w,oy=topBottom ? eye*h:0
            // Source bounds are conservative: one nonblack sampled pixel keeps that edge.
            // Avoid row-average cropdetect silently discarding tiny bright subtitles/details.
            var minX=w,minY=h,maxX = -1,maxY = -1
            for y in 0..<h {for x in 0..<w {
                if a[(oy+y)*width+ox+x]>12 {minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)}
            }}
            guard maxX>=minX,maxY>=minY else{return nil}
            let t=minY,b=maxY,l=minX,r=maxX
            out.append(Bounds(x:l,y:t,width:r-l+1,height:b-t+1))
        }
        return out
    }
    struct NormalizedCrop:Equatable {let x:Double;let y:Double;let width:Double;let height:Double}
    /// Common horizontal union across both eyes and every sampled frame. One
    /// sampled-pixel guard preserves boundary detail. Vertical crop remains with
    /// the original-pixel video-crop owner, avoiding a second vertical crop.
    static func sourceCrop(_ frames:[Data],width:Int,height:Int,topBottom:Bool=false)->NormalizedCrop? {
        let scans=frames.compactMap{scan($0,width:width,height:height,topBottom:topBottom)}
        guard !topBottom,scans.count>=3,scans.count==frames.count else{return nil}
        let w=width/2
        let all=scans.flatMap{$0}
        let x=max(0,(all.map{$0.x}.min() ?? 0)-1)
        let r=min(w,(all.map{$0.x+$0.width}.max() ?? w)+1)
        return NormalizedCrop(x:Double(x)/Double(w),y:0,width:Double(r-x)/Double(w),height:1)
    }
    static func eyeAspect(_ frames:[Data],width:Int,height:Int,codedWidth:Double,codedHeight:Double,sar:Double,full:Bool,topBottom:Bool=false)->Double? {
        let scans=frames.compactMap{scan($0,width:width,height:height,topBottom:topBottom)}
        guard scans.count>=3 else{return nil}
        func median(_ v:[Double])->Double {let a=v.sorted();return a[a.count/2]}
        // A common crop union avoids cutting differently in the two eyes.
        let ratios=scans.map {eyes -> Double in
            let x=min(eyes[0].x,eyes[1].x),y=min(eyes[0].y,eyes[1].y)
            let right=max(eyes[0].x+eyes[0].width,eyes[1].x+eyes[1].width)
            let bottom=max(eyes[0].y+eyes[0].height,eyes[1].y+eyes[1].height)
            let cw=Double(right-x)*codedWidth/Double(width),ch=Double(bottom-y)*codedHeight/Double(height)
            let sx=topBottom ? 1:(full ? 1:2),sy=topBottom && !full ? 2:1
            return cw*Double(sx)*(sar>0 ? sar:1)/(ch*Double(sy))
        }
        return median(ratios)
    }
    static func circularEdge(_ frames:[Data],width:Int,height:Int)->Bool {
        // Fisheye profile requires both eyes: dark corners, bright central disk, curved occupancy.
        let votes=frames.filter {frame in
            guard frame.count==width*height else{return false};let a=[UInt8](frame),w=width/2
            return (0...1).allSatisfy {eye in
                func lum(_ x:Double,_ y:Double)->Double {Double(a[min(height-1,Int(y*Double(height)))*width+eye*w+min(w-1,Int(x*Double(w)))])}
                let corners=[(0.05,0.05),(0.95,0.05),(0.05,0.95),(0.95,0.95)].map{lum($0.0,$0.1)}
                let axis=[(0.5,0.15),(0.15,0.5),(0.85,0.5),(0.5,0.85)].map{lum($0.0,$0.1)}
                return corners.allSatisfy{$0<12} && axis.allSatisfy{$0>24} && lum(0.5,0.5)>24
            }
        }
        return votes.count>=3
    }
}

// MARK: - StereoDepth
/// Physical-pixel disparity. Cross-eye maps left half to right eye; swap reverses that mapping.
/// No pose input: depth placement is independent of head-pose parallax.
enum StereoDepth {
    struct Placement { let left: Double; let right: Double; let disparity: Double }
    static func placeDepth(disparityPX: Double, distanceMM: Double?, mmPerPX: Double, swapEyes: Bool) -> Placement {
        let scale = mmPerPX > 0 ? mmPerPX : 25.4/227.0
        // Same 500mm reference as182 when camera distance is unavailable, never a guessed live distance.
        let d = (distanceMM ?? 500) > 0 ? (distanceMM ?? 500) : 500
        let limit = 2*d*tan(Double.pi/360)/scale
        let v = max(-limit,min(limit,disparityPX))
        // d = x_leftEye - x_rightEye. In cross-eye, right eye sees the left display half.
        let l = (swapEyes ? 1.0 : -1.0)*v/2
        return Placement(left:l,right:-l,disparity:v)
    }
}

/// Decoded SOURCE layout, independent of output pack and head/VR enable state.
enum CropSourcePacking {
    static func flags(_ kind: String) -> (stereo: Bool, topBottom: Bool) {
        let tb = ["flat-tb", "vr180-tb", "vr360-tb"].contains(kind)
        return (["flat-sbs", "vr180"].contains(kind) || tb, tb)
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
    "archive/gor/Sources/gor/Stereo/StereoGeometry.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nlet bright=Data(repeating: 200,count: 32*32)\ncheck(SBSEyeCrop.scan(bright,width: 32,height: 32)?.count == 2,\"normal scan preserved\")\ncheck(SBSEyeCrop.scan(Data(),width: Int.max-1,height: 32) == nil,\"overflow dimensions refused\")\ncheck(!SBSEyeCrop.circularEdge([Data()],width: Int.max-1,height: 32),\"circular overflow dimensions refused\")\ncheck(!SBSEyeCrop.circularEdge([Data()],width: 0,height: 0),\"zero dimensions refused\")\ncheck(!SBSEyeCrop.circularEdge([Data()],width: -2,height: -2),\"negative dimensions refused\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=-4


*** Signal 4: Backtracing from 0x560d192f3093... done ***

*** Program crashed: Illegal instruction at 0x0000560d192f3093 ***

Thread 0 "test" crashed:

0      0x0000560d192f3093 static SBSEyeCrop.scan(_:width:height:topBottom:) + 2979 in test
1 [ra] 0x0000560d192f4c79 main + 520 in test


Registers:

rax 0xffffffffffffff01  18446744073709551361
rdx 0x0000000000000000  0
rcx 0x0000000000000020  32
rbx 0x0000000000000000  0
rsi 0x0000000000000000  0
rdi 0xc000000000000000  13835058055282163712
rbp 0x00007fff69fb1640  40 18 fb 69 ff 7f 00 00 79 4c 2f 19 0d 56 00 00  @·ûiÿ···yL/··V··
rsp 0x00007fff69fb12d0  c8 c8 c8 c8 c8 c8 c8 c8 c8 c8 c8 c8 c8 c8 c8 c8  ÈÈÈÈÈÈÈÈÈÈÈÈÈÈÈÈ
 r8 0x0000000000000000  0
 r9 0x80000000ffffffff  9223372041149743103
r10 0x00007fd43e6282a8  bf 68 01 00 12 03 0b 00 e0 c6 30 00 00 00 00 00  ¿h······àÆ0·····
r11 0x00007fd43e90c6e0  48 ba 00 00 00 00 00 00 00 c0 31 c0 c3 0f 1f 00  Hº·······À1ÀÃ···
r12 0x00007fff69fb1958  37 2c fb 69 ff 7f 00 00 00 00 00 00 00 00 00 00  7,ûiÿ···········
r13 0x0000560d192f4a70  55 48 89 e5 41 55 48 81 ec e8 01 00 00 48 c7 05  UH·åAUH·ìè···HÇ·
r14 0x0000560d192f8808  68 03 be 3f d4 7f 00 00 f0 11 be 3f d4 7f 00 00  h·¾?Ô···ð·¾?Ô···
r15 0x00007fd43fe45040  e0 62 e4 3f d4 7f 00 00 15 00 00 00 00 00 00 00  àbä?Ô···········
rip 0x0000560d192f3093  0f 0b 0f 0b 0f 0b 0f 0b 0f 0b 0f 0b 0f 0b 0f 0b  ················

rflags 0x0000000000010202  

cs 0x0033  fs 0x0000  gs 0x0000


Images (19 omitted):

0x0000560d192e8000–0x0000560d192f6d00 <no build ID> test /tmp/tmpopksmw2i/test

Backtrace took 0.00s



```

Claim lease: 2h under existing earliest-claim workflow, refreshed only by verified progress. OPEN/unclaimed. Starter RED is not acceptance; own compiler rerun NOT_RUN.
