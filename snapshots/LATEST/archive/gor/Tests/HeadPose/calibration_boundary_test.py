#!/usr/bin/env python3
"""Compile actual estimator. Captured rows are partial history, not labeled stillness."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read, materialize as _s3unit
from pathlib import Path
import json,subprocess,tempfile,os,sys
root=Path(__file__).resolve().parents[2]
source=_s3read(root/'Sources/gor/Camera/Pose192d.swift')
old=subprocess.check_output(['git','show','15d5b607c5bb5b22cd77070a04f14b46b2a3b48c:archive/gor/Sources/gor/Stereo/Pose192d.swift'],text=True).replace('PoseNoiseCalibration','OldPoseNoiseCalibration')
lines=['import Foundation',r'''
var p=PoseNoiseCalibration()
for i in 0..<32 {p.observe(Array(repeating:Double(i)/100,count:6))}
precondition(p.bands==nil);p.interrupt()
for i in 0..<32 {p.observe(Array(repeating:Double(i)/1000,count:6))}
precondition(p.bands==nil)
p.observe(Array(repeating:0.032,count:6));let learned=p.bands!
p.interrupt();precondition(p.bands! == learned)
print("PASS invalid boundary clears only pending calibration; full33fresh samples required; completed bands retained")
var old=OldPoseNoiseCalibration(),candidate=PoseNoiseCalibration()
var oldCount=0,newCount=0,oldDone=false,newDone=false
var oldStart=0.0,newStart=0.0
''']
if len(sys.argv)>1:
 rows=[json.loads(s) for s in _s3read(Path(sys.argv[1])).splitlines()]
 rows=[r for r in rows if r['traceSession']=='EFE538A4-BE1E-4E0D-BF6F-255BC7AA4BF3' and r['resetSequence']==5]
 firstbands=next(n for n,r in enumerate([r for r in rows if len(r['euro'])==6]) if r['bands'])
 print('PROVENANCE installed bands present at retained accepted index',firstbands,'therefore exact original calibration not recoverable')
 for r in rows:
  t=r['t']
  if len(r['euro'])!=6 or r['reacquire']:
   lines.append('candidate.interrupt();if !newDone {newCount=0;newStart=0}')
  if len(r['euro'])==6:
   v=','.join(str(x) for x in r['euro']);lines.append(f'if oldCount==0 {{oldStart={t}}};oldCount+=1;old.observe([{v}])')
   lines.append(f'if !oldDone,let b=old.bands {{print("REPLAY_OLD window_s",{t}-oldStart,"bands",b);oldDone=true}}')
   if not r['reacquire']:
    lines.append(f'if newCount==0 {{newStart={t}}};newCount+=1;candidate.observe([{v}])')
    lines.append(f'if !newDone,let b=candidate.bands {{print("REPLAY_NEW window_s",{t}-newStart,"bands",b);precondition(abs(({t}-newStart)-1.7970240000868216)<1e-7);newDone=true}}')
 lines.append('precondition(oldDone && newDone)')
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'old.swift').write_text('import Foundation\nstruct OldPoseNoiseCalibration'+old.split('struct OldPoseNoiseCalibration',1)[1]);(p/'main.swift').write_text('\n'.join(lines));subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_s3unit(root/'Sources/gor/Camera/Pose192d.swift',p/'unit-Pose192d.swift')),str(p/'old.swift'),str(p/'main.swift'),'-o',str(p/'test')],check=True);print(subprocess.check_output([str(p/'test')],text=True),end='')
s=_s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
assert s.count('self.poseContinuity.faceLost();self.poseNoise.interrupt()')==2
assert s.count('poseFollow?.hold(at:t);poseNoise.interrupt()')==2
assert 'if continuity.reacquire || !distanceReady {poseNoise.interrupt()} else {poseNoise.observe(euro)}' in s
assert 'distanceReady=distanceConsistent && poseDistanceConsistency.ready(for:landmarkKind)' in s
current_noise=source.split('struct PoseNoiseCalibration',1)[1].split('/// Dimensionless anatomy consistency,',1)[0].rstrip()
old_noise=old.split('struct OldPoseNoiseCalibration',1)[1].rstrip()
assert current_noise.replace('    mutating func interrupt() {if bands==nil {samples=[]}}\n','')==old_noise
print('PASS loss/structure/eye-held/reacquire production boundaries wired; estimator formula/noise thresholds/native roll unchanged; no still-head or gap-only stall guarantee')
