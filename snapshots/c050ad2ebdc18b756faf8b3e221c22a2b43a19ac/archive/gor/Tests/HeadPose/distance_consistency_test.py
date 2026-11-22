#!/usr/bin/env python3
"""Compiled anatomy guard, signed valid geometry, optional partial-history owner replay.
No physical-motion labels or live Mac uniform attribution are inferred.
"""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read, materialize as _s3unit
from pathlib import Path
import subprocess,tempfile,json,os,sys
import numpy as np
root=Path(__file__).resolve().parents[2]
swift=os.environ.get('SWIFTC','swiftc')
synthetic=r'''import Foundation
var guarder=PoseDistanceConsistency()
let p=[-60.0,0,60,0],e=p,w=[50.0,50.0]
for _ in 0..<33 {precondition(guarder.accept(pupils:p,eyeGeometry:e,eyeWidths:w,yaw:0,pitch:0))}
precondition(guarder.calibrated)
func rotate(_ p:[Double],yaw:Double,pitch:Double,roll:Double,scale:Double)->[Double] {
 var out:[Double]=[]
 for i in stride(from:0,to:p.count,by:2) {
 let x=p[i],y=p[i+1]
 let x1=cos(yaw)*x,z1 = -sin(yaw)*x
 let y1=cos(pitch)*y-sin(pitch)*z1
 out += [(cos(roll)*x1-sin(roll)*y1)*scale,(sin(roll)*x1+cos(roll)*y1)*scale]
 }
 return out
}
func diameter(_ points:[Double])->Double {
 var best=0.0
 for i in stride(from:0,to:points.count,by:2) {for j in stride(from:0,to:points.count,by:2) {best=max(best,hypot(points[i]-points[j],points[i+1]-points[j+1]))}}
 return best
}
let outline=(0..<32).flatMap{j->[Double] in let a=Double(j)*2*Double.pi/32;return [25*cos(a),10*sin(a)]}
var cases=0
for yd in [-60.0,-30,0,30,60] {for pd in [-45.0,-20,0,20,45] {for rd in [-150.0,-45,0,45,150] {for s in [0.25,0.5,1,2,4] {
 let yaw=yd*Double.pi/180,pitch=pd*Double.pi/180,roll=rd*Double.pi/180
 let points=rotate(p,yaw:yaw,pitch:pitch,roll:roll,scale:s),width=diameter(rotate(outline,yaw:yaw,pitch:pitch,roll:roll,scale:s))
 precondition(guarder.accept(pupils:points,eyeGeometry:points,eyeWidths:[width,width],yaw:yaw,pitch:pitch));cases+=1
}}}}
// Differential co-collapse is rejected even when pupil and eye-outline centres agree.
precondition(!guarder.accept(pupils:[-7,0,7,0],eyeGeometry:[-8,0,8,0],eyeWidths:[17,14],yaw:0,pitch:0))
precondition(!guarder.accept(pupils:[],eyeGeometry:e,eyeWidths:w,yaw:0,pitch:0))
// Exact uniform real retreat/approach remains active through the distance estimator.
var d=PupilDistanceScale()
_=d.sample(left:(-60,0),right:(60,0),yaw:0,fallbackWidth:0)
for scale in [0.5,2.0,0.25,4.0] {
 let pts=p.map{$0*scale}
 precondition(guarder.accept(pupils:pts,eyeGeometry:pts,eyeWidths:w.map{$0*scale},yaw:0,pitch:0))
 let z=d.sample(left:(pts[0],pts[1]),right:(pts[2],pts[3]),yaw:0,fallbackWidth:0).relative
 precondition(abs(z-(scale-1))<1e-12)
}
print("PASS \(cases) signed rigid-plane yaw/pitch/roll and real0.25-4xscale cases; differential co-collapse rejected; approach/retreat scale active")

// Each landmark sensor calibrates independently, never inherits another ratio.
var sensors=PoseDistanceConsistency()
for _ in 0..<33 {precondition(sensors.accept(pupils:p,eyeGeometry:p,eyeWidths:w,yaw:0,pitch:0,landmarkKind:"eye"))}
for _ in 0..<33 {precondition(sensors.accept(pupils:[-40,0,40,0],eyeGeometry:p,eyeWidths:w,yaw:0,pitch:0,landmarkKind:"pupil"))}
precondition(sensors.accept(pupils:p,eyeGeometry:p,eyeWidths:w,yaw:0,pitch:0,landmarkKind:"eye"))
print("PASS independent pupil/outline calibration; existing outline-startup route retained")
// Channel5 holds exact state even with a moving filter/follow tail.
var follow=PoseBacklashFollow(bands:Array(repeating:0,count:6),taus:Array(repeating:0.1,count:6))
_=follow.accept(Array(repeating:0,count:6),at:0)
let moving=follow.accept(Array(repeating:1,count:6),at:0.05)
for i in 1...20 {
 let held=follow.accept(Array(repeating:2,count:6),at:0.05+Double(i)/30,heldChannels:[5])
 precondition(held[5]==moving[5] && held[2]>moving[2])
}
let released=follow.accept(Array(repeating:2,count:6),at:0.75)
precondition(released[5]>moving[5])
print("PASS channel5 exact follow hold during nonzero velocity; other5channels and resumed valid distance active")
'''

