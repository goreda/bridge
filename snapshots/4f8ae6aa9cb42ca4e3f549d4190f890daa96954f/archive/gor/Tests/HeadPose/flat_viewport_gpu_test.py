#!/usr/bin/env python3
"""Actual Swift publisher -> real Lua-published GLSL -> EGL pixels. Not Mac/camera proof."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile,json,math,re
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
s=(_pp_split().path(root,'PPController_Features.swift')).read_text()
a=s.index('    private func applyHeadPose(');b=s.index('\n    func recenterHeadTracking',a)
constants='\n'.join(l.strip() for l in s.splitlines() if any(('static let '+n+':') in l for n in ['headRotationGain','headFovGain','headLeanNudgeFovDegPerUnit','headTrackingRestFovDeg','headTranslateMetersPerUnit','headIpdNudgePerUnit']))
zs=[-100,-1,-.75,-.5,-.25,-.2,-.1,0,.05,.1,.15,.2,.25,.5,1,100]
main='''import Foundation
enum Key {case headInvert}
enum Value:Equatable {case bool(Bool)}
struct Snapshot {var effects:[Key:Value]=[:]}
@MainActor final class ThreeDStore {static let shared=ThreeDStore();var snapshot=Snapshot()}
enum VRDistance {static func mmPerPx()->Double {0.2}}
struct HeadPose {var yaw=0.0,pitch=0.0,roll=0.0,xOffset=0.0,yOffset=0.0,zOffset=0.0;var distanceMM:Double?;var distanceFallback:String?;var fusionRoll:Double?,nativeRawRoll:Double?}
final class Probe {
var recenterPosePublishing=false
var headTrackingEnabled=true,loadedVideoActive=true,projectionKind="flat-2d3d",swapEyes=false
var depthDistanceMM:Double?;var onSubtitleTilt:((Double,Double)->Void)?;var onUITilt:((Double)->Void)?
func sendRaw(_ value:String){print(value)}
'''+constants+'\n'+s[a:b]+'''
func run(_ z:Double){var p=HeadPose();p.zOffset=z;applyHeadPose(p)}
}
MainActor.assumeIsolated {
let p=Probe()
for native in [false,true] {p.projectionKind=native ? "vr180":"flat-2d3d"
for inverted in [false,true] {ThreeDStore.shared.snapshot.effects[.headInvert] = .bool(inverted)
for z in '''+str(zs)+''' {p.run(z)}
}}
p.recenterPosePublishing=true;p.run(0.1)
}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 records=[json.loads(l) for l in subprocess.check_output([str(p/'test')],text=True).splitlines()]
 rows=[r['command'][3:] for r in records]
 assert records[-1].get('request_id')==194 and all('request_id' not in r for r in records[:-1])
f=root/'Tests/ThreeDAutoRoute/zoom_content_gpu_test.py'
exec(compile(f.read_text().split('for deg in (0,20,-20):')[0],str(f),'exec'))
frames=[]
replay=ns['Replay'](flat=True)
for inv in (0,1):
 for i,z in enumerate(zs):
  row=rows[inv*len(zs)+i];fov=float(row[2]);mag=math.tan(math.radians(135)/2)/math.tan(math.radians(fov)/2)
  expected=min(1.25,max(.90,1+z*(1 if inv==0 else -1)))
  assert abs(mag-expected)<1e-12,(inv,z,mag,expected)
  # Isolate distance scale from the separately-tested convergence common-domain reserve.
  common["vr_ipd_nudge"]=0
  assert abs(float(row[4])-.12*min(.25,max(-.10,z)))<1e-12
  # Pass actual Swift output through real Lua so its old spherical ceiling cannot hide.
  replay.pose(fov=fov)
  published=replay.values()['vr_fov']
  assert abs(published-math.radians(fov))<1e-6,(fov,published)
  values=dict(vr_fov=published,vr_head_z=0,vr_roll=0,vr_head_roll=0,vr_cross_eye=1,vr_manual_view=0)
  length,axis=measure(values)
  baseline,_=measure(dict(values,vr_fov=math.radians(135)))
  assert abs(length/baseline-mag)<.01,(z,length/baseline,mag)
  rest=draw((w,h),dict(common,**values))
  moved=draw((w,h),dict(common,**values,vr_yaw=10,vr_pitch=-10,vr_head_x=10,vr_head_y=-10))
  assert np.isfinite(moved).all()
  # At fit/retreat there is no crop room. Approach exposes bounded, active looking.
  delta=float(np.abs(moved-rest).mean())
  if mag<=1:assert delta<1e-7,(z,mag,delta)
  else:assert delta>.0001,(z,mag,delta)
  if inv==0 and z in (-100,0,.1,100):frames.append((z,mag,rest,moved))
  print('PASS published flat z',z,'invert',inv,'pixel_scale',length/baseline,'pan_delta',delta)
# Native spherical mapping remains the original135-150*z before Lua rails.
for inv in (0,1):
 for i,z in enumerate(zs):assert abs(float(rows[(2+inv)*len(zs)+i][2])-(135+(1 if inv==0 else -1)*-150*z))<1e-9
# Direct shader boundary: arbitrarily large head pan cannot move the centre landmark out of view.
# Manual pan is deliberately outside that boundary, preserving explicit user control.
values=dict(common,vr_fov=2*math.atan(math.tan(math.radians(67.5))/1.25),vr_head_z=0,vr_roll=0)
manual=draw((w,h),dict(values,vr_manual_yaw=1))
head=draw((w,h),dict(values,vr_yaw=1))
assert float(np.abs(manual-head).mean())>.0001
# Use a bright asymmetric full film for visual inspection, not only tiny metrology dots.
fixture=Image.new('RGB',(w,h),(45,82,119));pen=ImageDraw.Draw(fixture)
for yy in range(0,h,60):
 for xx in range(0,w,80):
  if (xx//80+yy//60)%2:pen.rectangle((xx,yy,xx+79,yy+59),fill=(70,110,145))
pen.rectangle((2,2,w-3,h-3),outline=(235,190,70),width=5)
pen.ellipse((w//3,h//4,2*w//3,3*h//4),fill=(130,65,50),outline=(240,210,150),width=4)
pen.text((30,25),'FULL FILM - top left',fill='white');pen.text((w-150,h-35),'bottom right',fill='white')
rgba=np.concatenate([np.asarray(fixture).astype('f4')/255,np.ones((h,w,1),dtype='f4')],axis=-1);tex.write(rgba.tobytes())
visual=[]
for z,mag,_,_ in frames:
 values=dict(common,vr_ipd_nudge=float(rows[zs.index(z)][4]),vr_fov=2*math.atan(math.tan(math.radians(67.5))/mag),vr_head_z=0,vr_roll=0,vr_head_roll=0,vr_cross_eye=1)
 rest=draw((w,h),values);moved=draw((w,h),dict(values,vr_yaw=10,vr_pitch=-10,vr_head_x=10,vr_head_y=-10))
 for side in (0,1):
  assert moved[h//2,side*w//2+w//4].max()>.1,'extreme head input blanked the fitted film centre'
 visual.append((z,mag,rest,moved))
frames=visual
canvas=Image.new('RGB',(w*2,len(frames)*(h+24)),(14,14,14));d=ImageDraw.Draw(canvas)
for i,(z,mag,rest,moved) in enumerate(frames):
 y=i*(h+24);d.text((8,y+4),'actual Swift z=%g -> scale %.3fx | neutral / extreme head look-around'%(z,mag),fill='white')
 for j,img in enumerate((rest,moved)):canvas.paste(Image.fromarray((np.clip(img[::-1],0,1)*255).astype('uint8')),(j*w,y+24))
canvas.save('/downloads/flat-head-viewport-gpu.png')
print('PASS actual publisher32flat cases through Lua,32unchanged native cases; real GLSL pixel scale, finite extreme input, bounded head pan, explicit manual pan retained. EGL software GPU, no Mac camera.')
