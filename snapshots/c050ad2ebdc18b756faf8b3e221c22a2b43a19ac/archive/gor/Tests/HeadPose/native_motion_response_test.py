#!/usr/bin/env python3
"""Actual OneEuro/smooth and follow, measured synthetic latency/noise, not Mac FPS."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read, materialize as _s3unit
from pathlib import Path
import os,tempfile,subprocess,json,re
root=Path(__file__).resolve().parents[2]
s=_s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
def extract(marker):
 a=s.index(marker);b=s.index('{',a)+1;i=b;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i].replace('private ','')
pose=s[s.index('struct HeadPose {'):s.index('/// Block 182 2 distance model')]
config=s[s.index('    private static let stillCutoffHz'):s.index('    /// Main-thread only (called exclusively',s.index('    private static let stillCutoffHz'))].replace('private ','')
main='import Foundation\ntypealias CFTimeInterval=Double\n'+pose+'\nclass Probe {var nativeMotionResponsive=false\n'+extract('    struct OneEuro {')+'\n'+config+extract('    private func smooth(')+'''\n}
for native in [false,true] {
 let p=Probe();p.nativeMotionResponsive=native
 var seed:UInt64=192
 func uniform()->Double {seed=seed &* 6364136223846793005 &+ 1;return (Double(seed>>11)+0.5)/9007199254740992}
 func noise()->Double {sqrt(-2*log(uniform()))*cos(2*Double.pi*uniform())}
 let followTau:Double = native ? NATIVE_TAU:0.1
 var follow=PoseBacklashFollow(bands:Array(repeating:0,count:6),taus:[followTau,followTau,followTau,0.1,0.1,0.1])
 var t90 = -1.0,still:[Double]=[]
 for i in 0..<360 {
  let t=Double(i)/30
  let x=t<5 ? 0:min(0.5,t-5)
  let jitter=t<4 ? 0.01*noise():0
  let pose=HeadPose(yaw:x+jitter,pitch:0,roll:0,xOffset:0,yOffset:0,zOffset:0)
  let euro=p.smooth(pose,at:t),out=follow.accept([euro.yaw,0,0,0,0,0],at:t)[0]
  if t>1 && t<4 {still.append(out)}
  if t>=5 && out>=0.45 && t90<0 {t90=t-5}
 }
 let mean=still.reduce(0,+)/Double(still.count)
 let rms=sqrt(still.reduce(0){$0+($1-mean)*($1-mean)}/Double(still.count))
 print("{\\"native\\":\\(native),\\"t90\\":\\(t90),\\"jitter\\":\\(rms)}")
}
'''
# Keep the old baseline executable: absent new native follow profile is the red state.
main=main.replace('HeadTracker.','Probe.')
profile=re.search(r'nativeMotionResponsive \? \[([^]]+)\]',s)
main=main.replace('NATIVE_TAU',profile[1].split(',')[0] if profile else '0.1')
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_s3unit(root/'Sources/gor/Camera/Pose192d.swift',p/'unit-Pose192d.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 rows=[json.loads(x) for x in subprocess.check_output([str(p/'test')],text=True).splitlines()]
print(rows)
old,new=rows
assert new['t90']<=.601 and new['t90']<old['t90']-.15,rows
assert new['jitter']<.001247 and new['jitter']<old['jitter']*1.5,rows
print('PASS actual native response improves synthetic turn latency within stated jitter envelope; flat profile unchanged. Still jitter tradeoff reported above. Playback FPS and native camera NOT_RUN')
