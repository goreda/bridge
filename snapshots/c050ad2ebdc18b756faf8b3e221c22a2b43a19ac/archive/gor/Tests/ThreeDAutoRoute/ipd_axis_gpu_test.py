#!/usr/bin/env python3
"""Actual published GLSL nonzero-IPD optical sweep; synthetic fixtures, not Mac proof."""
from pathlib import Path
import math,numpy as np
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/head_shift_gpu_test.py'
exec(compile(f.read_text().split('for layout,arrangement',1)[0],str(f),'exec'))
fail=[]
for layout,arr in [(0,mono),(1,sbs),(2,tb)]:
 if arr.ndim==2:arr=np.stack([arr]*3+[np.ones_like(arr)],-1).astype('f4')
 tex.write(arr.astype('f4').tobytes())
 for cross in (0,1):
  for deg in (-30,0,30):
   angle=math.radians(deg);sign=1 if cross else -1;axis=np.array([math.cos(angle*sign),math.sin(angle*sign)])
   v=dict(settings,vr_source_layout=layout,vr_flat_mono=int(layout==0),vr_cross_eye=cross,vr_swap_eyes=cross,vr_roll=angle,vr_head_roll=angle)
   a,b=centres(draw((w,h),v));zero=b-a
   for ipd in (-.2,.2):
    c,d=centres(draw((w,h),dict(v,vr_base_ipd=ipd)));delta=d-c;change=delta-zero
    vertical=axis[0]*delta[1]-axis[1]*delta[0];along=float(np.dot(change,axis))
    print('MEAS layout',layout,'cross',cross,'deg',deg,'ipd',ipd,'axis_change_px',along,'vertical_px',vertical,flush=True)
    if abs(vertical)>1 or abs(along)<10:fail.append((layout,cross,deg,ipd,along,vertical))
print('FAILURES',fail);assert not fail
print('PASS36 nonzero-IPD optical cases')