with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(synthetic)
 subprocess.run([swift,str(_s3unit(root/'Sources/gor/Camera/Pose192d.swift',p/'unit-Pose192d.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 print(subprocess.check_output([str(p/'test')],text=True),end='')
s=_s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
assert s.count('poseDistanceConsistency=PoseDistanceConsistency()')==2 # declaration and tracking-stop reset, NOT recenter
assert 'pupils:distancePoints,eyeGeometry:eyeGeometry,eyeWidths:eyeWidths,yaw:yaw,pitch:pitch,landmarkKind:landmarkKind' in s
assert 'let heldChannels:Set<Int>=distanceReady ? []:[5]' in s
assert 'distanceConsistent && poseDistanceConsistency.ready(for:landmarkKind)' in s
assert 'distanceValid:distanceReady' in s and 'accept(euro,at:now,heldChannels:heldChannels)' in s
assert 'zRelative=distance.relative;distanceUsedPupils=distance.usedPupils' in s
assert 'distanceMode:distanceConsistent ? (distanceUsedPupils ? (landmarkKind=="pupil" ? 1:2):0):3' in s
print('PASS production guard before pupil-reference mutation; exact channel5 hold with other5channels active; diagnostic distanceMode3')
if len(sys.argv)<2:raise SystemExit(0)
eng=_s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
one='struct OneEuro {'+eng.split('    struct OneEuro {',1)[1].split('    // Synthetic 30 fps',1)[0];one=one.rsplit('}',1)[0]+'}'
continuity=_s3read(root/'Sources/gor/Camera/HeadPose.swift').split('/// Owner-authorized pose-only diagnostics:')[0]
pose=_s3read(root/'Sources/gor/Camera/Pose192d.swift');guard=''
main=r'''import Foundation
func euro(_ ref:Double)->OneEuro {var f=OneEuro(minCutoff:0.35,beta:(2.0-0.35)/ref);f.dCutoff=0.3;return f}
struct Pipeline {
 var consistency=PoseDistanceConsistency(),distance=PupilDistanceScale(),continuity=PoseContinuity(),noise=PoseNoiseCalibration(),follow:PoseBacklashFollow?,previous:[Double]?
 var filters=[euro(1),euro(1),euro(1),euro(0.25),euro(0.25),OneEuro(minCutoff:1/(2*Double.pi*0.8),beta:0)]
 var held=Array(repeating:0.0,count:6),nReject=0
 mutating func reset(preserveAnatomy:Bool=true){let keep=consistency;self=Pipeline();if preserveAnatomy {consistency=keep}}
 mutating func feed(_ x:[String:Any],guarded:Bool)->[Double]? {
 let t=x["t"] as! Double,raw=x["raw"] as! [Double]
 guard raw.count==6, (x["euro"] as! [Double]).count==6 else {follow?.hold(at:t);noise.interrupt();return nil}
 let p=x["pupils"] as! [Double],e=x["eyeGeometry"] as! [Double],w=x["eyeWidths"] as! [Double]
 let angles=x["poseAngles"] as! [Double]
 let good = !guarded || consistency.accept(pupils:p,eyeGeometry:e,eyeWidths:w,yaw:angles[0],pitch:angles[1])
 if !good {nReject+=1}
 let d=distance.sample(left:good ? (p[0],p[1]):nil,right:good ? (p[2],p[3]):nil,yaw:angles[0],fallbackWidth:0,landmarkKind:"pupil")
 var r=raw;r[5]=d.relative
 let heldChannels:Set<Int>=good ? []:[5]
 let c=continuity.accept(r,t:t,heldChannels:heldChannels)
 let euro=(0..<6).map{i in i==5 && !good ? filters[i].hold(at:t):filters[i].filter(c.values[i],at:t)}
 if c.reacquire || !good {noise.interrupt()}else{noise.observe(euro)}
 if follow==nil,let bands=noise.bands {follow=PoseBacklashFollow(bands:bands,taus:Array(repeating:0.1,count:6));_=follow?.accept(previous ?? euro,at:t-1/30)}
 let final=follow?.accept(euro,at:t,heldChannels:heldChannels) ?? euro;previous=final;held=final;return final
 }
}
let text=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)
let rows=try text.split(separator:"\n").map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}.sorted{($0["t"] as! Double)<($1["t"] as! Double)}
var before=Pipeline(),after=Pipeline(),start=false
for x in rows {
 let seq=x["resetSequence"] as! Int,action=x["action"] as! String
 if seq<5 {continue}
 if action != "sample" {before.reset(preserveAnatomy:action=="recenter");after.reset(preserveAnatomy:action=="recenter");start=true;continue}
 guard start else{continue}
 let a=before.feed(x,guarded:false),b=after.feed(x,guarded:true)
 if let a,let b {
 let original=x["filtered"] as! [Double]
 let output:[String:Any]=["t":x["t"]!,"seq":seq,"original":original,"before":a,"after":b,"rejected":after.nReject-before.nReject,"calibrated":after.consistency.calibrated]
 let data=try JSONSerialization.data(withJSONObject:output,options:.sortedKeys);print(String(data:data,encoding:.utf8)!)
 }
}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'types.swift').write_text('\n'.join([one,continuity,pose,guard]));(p/'main.swift').write_text(main)
 subprocess.run([swift,str(p/'types.swift'),str(p/'main.swift'),'-o',str(p/'probe')],check=True)
 output=subprocess.check_output([str(p/'probe'),sys.argv[1]],text=True)
import numpy as np
rows=[json.loads(s) for s in output.splitlines()]
for seq in [5,7,10]:
 a=[x for x in rows if x['seq']==seq];print('SEQ',seq,'N',len(a))
 if not a:continue
 print('original_replay_max_error',np.max(abs(np.array([x['original'] for x in a])-np.array([x['before'] for x in a]))))
 for k in ['before','after']:
  fov=np.clip(135-150*np.array([x[k][5] for x in a]),22.5,157.5)
  print(k,'fov_range',fov.min(),fov.max(),'maxstep',max(abs(np.diff(fov))) if len(fov)>1 else 0,'stepRMS',np.sqrt(np.mean(np.diff(fov)**2)) if len(fov)>1 else 0)
 print('rejects',a[-1]['rejected'])

last={};holds=0
for row in rows:
 p=last.get(row['seq'])
 if p and row['rejected']>p['rejected']:
  holds+=1;assert row['after'][5]==p['after'][5]
 last[row['seq']]=row
assert np.max(abs(np.array([x['before'][:5] for x in rows])-np.array([x['after'][:5] for x in rows])))==0
assert np.max(abs(np.array([x['original'] for x in rows])-np.array([x['before'] for x in rows])))<1e-5
print('PASS partial-history replay original reproduction<1e-5; comparable rejected-distance exact holds',holds,'other5channels byte-identical as Doubles')
print('LIMIT partial-history replay starts mid-session and does not exercise the new startup arming gate; see activation_distance_arming_test.py. No physical labels; native Mac NOT_RUN')
