#!/usr/bin/env python3
"""Real Lua crop route -> real generated GLSL: rejected bar pixels never return under pose/soft."""
from pathlib import Path
import numpy as np,math
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
# Every sample outside the accepted common source eye rect is painted red in mutant.
inside=(xx>=.15)&(xx<=.85)&(yy>=.2)&(yy<=.8)
clean=arr.copy();clean[:,:,:3]=(.2,.6,.4)
mutant=clean.copy();mutant[~inside,:3]=(1,0,0)
failures=[];shots=[]
for kind in ('flat-2d3d','flat-sbs','flat-tb'):
 localx=(xx*2)%1 if kind=='flat-sbs' else xx
 localy=(yy*2)%1 if kind=='flat-tb' else yy
 inside=(localx>=.15)&(localx<=.85)&(localy>=.2)&(localy<=.8)
 clean=arr.copy();clean[:,:,:3]=(.2,.6,.4)
 mutant=clean.copy();mutant[~inside,:3]=(1,0,0)
 for deg in (0,25,-45,90):
  for fade in (0,1):
   replay=ns['Replay'](flat=True);replay.msg('vr180-look-set-projection',kind,16/9)
   replay.msg('vr180-look-set-pack',3,1,.5,1,fade)
   replay.msg('vr180-look-menu-crop','.7|.5|960','.6|.5|270')
   replay.msg('vr180-look-bar-crop',.15,.2,.7,.6)
   replay.pose(roll=math.radians(deg),fov=145)
   values=replay.values();values.update(vr_d3_gain=.04,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0)
   tex.write(clean.tobytes());expected=draw((672,162),values)
   tex.write(mutant.tobytes());actual=draw((672,162),values)
   error=np.abs(actual-expected).max(axis=-1);count=int((error>.001).sum())
   print('bar-rejection source',kind,'roll',deg,'soft',fade,'changedPixels',count,'max',float(error.max()))
   if count:failures.append((kind,deg,fade,count))
assert not failures,failures
print('PASS rejected source bars cannot affect any film/surround pixel in mono/SBS/TB under tilt, depth, retreat')
