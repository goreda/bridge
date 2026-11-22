#!/usr/bin/env python3
"""Actual generated GLSL gutter, no fixed-black seam. Software EGL only."""
from pathlib import Path
import numpy as np,math
root=Path(__file__).resolve().parents[2]
p=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(p.read_text().split("cases={'plain'",1)[0],str(p),'exec'))
C=np.array([.2,.4,.6],dtype='f4')
source=np.empty((h,w,4),dtype='f4');source[:,:,:3]=C;source[:,:,3]=1;tex.write(source.tobytes())
for deg in (0,25,-45):
 for soft in (0,1):
  for invert in (0,1):
   v=dict(vr_pack=3,vr_flat_sbs=1,vr_flat_mono=1,vr_source_layout=0,vr_gap_frac=.04,vr_pk_soft=soft,vr_pk_surround_invert=invert,vr_pk_zoom=.65,vr_d3_gain=0,vr_parallax_strength=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_roll=math.radians(deg),vr_head_roll=math.radians(deg))
   image=draw((w,h),v)
   # The centre point belongs to the physical divider at every roll. Use its
   # inner2x2 pixels so ownership AA cannot masquerade as a gutter sample.
   gutter=image[h//2-1:h//2+1,w//2-1:w//2+1]
   if not soft:assert np.max(abs(gutter-invert))<1e-6,(deg,soft,invert,gutter)
   elif invert:assert gutter.min()>.5,(deg,soft,invert,gutter)
   else:
    assert gutter.min()>=0 and gutter.max()<.5,(deg,soft,invert,gutter)
    if deg==0:assert gutter.max()>.01,'neutral soft gutter replaced by fixed black'
    # At tilt the evaluated outside UV may legitimately fade fully to black.
   print('PASS actual gutter',deg,soft,invert,'range',float(gutter.min()),float(gutter.max()))
print('PASS12gutter cases,Black/White/Soft at0/25/-45; NativeMac NOT_RUN')
