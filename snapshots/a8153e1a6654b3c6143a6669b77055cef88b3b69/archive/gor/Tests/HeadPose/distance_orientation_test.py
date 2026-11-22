#!/usr/bin/env python3
"""Compile actual distance estimator and previous published source as a mutant."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read, materialize as _s3unit
import os,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[2]
old=subprocess.check_output(['git','show','f4687297cf5ee2ef4a3ade5f5fdb52f2e5c8f05a:archive/gor/Sources/gor/Stereo/Pose192d.swift'],text=True).split('///192d D1')[0]
old=old.replace('struct PupilDistanceScale','struct OldPupilDistanceScale').replace('ipdMM:Double?=nil)','ipdMM:Double?=nil,landmarkKind:String="pupil")')
main=r'''import Foundation
var now=PupilDistanceScale(),old=OldPupilDistanceScale()
func points(_ deg:Double,_ span:Double)->((Double,Double),(Double,Double)) {
 let r=deg*Double.pi/180;return ((320,240),(320+span*cos(r),240+span*sin(r)))
}
let a=points(0,60);_=now.sample(left:a.0,right:a.1,yaw:0,fallbackWidth:140)
_=old.sample(left:a.0,right:a.1,yaw:0,fallbackWidth:140)
var peak=0.0,oldPeak=0.0
for axis in ["roll","pitch","yaw"] {for deg in [-30.0,-20,-10,0,10,20,30] {
 let yaw=axis=="yaw" ? deg*Double.pi/180:0
 for mode in ["pupil","eye","missing","pupil"] {
  let span=(mode=="eye" ? 56.0:60.0)*cos(yaw)
  let p=points(axis=="roll" ? deg:0,span)
  let width=140*cos(deg*Double.pi/180)+190*abs(sin(deg*Double.pi/180))
  let l:(Double,Double)?=mode=="missing" ? nil:p.0,r:(Double,Double)?=mode=="missing" ? nil:p.1
  let n=now.sample(left:l,right:r,yaw:yaw,fallbackWidth:width,landmarkKind:mode)
  let o=old.sample(left:l,right:r,yaw:yaw,fallbackWidth:width,landmarkKind:mode)
  peak=max(peak,abs(n.relative));oldPeak=max(oldPeak,abs(o.relative))
  precondition(abs(n.relative)<1e-12,"orientation or landmark switching changed distance zoom")
 }
}}
print("MEAS signed roll/pitch/yaw +/-10/20/30 with pupil/eye/missing switching: corrected max_relative_zoom=\(peak), previous_source_mutant=\(oldPeak)")
precondition(oldPeak>0.05,"regression mutant was not killed")
var missing=PupilDistanceScale(),oldMissing=OldPupilDistanceScale()
_=missing.sample(left:a.0,right:a.1,yaw:0,fallbackWidth:140)
_=oldMissing.sample(left:a.0,right:a.1,yaw:0,fallbackWidth:140)
for deg in [-30.0,-20,-10,0,10,20,30] {
 let r=deg*Double.pi/180,width=140*cos(r)+190*abs(sin(r))
 let n=missing.sample(left:nil,right:nil,yaw:0,fallbackWidth:width)
 let o=oldMissing.sample(left:nil,right:nil,yaw:0,fallbackWidth:width)
 precondition(abs(n.relative)<1e-12)
 print("MEAS missing-landmark signed tilt\(deg): corrected_zoom=\(n.relative), previous_box_zoom=\(o.relative)")
}
for deg in [-30.0,30] {
 let p=points(deg,72)
 let n=now.sample(left:p.0,right:p.1,yaw:0,fallbackWidth:160,landmarkKind:"pupil")
 precondition(abs(n.relative-0.2)<1e-12)
 print("PASS simultaneous real20percent approach and signed tilt\(deg) preserves relative zoom\(n.relative)")
}
for deg in [-30.0,-20,-10,0,10,20,30] {
 var gate=PoseEyeMeasurementGate(),d=PupilDistanceScale(),held=[Double](repeating:0,count:6)
 let normal=points(deg,60)
 for i in 0..<30 {if gate.accept([0.3,0.31]) {let z=d.sample(left:normal.0,right:normal.1,yaw:0,fallbackWidth:140).relative;held=[0,0,deg,0,0,z]};_=i}
 let baseline=held
 for i in 0..<12 {
  let eye=i%2==0 ? [Double]():[0.02,0.015]
  if gate.accept(eye) {held=[0.5,-0.5,deg+12,0.1,0.1,d.sample(left:(0,0),right:(12,4),yaw:0.3,fallbackWidth:80,landmarkKind:"eye").relative]}
  precondition(held==baseline,"blink/collapsed outline mutated pose or zoom")
 }
 precondition(gate.accept([0.3,0.31]))
 precondition(abs(d.sample(left:normal.0,right:normal.1,yaw:0,fallbackWidth:140).relative)<1e-12)
 print("PASS signed blink\(deg):12frames pupil dropout/collapsed outline hold all6channels, reopen no distance jump")
}
now.reset();let q=points(20,60)
precondition(now.sample(left:q.0,right:q.1,yaw:0,fallbackWidth:190).relative==0)
print("PASS recenter zero, missing landmarks hold last distance instead of box-driven false zoom; owner trace NOT_MEASURED")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'old.swift').write_text(old);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_s3unit(root/'Sources/gor/Camera/Pose192d.swift',p/'unit-Pose192d.swift')),str(p/'old.swift'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 print(subprocess.check_output([str(p/'test')],text=True),end='')
s=_s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
assert 'let hasPupils=pupils.0 != nil && pupils.1 != nil' in s
assert 'leftPupil ?? distanceFace?.landmarks?.leftEye' not in s
gate_start=s.index('if let eyes=eyeApertures,!poseEyeGate.accept(eyes) {')
gate_end=s.index('var distanceReady=',gate_start)
eye_gate=s[gate_start:gate_end]
assert gate_end<s.index('let distance=pupilDistanceScale.sample')
assert 'poseFollow?.hold(at:t);poseNoise.interrupt()' in eye_gate and 'eyeHold:true' in eye_gate
assert eye_gate.rstrip().endswith('return\n        }')
assert 'poseFollow?.hold(at:t)' in s
assert 'landmarkKind != "pupil" && pupilDistanceScale.hasPupilReference' in s
print('PASS production chooses paired same-kind landmarks, never independently mixed eye/pupil sensors')
