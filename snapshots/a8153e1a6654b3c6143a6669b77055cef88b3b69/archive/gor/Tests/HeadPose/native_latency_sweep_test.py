#!/usr/bin/env python3
"""Actual OneEuro/smooth and follow, measured synthetic latency/noise, not Mac FPS."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read, materialize as _s3unit
from pathlib import Path
import os,tempfile,subprocess,json
root=Path(__file__).resolve().parents[2]
s=_s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
def extract(marker):
 a=s.index(marker);b=s.index('{',a)+1;i=b;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i].replace('private ','')
pose=s[s.index('struct HeadPose {'):s.index('/// Block 182 2 distance model')]
config=s[s.index('    private static let stillCutoffHz'):s.index('    /// Main-thread only (called exclusively',s.index('    private static let stillCutoffHz'))].replace('private ','')
# 194q SWEEP (compiled with Swift6 on Linux): tabulates native turn cutoff x speed-filter cutoff
# x follow tau against synthetic t90 and still jitter, so a value is chosen from measurements
# instead of guessed. Exploratory rows have a broad safety cap; the selected product
# profile has the tighter native_motion_response_test regression envelope.
import itertools
base=extract('    private func smooth(')
def probe_source(turn,speed,tau):
 smooth=base.replace('nativeMotionResponsive ? 4.0:Self.turnCutoffHz',str(turn)).replace('nativeMotionResponsive ? 0.3:Self.speedFilterCutoffHz',str(speed))
 assert smooth!=base or (str(turn)=='4.0' and str(speed)=='0.3')
 return smooth,tau
body=r"""
var seed:UInt64=192
func uniform()->Double {seed=seed &* 6364136223846793005 &+ 1;return (Double(seed>>11)+0.5)/9007199254740992}
func noise()->Double {sqrt(-2*log(uniform()))*cos(2*Double.pi*uniform())}
let p=Probe();p.nativeMotionResponsive=true
var follow=PoseBacklashFollow(bands:Array(repeating:0,count:6),taus:[TAU,TAU,TAU,0.1,0.1,0.1])
var t90 = -1.0,still:[Double]=[]
for i in 0..<360 {
 let t=Double(i)/30,x=t<5 ? 0:min(0.5,t-5),jitter=t<4 ? 0.01*noise():0
 let pose=HeadPose(yaw:x+jitter,pitch:0,roll:0,xOffset:0,yOffset:0,zOffset:0)
 let euro=p.smooth(pose,at:t),out=follow.accept([euro.yaw,0,0,0,0,0],at:t)[0]
 if t>1 && t<4 {still.append(out)}
 if t>=5 && out>=0.45 && t90<0 {t90=t-5}
}
let mean=still.reduce(0,+)/Double(still.count)
let rms=sqrt(still.reduce(0){$0+($1-mean)*($1-mean)}/Double(still.count))
print("{\"t90\":\(t90),\"jitter\":\(rms)}")
"""
pose_=pose;cfg=config
rows=[]
for turn,speed,tau in itertools.product((4.0,6.0,8.0),(0.3,0.6,1.0),(0.04,0.025)):
 smooth,_=probe_source(turn,speed,tau)
 main='import Foundation\ntypealias CFTimeInterval=Double\n'+pose_+'\nclass Probe {var nativeMotionResponsive=false\n'+extract('    struct OneEuro {')+'\n'+cfg+smooth+'\n}\n'+body.replace('TAU',str(tau))
 main=main.replace('HeadTracker.','Probe.')
 with tempfile.TemporaryDirectory() as td:
  p=Path(td);(p/'main.swift').write_text(main)
  subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_s3unit(root/'Sources/gor/Camera/Pose192d.swift',p/'unit-Pose192d.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
  r=json.loads(subprocess.check_output([str(p/'test')],text=True).splitlines()[-1])
 rows.append((turn,speed,tau,r['t90'],r['jitter']));print('turn',turn,'speed',speed,'tau',tau,'t90',r['t90'],'jitter',r['jitter'])
shipped=[r for r in rows if r[:3]==(4.0,0.3,0.04)][0]
print('194p shipped point:',shipped,'- the cost of any faster row is its jitter column vs this one')
assert all(r[4]<max(.0030,shipped[4]*3) for r in rows),'jitter envelope exceeded'
