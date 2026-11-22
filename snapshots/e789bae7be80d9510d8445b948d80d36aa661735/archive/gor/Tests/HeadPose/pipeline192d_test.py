#!/usr/bin/env python3
"""192d actual Swift primitives and existing one-euro, synthetic first calibration.
Owner G1/G2/G5: NOT_MEASURED no owner trace. No camera/playback acceptance.
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
import os,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[2]
s=_s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift');a=s.index('    struct OneEuro {');b=s.index('    // Synthetic 30 fps',a)
euro=s[a:b].replace('    struct OneEuro {','struct OneEuro {',1)
main=r'''import Foundation
var distance=PupilDistanceScale()
for i in 0..<181 {
 let pitch=Double(i-90)*Double.pi/180
 let sample=distance.sample(left:(100,100),right:(160,100),yaw:0,fallbackWidth:140,focalPixels:1000,ipdMM:60)
 precondition(sample.relative==0 && sample.millimetres==1000 && sample.usedPupils)
 _=pitch
}
let a=Double.pi/6
let rolled=distance.sample(left:(100,100),right:(100+60*cos(a),100+60*sin(a)),yaw:0,fallbackWidth:140)
precondition(abs(rolled.relative)<1e-12)
let turned=distance.sample(left:(100,100),right:(100+60*cos(a),100),yaw:a,fallbackWidth:140*cos(a))
precondition(abs(turned.relative)<1e-12)
let near=distance.sample(left:(100,100),right:(172,100),yaw:0,fallbackWidth:168,focalPixels:1000,ipdMM:60)
precondition(abs(near.relative-0.2)<1e-12)
let fallback=distance.sample(left:nil,right:nil,yaw:0,fallbackWidth:168)
precondition(abs(fallback.relative-near.relative)<1e-12)
print("PASS D2 actual Swift nod/yaw/roll pupil invariance, distance approach and matched fallback")
var late=PupilDistanceScale()
_=late.sample(left:nil,right:nil,yaw:0,fallbackWidth:100)
let boxNear=late.sample(left:nil,right:nil,yaw:0,fallbackWidth:120)
let acquired=late.sample(left:(0,0),right:(72,0),yaw:0,fallbackWidth:120)
precondition(abs(boxNear.relative-acquired.relative)<1e-12)
print("PASS initial missing-distance hold to first pupil acquisition keeps zoom continuous")
var euro=OneEuro(minCutoff:0.35,beta:1.65)
var calibration=PoseNoiseCalibration(),state:UInt64=37
func noise()->Double {state=state &* 6364136223846793005 &+ 1;return (Double(state>>11)/9007199254740992.0-0.5)*0.02}
var filtered:[Double]=[]
for i in 0..<300 {
 let x=euro.filter(noise(),at:Double(i)/30);filtered.append(x)
 calibration.observe(Array(repeating:x,count:6))
}
let band=calibration.bands![0]
precondition(band>0 && band.isFinite)
print("MEAS synthetic startup online band=\(band), fixed critical tau_s=0.1; owner noise envelope NOT_MEASURED")
var follow=PoseBacklashFollow(bands:[band],taus:[0.1]);_=follow.accept([0],at:0)
var last=0.0,maxStep=0.0,outputs:[Double]=[]
for i in 1...300 {
 let x=follow.accept([filtered[i-1]],at:Double(i)/30)[0];outputs.append(x);maxStep=max(maxStep,abs(x-last));last=x
}
func rms2(_ a:[Double])->Double {var sum=0.0;for i in 2..<a.count {let d=a[i]-2.0*a[i-1]+a[i-2];sum+=d*d};return sqrt(sum/Double(a.count-2))}
print("MEAS synthetic still output_rms2=\(rms2(outputs)) filtered_noise_floor_rms2=\(rms2(filtered)) maxStep=\(maxStep) band=\(band)")
precondition(rms2(outputs)<=rms2(filtered) && maxStep<=band)
for channel in 0..<6 {
 var f=PoseBacklashFollow(bands:[band],taus:[0.1]);_=f.accept([0],at:0)
 var result:[Double]=[]
 for i in 1...600 {result.append(f.accept([min(0.2,Double(i)*band*0.25)],at:Double(i)/30)[0])}
 let peak=zip(result.dropFirst(),result).map{abs($0-$1)}.max()!
 precondition(peak<=band)
 var step=PoseBacklashFollow(bands:[band],taus:[0.1]);_=step.accept([0],at:0)
 var t90=Double.infinity
 for i in 1...300 {let x=step.accept([0.5],at:Double(i)/30)[0];if x>=0.45 && !t90.isFinite {t90=Double(i)/30}}
 print("MEAS channel\(channel) synthetic slow maxStep=\(peak) band=\(band) t90_s=\(t90)")
 precondition(t90.isFinite)
}
var tilt=PoseBacklashFollow(bands:[band],taus:[0.1]);_=tilt.accept([0],at:0)
var held:[Double]=[]
for i in 1...600 {let x=tilt.accept([20*Double.pi/180],at:Double(i)/30)[0];if i>300 {held.append(x)}}
precondition(held.max()!-held.min()!<1e-12 && abs(held.last!-20*Double.pi/180)<=band+1e-12)
print("MEAS held20deg settled_deg=\(held.last!*180/Double.pi) band_deg=\(band*180/Double.pi), stable range=\(held.max()!-held.min()!)")
// Full production continuity + per-channel one-euro + backlash/critical latency.
for j in 0..<6 {
 var c=PoseContinuity(),e=OneEuro(minCutoff:j==5 ? 1/(2*Double.pi*0.8):0.35,beta:j==5 ? 0:1.65/(j<3 ? 1:0.25))
 e.dCutoff=0.3
 var f=PoseBacklashFollow(bands:[band],taus:[0.1]),t90=Double.infinity
 for i in 0..<360 {
  let t=Double(i)/30,input=i<90 ? 0.0:0.5
  var channels=Array(repeating:0.0,count:6);channels[j]=input
  let out=f.accept([e.filter(c.accept(channels,t:t).values[j],at:t)],at:t)[0]
  if i>=90 && out>=0.45 && !t90.isFinite {t90=t-3}
 }
 precondition(t90.isFinite)
 print("MEAS full_pipeline synthetic channel\(j) step_t90_s=\(t90), includes continuity and existing one-euro; NOT camera latency")
}
// Mirrored physical approach/retreat use the exact same production distance filter.
func distanceStep(_ sign:Double)->[Double] {
 var c=PoseContinuity(),e=OneEuro(minCutoff:1/(2*Double.pi*0.8),beta:0)
 e.dCutoff=0.3
 var f=PoseBacklashFollow(bands:[band],taus:[0.1]),out:[Double]=[]
 for i in 0..<360 {
  let t=Double(i)/30,z=i<90 ? 0.0:sign*0.2
  var channels=Array(repeating:0.0,count:6);channels[5]=z
  out.append(f.accept([e.filter(c.accept(channels,t:t).values[5],at:t)],at:t)[0])
 }
 return out
}
let toward=distanceStep(1),away=distanceStep(-1)
precondition(zip(toward,away).allSatisfy{abs($0+$1)<1e-12})
precondition(toward.last!>0.19 && away.last! < -0.19)
print("PASS production continuity/OneEuro/backlash mirrored approach and retreat: identical lag, settling and noise response")
print("PASS synthetic G1-G4 primitives. Owner G1/G2/G5 NOT_MEASURED no_owner_trace")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'euro.swift').write_text('import Foundation\n'+euro);(p/'main.swift').write_text(main)
 (p/'continuity.swift').write_text(_s3read(root/'Sources/gor/Camera/HeadPose.swift').split('/// Owner-authorized pose-only diagnostics:')[0])
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_s3unit(root/'Sources/gor/Camera/Pose192d.swift',p/'unit-Pose192d.swift')),str(p/'euro.swift'),str(p/'continuity.swift'),str(p/'main.swift'),'-o',str(p/'test')],check=True,text=True)
 print(subprocess.check_output([str(p/'test')],text=True),end='')
assert 'StationaryScaleHold' not in _s3read(root/'Sources/gor/Camera/HeadPose.swift')
assert 'cinema_step' not in _s3read(root/'Resources/vendor/mpv/scripts/vr180-look.lua')
assert 'let headZ = 0.0' in _s3read(_pp_split().path(root,'PPController_Features.swift'))
print('PASS production wiring: one zoom carrier, no Lua cinema/fast mode, no StationaryScaleHold')
