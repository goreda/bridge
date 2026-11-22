#!/usr/bin/env python3
"""Actual production ingestion: acquisition changes must not publish startup zoom."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read, materialize as _s3unit
from pathlib import Path
import subprocess,tempfile,os
root=Path(__file__).resolve().parents[2]
fixture=root/'Tests/HeadPose/session_baseline_test.py'
ns={'__file__':str(fixture)}
exec(compile(_s3read(fixture).split('main=main.replace',1)[0],str(fixture),'exec'),ns)
main=ns['main'].split('let p=Probe();var samples:',1)[0]+r'''
let p=Probe();var samples:[HeadPose]=[];p.onPoseUpdate={samples.append($0)}
p.startHead()
p.sample(100,yaw:0,pitch:0,roll:0.1)
// Camera/landmark acquisition converges, not physical approach. The existing
// anatomy calibration is still learning for its shipped33samples.
for _ in 0..<31 {p.sample(120,yaw:0,pitch:0,roll:0.2)}
check(samples.count==32,"orientation remains live during distance acquisition")
check(samples.allSatisfy{abs($0.zOffset)<1e-12},"uncalibrated acquisition cannot zoom at head-enable")
p.sample(120,yaw:0,pitch:0,roll:0.2)
check(samples.last!.zOffset==0,"first calibrated distance seeds neutral1x, not early noisy span")
for _ in 0..<45 {p.sample(120,yaw:0,pitch:0,roll:0.2)}
check(abs(samples.last!.zOffset)<1e-12,"static head stays at1x after arming")
for _ in 0..<45 {p.sample(144,yaw:0,pitch:0,roll:0.2)}
check(samples.last!.zOffset>0.1,"actual later approach still zooms")
p.startHead();let n=samples.count
for _ in 0..<33 {p.sample(150,yaw:0,pitch:0,roll:0.2)}
check(samples.count==n+33 && samples.last!.zOffset==0,"warm shared-camera re-enable re-arms distance without old zoom")
print("PASS actual HeadTracker ingestion acquisition gate; native camera transition NOT_RUN")
'''
main=main.replace('CAPTURE_ARGUMENT',',capturedAt:capturedAt')
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_s3unit(root/'Sources/gor/Camera/Pose192d.swift',p/'unit-Pose192d.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
