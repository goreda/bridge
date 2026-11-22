#!/usr/bin/env python3
"""Compile actual pose ingestion + baseline/recenter methods; shared camera lifecycle spy.
No physical camera or Mac validation.
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read, materialize as _s3unit
from pathlib import Path
import subprocess,tempfile,os
root=Path(__file__).resolve().parents[2]
s=_s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
def extract(marker):
 a=s.index(marker);b=s.index('{',a)+1;depth=1;i=b
 while depth:depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i]+'\n'
pose=s[s.index('struct HeadPose {'):s.index('/// Block 182 2 distance model')]
state=s[s.index('    private var poseContinuity='):min(s.index('    func beginPoseSession()') if '    func beginPoseSession()' in s else len(s),s.index('    func recenter() {',s.index('    private var poseContinuity=')))].split('    ///',1)[0].replace('private ','')
reset=extract('    func beginPoseSession()') if '    func beginPoseSession()' in s else ''
main=r'''import Foundation
var clock=0.0
func CACurrentMediaTime()->Double {clock}
enum BuildID {static func value()->String {"test"}}
enum GeomTrace {static let on=false;static func log(_ k:String,_ v:String){}}
enum VRDistance {static func distanceMM(hfovDeg:Double,boxWidthNorm:Double)->Double {0}}
struct F {mutating func filter(_ x:Double,at:Double)->Double {x}}
'''+pose+_s3read(root/'Sources/gor/Camera/HeadPose.swift')+'''
final class Probe {
static let poseHoldLock=true
'''+state+r'''
static let xOffsetSign=1.0,yOffsetSign=1.0
var fD=F(),onPoseUpdate:((HeadPose)->Void)?,resetCalls=0
func resetFilters(){resetCalls+=1}
func smooth(_ p:HeadPose,at:Double,distanceValid:Bool)->HeadPose {p}
'''+reset+extract('    func recenter() {')+extract('    private func applyObservation(').replace('private func','func')+r'''
func sample(_ span:Double,yaw:Double=0.2,pitch:Double=0.1,roll:Double=0.5,kind:String="pupil",capturedAt:Double?=nil) {
 clock+=1.0/30
 applyObservation(box:CGRect(x:0.2,y:0.3,width:0.4,height:0.5),yaw:yaw,pitch:pitch,roll:roll,pupilLeft:(-span/2,0),pupilRight:(span/2,0),landmarkKind:kind,eyeApertures:[0.3,0.3],eyeGeometry:[-span/2,0,span/2,0],eyeWidths:[span/2,span/2]CAPTURE_ARGUMENT)
}
func startHead(){
'''+('beginPoseSession()' if reset else '// OLD: camera consumer start did not reset the pose session')+r'''
}
}
func check(_ ok:Bool,_ text:String){precondition(ok,text);print("PASS "+text)}
let p=Probe();var samples:[HeadPose]=[];p.onPoseUpdate={samples.append($0)}
// Camera has already run for blink before head tracking begins.
for _ in 0..<40 {p.sample(120)}
for _ in 0..<90 {p.sample(160)}
p.startHead()
check(!p.pupilDistanceScale.hasPupilReference && p.poseFollow==nil && p.previousPoseOutput==nil,"session drops old distance reference and old filter-follow tail")
p.sample(160)
check(abs(samples.last!.zOffset)<1e-12,"shared-camera head enable first fresh frame is 1x zoom, not old pupil reference")
check(abs(samples.last!.yaw)<1e-12 && abs(samples.last!.pitch)<1e-12,"head enable seeds current viewing direction")
check(abs(samples.last!.roll-0.5)<1e-12,"head enable preserves physical roll")
for _ in 0..<32 {p.sample(160)} // arm the distance sensor before testing motion
for _ in 0..<45 {p.sample(176)}
check(samples.last!.zOffset>0.05,"approach remains active after enable")
p.recenter();check(samples.last!.zOffset==0 && samples.last!.roll==0.5,"Shift+R immediate neutral distance preserves physical roll")
check(!p.pupilDistanceScale.hasPupilReference && !p.poseDistanceConsistency.calibrated,"Shift+R requests new distance and geometry calibration")
let n=samples.count
p.sample(176)
check(samples.count==n+1 && abs(samples.last!.zOffset)<1e-12,"first fresh post-reset frame remains neutral and callback live")
for _ in 0..<32 {p.sample(176)} // post-recenter distance acquisition remains neutral
for _ in 0..<90 {p.sample(158.4)}
check(samples.count>n+80 && samples.last!.zOffset < -0.05,"post-reset retreat resumes without toggle")
for _ in 0..<90 {p.sample(193.6)}
check(samples.last!.zOffset>0.05,"post-reset approach resumes without toggle")
check(p.onPoseUpdate != nil,"reset never detaches pose callback")
// No prior observation: reset must still invalidate state and seed the next frame.
p.lastBoundingBox=nil;p.recenter();p.sample(193.6)
check(abs(samples.last!.zOffset)<1e-12,"reset with no current face defers fresh neutral baseline")
// Capture began before reset, but its main-queue delivery arrives after reset.
let q=Probe();var fresh:[HeadPose]=[];q.onPoseUpdate={fresh.append($0)}
q.sample(120);let oldCapture=clock;clock+=1;q.startHead()
let prior=fresh.count;q.sample(120,capturedAt:oldCapture)
check(fresh.count==prior,"pre-reset captured frame cannot mutate new session or seed stale baseline")
q.sample(160)
check(fresh.count==prior+1 && fresh.last!.zOffset==0,"first current frame seeds new neutral baseline after stale delivery rejected")
// A temporarily absent pupil must hold distance, not freeze valid head orientation.
for _ in 0..<32 {p.sample(193.6)} // establish a calibrated pupil reference before fallback
let beforeOutline=samples.count,zBefore=samples.last!.zOffset
for _ in 0..<90 {p.sample(193.6,roll:0.8,kind:"eye")}
check(samples.count==beforeOutline+90,"pupil-to-outline fallback keeps all orientation callbacks alive")
check(abs(samples.last!.roll-0.8)<0.01 && abs(samples.last!.zOffset-zBefore)<1e-12,"outline fallback moves roll while retaining exact pupil distance")
for _ in 0..<90 {p.sample(212.96,roll:0.9)}
check(samples.last!.zOffset>0.05,"pupil distance resumes after outline-only frames")
'''
main=main.replace('CAPTURE_ARGUMENT',',capturedAt:capturedAt' if 'framePTS:Double = -1,capturedAt:' in s else '')
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_s3unit(root/'Sources/gor/Camera/Pose192d.swift',p/'unit-Pose192d.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)

_sections_spec=_iu.spec_from_file_location('session_baseline_sections',root/'Tests/Structure/section_source.py')
_sections=_iu.module_from_spec(_sections_spec);_sections_spec.loader.exec_module(_sections)
consumer=_sections.func_text(root,'private func updateCaptureConsumers()',within='VR180Controller.swift')
assert consumer.index('HeadTracker.shared.beginPoseSession()') < consumer.index('HeadTracker.shared.onPoseUpdate') < consumer.index('HeadTracker.shared.start(owner: 1)')
print('PASS actual head consumer begins independent pose session before callback/camera attach')
