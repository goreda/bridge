#!/usr/bin/env python3
"""Structural degradation audit rebased to decoded C1 input, never lighting labels.

The original validity, continuity, sampler, trace and historical-formula checks
remain. Native-Vision assumptions are replaced by a production decoded-frame
projection; native camera and Darwin compiler performance remain unproved.
"""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read, materialize as _s3unit
import json,math,os,statistics,subprocess,sys,tempfile,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2]
program='''import Foundation
let valid=CGRect(x:0.3,y:0.3,width:0.3,height:0.4)
func reason(_ n:Int=1,_ m:Int=1,_ a:[Double]=[0,0,0],_ p:[Double]=[0,0,60,0],_ c:Double=0.8,_ box:CGRect=CGRect(x:0.3,y:0.3,width:0.3,height:0.4))->Int {
PoseMeasurementValidity.reason(faceCount:n,landmarkFaceCount:m,angles:a,box:box,pupils:p,landmarkConfidence:c)
}
precondition(reason()==0)
for sign in [-1.0,1] {
 precondition(reason(0)==1);precondition(reason(2)==1);precondition(reason(1,2)==1)
 precondition(reason(1,1,[sign*0.3,0])==2)
 precondition(reason(1,1,[0,0,0],[])==2)
 precondition(reason(1,1,[Double.nan,0,0])==3)
 precondition(reason(1,1,[0,0,0],[0,0,Double.infinity,0])==3)
 precondition(reason(1,1,[0,0,0],[0,0,60,0],Double.nan)==3)
 precondition(reason(1,1,[sign*0.3,sign*0.2,sign*0.5])==0)
 // Low confidence is data, not a lighting label: do not silently invent a cutoff.
 precondition(reason(1,1,[0,0,0],[0,0,60,0],0.7)==0)
}
for sign in [-1.0,1] {
 precondition(PoseMeasurementValidity.rectangleReason(faceCount:1,angles:[sign*0.3,sign*0.2,sign*0.5],box:valid)==0)
 for count in [0,2] {precondition(PoseMeasurementValidity.rectangleReason(faceCount:count,angles:[0,0,0],box:valid)==1)}
 precondition(PoseMeasurementValidity.rectangleReason(faceCount:1,angles:[0,0],box:valid)==2)
 precondition(PoseMeasurementValidity.rectangleReason(faceCount:1,angles:[Double.nan,0,0],box:valid)==3)
 precondition(PoseMeasurementValidity.rectangleReason(faceCount:1,angles:[0,0,0],box:CGRect(x:0,y:0,width:0,height:1))==3)
}
var held=[Double](repeating:0,count:6)
for sign in [-1.0,1] {for n in [0,2] {
 let r=reason(n,1,[sign,sign,sign]);if r==0 {held=[sign,sign,sign,1,1,1]}
 precondition(held==Array(repeating:0,count:6))
}}
var continuity=PoseContinuity();_=continuity.accept(Array(repeating:0,count:6),t:0)
continuity.faceLost();let first=continuity.accept(Array(repeating:0.5,count:6),t:1)
precondition(first.values==Array(repeating:0,count:6))
let end=continuity.accept(Array(repeating:0.5,count:6),t:1.2)
precondition(end.values==Array(repeating:0.5,count:6))
print("PASS structural degradation signed tests: missing/multiple face, absent fields/landmarks, nonfinite, hold-before-mutation; source continuity reacquire starts at held pose")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 (p/'continuity.swift').write_text(_s3read(root/'Sources/gor/Camera/HeadPose.swift').split('/// Owner-authorized pose-only diagnostics:')[0])
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_s3unit(root/'Sources/gor/Camera/PoseMeasurementValidity.swift',p/'unit-PoseMeasurementValidity.swift')),str(p/'continuity.swift'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 print(subprocess.check_output([str(p/'test')],text=True),end='')
# Compile the actual BGRA sampling function against a byte-buffer boundary.
bridge=r"""import Foundation
let kCVPixelFormatType_32BGRA:UInt32=111
struct LockFlags:OptionSet {let rawValue:Int;static let readOnly=LockFlags(rawValue:1)}
final class CVPixelBuffer {
let ptr:UnsafeMutableRawPointer
init(_ value:UInt8) {ptr=UnsafeMutableRawPointer.allocate(byteCount:64*48*4,alignment:4);ptr.initializeMemory(as:UInt8.self,repeating:value,count:64*48*4)}
deinit{ptr.deallocate()}
}
func CVPixelBufferGetPixelFormatType(_ b:CVPixelBuffer)->UInt32 {111}
func CVPixelBufferLockBaseAddress(_ b:CVPixelBuffer,_ f:LockFlags){}
func CVPixelBufferUnlockBaseAddress(_ b:CVPixelBuffer,_ f:LockFlags){}
func CVPixelBufferGetBaseAddress(_ b:CVPixelBuffer)->UnsafeMutableRawPointer? {b.ptr}
func CVPixelBufferGetWidth(_ b:CVPixelBuffer)->Int {64}
func CVPixelBufferGetHeight(_ b:CVPixelBuffer)->Int {48}
func CVPixelBufferGetBytesPerRow(_ b:CVPixelBuffer)->Int {256}
"""
measure=_s3read(root/'Sources/gor/Camera/PoseFrameQuality.swift').replace('import CoreVideo','')
checks=r"""
for v:UInt8 in [0,20,100,255] {
let b=CVPixelBuffer(v),q=PoseFrameQuality.measure(b,face:CGRect(x:0.2,y:0.2,width:0.5,height:0.5),eyes:[CGPoint(x:0.3,y:0.5),CGPoint(x:0.5,y:0.5)])!
precondition(abs(q.mean-Double(v))<1e-9 && q.contrast<1e-9)
precondition(q.clipped==(v>=245 ? 1:0))
}
print("PASS production BGRA sampler: dark/mid/bright levels, constant-field contrast, eye-region clipped fraction; numeric diagnostics only")
"""
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(bridge+measure+checks)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 print(subprocess.check_output([str(p/'test')],text=True),end='')
_sections=__import__('camera_source')._sections
_helper=_sections.func_text(root,'private func handleHelperFrame(')
_apply=_sections.func_text(root,'private func applyObservation(')
assert _apply.index('if structureReason != 0 {')<_apply.index('let distance=pupilDistanceScale.sample')
assert 'let measuredAngles:[Double]=[selYaw,selPitch,selRoll].compactMap{$0}' in _helper
assert 'angles:measuredAngles' in _helper
assert 'frameQuality:frameQuality,structureReason:structureReason' in _helper
print('PASS C1 production guards absent selected pose instead of substituting0; no semantic low-light/glare threshold introduced')
for path in map(Path,sys.argv[1:]):
 rows=[json.loads(line) for line in _s3read(path).splitlines()]
 usable=[r for r in rows if len(r.get('raw',[]))==6 and len(r.get('filtered',[]))==6]
 conf=[r['confidence'] for r in usable]
 z=[r['raw'][5] for r in usable];fz=[r['filtered'][5] for r in usable]
 pupil=[r for r in usable if len(r.get('pupils',[]))==4]
 spans=[math.hypot(r['pupils'][2]-r['pupils'][0],r['pupils'][3]-r['pupils'][1]) for r in pupil]
 worst=min(usable,key=lambda r:r['raw'][5]);i=rows.index(worst)
 print('OWNER',path.name,'rows',len(rows),'valid6',len(usable),'confidence_min_med_max',min(conf),statistics.median(conf),max(conf),'raw_z_range',min(z),max(z),'filtered_z_range',min(fz),max(fz),'pupil_span_range',min(spans),max(spans),'worst_z_confidence',worst['confidence'])
 print('OWNER worst_z sequence',[(r['t'],r.get('confidence'),r.get('raw',[])[5:] ,r.get('filtered',[])[5:]) for r in rows[max(0,i-1):i+2]])
 print('OWNER lighting/exposure/eyeHold/source_kind labels present',any('frameQuality' in r for r in rows),any('eyeHold' in r for r in rows),any('distanceMode' in r for r in rows))
print('AUDIT low-light/backlight/glare/exposure-change: NOT_PROVEN in old pose-only traces; numeric image-quality capture added, no guessed classification')
print('AUDIT occlusion/hand/second-face: missing or ambiguous structure held; high-confidence semantically wrong single-face measurement NOT_PROVEN')
print('AUDIT fast-head/frame-stall/edge: no arbitrary speed/edge/age cutoff added; existing continuity/latest-only transport retained; native camera cases NOT_PROVEN')

# Compile the actual serialized trace ring, not a reimplementation.
ring=_s3read(root/'Sources/gor/Camera/HeadPose.swift').split('// MARK: - LatestPoseSlot')[0]
probe=r'''import Foundation
let ring=PoseTraceRing.shared,pose=[Double](repeating:0.25,count:6)
ring.append(t:0.1,raw:[],filtered:pose,confidence:0,faceLost:false,outlier:false,reacquire:false,action:"baselineSeed")
ring.append(t:0.2,raw:pose,filtered:pose,confidence:0.8,faceLost:false,outlier:false,reacquire:false,pairedPupils:[1,2,3,4],eyeGeometry:[5,6,7,8],eyeWidths:[9,10],faceBox:[11,12,13,14],landmarkBox:[15,16,17,18],poseAngles:[0.1,0.2,0.3],framePTS:0.15)
ring.append(t:0.3,raw:[],filtered:pose,confidence:0,faceLost:false,outlier:false,reacquire:false,action:"recenter")
ring.append(t:0.4,raw:[],filtered:pose,confidence:0,faceLost:false,outlier:false,reacquire:false,action:"trackingStop")
let url=ring.writeOnQuit()!
let lines=try String(contentsOf:url,encoding:.utf8).split(separator:"\n")
let rows=try lines.map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
precondition(rows.count==4)
precondition(rows.map{$0["resetSequence"] as! Int} == [1,1,2,3])
precondition(rows.map{$0["action"] as! String} == ["baselineSeed","sample","recenter","trackingStop"])
precondition(Set(rows.map{$0["traceSession"] as! String}).count==1)
precondition(UUID(uuidString:rows[0]["traceSession"] as! String) != nil)
precondition(rows[1]["traceBuild"] as! String == BuildID.value())
precondition(rows[1]["eyeWidths"] as! [Double] == [9,10])
precondition(rows[1]["eyeGeometry"] as! [Double] == [5,6,7,8])
precondition(rows[1]["poseAngles"] as! [Double] == [0.1,0.2,0.3])
precondition(rows[1]["framePTS"] as! Double == 0.15)
precondition(rows.allSatisfy{$0["filtered"] as! [Double] == pose})
try FileManager.default.removeItem(at:url)
print("PASS compiled production ring: synchronized geometry/source time, process session/build, baseline/recenter/stop sequence; no pose mutation")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'ring.swift').write_text(ring);(p/'main.swift').write_text(probe)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_s3unit(root/'Sources/gor/GorCore/BuildID.swift',p/'unit-BuildID.swift')),str(p/'ring.swift'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 print(subprocess.check_output([str(p/'test')],text=True),end='')
# This publication is diagnostics only: the production estimator/gate are byte-identical.
historical=(root/'Tests/HeadPose/fixtures/Pose192d.3083622.swift.txt').read_bytes()
assert hashlib.sha256(historical).hexdigest()=='4ea977bf11cc9d181b6d9375d17ec87d151807e1019c7c07a3f489f5c671297a','historical 3083622 fixture bytes changed'
assert _s3read(root/'Sources/gor/Camera/Pose192d.swift').split('/// Dimensionless anatomy consistency,')[0].rstrip().replace('    mutating func interrupt() {if bands==nil {samples=[]}}\n','').replace('mutating func accept(_ filtered:[Double],at t:Double,heldChannels:Set<Int>=[])->[Double]', 'mutating func accept(_ filtered:[Double],at t:Double)->[Double]').replace('            if heldChannels.contains(i) {velocity[i]=0;continue}\n','')+'\n'==historical.decode()
print('PASS distance estimator/eye gate/numeric follow-noise formulas unchanged to3083622; pending-calibration interrupt and explicit channel hold only; new anatomy guard tested separately')

# C1 uses decoded wire arrays, not in-process Vision objects. Compile the
# unchanged production projection at that real boundary and retain its guards.
import c1_projection_audit
c1_projection_audit.run(root)
