#!/usr/bin/env python3
"""Actual Lua shortcut forwarding + production GLSL content zoom, separate S1 layout. Not Mac keys."""
from pathlib import Path
import math,numpy as np
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
r=ns['Replay'](flat=True)
# Load actual gor-fit, route its script-message-to into the real look handler.
r.lua.execute('''mp.commandv=function(...)
 local a={...};cmds[#cmds+1]=a
 if a[1]=="script-message-to" and a[2]=="vr180_look" and handlers[a[3]] then handlers[a[3]](table.unpack(a,4)) end
 return true
end''')
r.lua.execute((root/'Resources/vendor/mpv/scripts/gor-fit.lua').read_text())
# Three coloured landmarks: middle gives layout; outer red/green give content scale.
X,Y=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
def blob(x):return np.exp(-((X-x)**2+(Y-.5)**2)/.0001).astype('f4')
texture=np.stack([blob(.4),blob(.6),blob(.5),np.ones_like(X)],-1).astype('f4');tex.write(texture.tobytes())
common=dict(vr_pack=3,vr_source_layout=0,vr_flat_mono=1,vr_flat_sbs=1,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0,vr_gap_frac=.0125)
def measure(values):
 image=draw((w,h),dict(values,**common));centres=[];length=[]
 for side in (0,1):
  eye=image[:,side*w//2:(side+1)*w//2];points=[]
  for channel in (0,1,2):
   v=np.maximum(eye[:,:,channel]-.05,0);yy,xx=np.indices(v.shape);mass=v.sum();assert mass>0
   points.append(np.array([(xx*v).sum()/mass+side*w//2,(yy*v).sum()/mass]))
  centres.append(points[2]);length.append(np.linalg.norm(points[1]-points[0]))
 return np.mean(length),centres[1]-centres[0]
for deg in (0,20,-20):
 angle=math.radians(deg)
 basev=dict(vr_fov=math.radians(135),vr_head_z=0,vr_roll=angle,vr_head_roll=angle,vr_cross_eye=1,vr_manual_view=0)
 default,axis=measure(basev)
 for z,fov in ((.2,110),(-.2,150)):
  length,delta=measure(dict(basev,vr_head_z=z,vr_fov=math.radians(fov)))
  ratio=length/default;expected=math.tan(math.radians(67.5))/((1-z)*math.tan(math.radians(fov/2)))
  err=abs(delta[1]-delta[0]*math.tan(angle))
  print('MEAS approach/retreat headdeg',deg,'z',z,'fov',fov,'scale_ratio',ratio,'expected',expected,'S1_error_px',err)
  assert abs(ratio/expected-1)<.02 and err<1
# Actual menu/shortcut routes: gor-fit -> look, without a replacement zoom policy.
for name,action,args in [('equals','zoom',('1',)),('minus','zoom',('-1',)),('held-in','hold',('0','0','1')),('held-out','hold',('0','0','-1'))]:
 r.msg('vr180-look-full-fit');r.pose();
 for i in range(90):r.tick(i/60)
 before=r.values();a,_=measure(before)
 r.g.handlers[action](*args)
 if action=='hold':
  for i in range(24):r.g.clock=2+i/60;r.g.handlers[action](*args);r.tick(2+i/60)
 else:
  for i in range(90):r.tick(2+i/60)
 after=r.values();b,delta=measure(after)
 print('MEAS shortcut',name,'manual_view',after['vr_manual_view'],'pixel_scale_ratio',b/a)
 assert b/a>1.02 if name in ('equals','held-in') else b/a<.98
print('PASS distance content zoom and actual Lua shortcut bridge, S1 centres retained. Physical Mac keyboard delivery NOT_RUN')
