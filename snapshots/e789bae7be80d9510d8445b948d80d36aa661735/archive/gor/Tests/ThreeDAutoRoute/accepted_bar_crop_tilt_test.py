#!/usr/bin/env python3
"""Actual converted-SBS GPU: verified bars stay excluded through tilt and fade.
No owner movie pixels. Bright fixture interior, zero actual black scene content.
"""
from pathlib import Path
import math,numpy as np
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
# Both pictures are identical inside the accepted bar-free rectangle. Outside,
# one has verified black bars, the other has the same bright edge continuation.
bright=np.stack([np.full_like(xx,.8),np.full_like(xx,.5),np.full_like(xx,.3),np.ones_like(xx)],-1).astype('f4')
barred=bright.copy();barred[(xx<.15)|(xx>.85)|(yy<.2)|(yy>.8),:3]=0
fail=[]
for soft in (0,1):
 for roll in (0,25,-45,90):
  r=ns['Replay'](flat=True);r.msg('vr180-look-set-output','full_sbs')
  r.msg('vr180-look-menu-crop','.7|.5|960','.6|.5|270')
  r.msg('vr180-look-bar-crop',.15,.2,.7,.6)
  before=r.values();r.pose(roll=math.radians(roll));v=r.values()
  # Pose may never alter the accepted detector crop or the frozen drawable anchor.
  for k in ['vr_surface_w','vr_surface_h','vr_surface_x','vr_surface_y','vr_source_x','vr_source_y','vr_source_w','vr_source_h','vr_crop_x','vr_crop_y']:
   assert v[k]==before[k],('pose changed accepted domain',k,roll,before[k],v[k])
  settings=dict(v,vr_plain=0,vr_flat_sbs=1,vr_flat_mono=1,vr_pack=3,vr_pk_soft=soft,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0)
  tex.write(bright.tobytes());reference=draw((672,162),settings)
  tex.write(barred.tobytes());actual=draw((672,162),settings)
  changed=int(np.any(abs(actual-reference)>.025,axis=-1).sum())
  print('BAR TILT soft',soft,'roll',roll,'black-bar-contaminated pixels',changed)
  # Permit only the one-pixel linear-filter/AA boundary, not an interior band.
  if changed/actual.shape[0]/actual.shape[1]>.02:fail.append((soft,roll,changed))
assert not fail,('verified black bars sampled again after accepted crop',fail)
print('PASS accepted converted-SBS bars excluded at0/25/-45/90, fade0/1; pose does not mutate crop domain')
