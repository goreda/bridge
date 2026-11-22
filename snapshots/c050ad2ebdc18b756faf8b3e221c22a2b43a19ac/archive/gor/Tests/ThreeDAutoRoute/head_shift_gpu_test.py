#!/usr/bin/env python3
"""Flat S1 real GLSL feature-centre matching. Native ray-only reference is separate.
Synthetic fixtures, not Mac proof. Owner193e Q2 withdrew the native S1 oracle.
"""
import math,os
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0].replace("fbo.release();return result","[a.release() for a in fbo.color_attachments];fbo.release();return result"),str(f),'exec'))
# A smooth bright calibration landmark; fit its intensity centroid, independently per eye.
x,y=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
blob=np.exp(-((x-.5)**2+(y-.5)**2)/(.005**2)).astype('f4')
mono=np.stack([blob,blob,blob,np.ones_like(blob)],-1)
sbs=np.concatenate([np.exp(-(((x[:,:w//2]*2)-.5)**2+(y[:,:w//2]-.5)**2)/(.005**2))]*2,axis=1)
tb=np.concatenate([np.exp(-((x[:h//2]-.5)**2+((y[:h//2]*2)-.5)**2)/(.005**2))]*2,axis=0)
settings=dict(vr_pack=3,vr_eye_aspect=16/9,vr_gap_frac=.0125,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0)
rows=[];fail=[]
def centres(image):
 result=[]
 for side in (0,1):
  a=image[:,side*w//2:(side+1)*w//2,0];yy,xx=np.indices(a.shape);weight=np.maximum(0,a-.1);mass=weight.sum()
  assert mass>0
  result.append(np.array([(xx*weight).sum()/mass+side*w//2,(yy*weight).sum()/mass]))
 return result
# Native layout3/4 ray-only geometry is measured by spherical_shift_gpu_test.
# These are the flat source layouts after the output-first plan maps native SBS/TB.
for layout,arrangement in ((0,mono),(1,sbs),(2,tb)):
 if arrangement.ndim==2:arrangement=np.stack([arrangement]*3+[np.ones_like(arrangement)],-1).astype('f4')
 tex.write(arrangement.astype('f4').tobytes())
 for cross in (0,1):
  for deg in (-30,-20,-10,-5,0,5,10,20,30):
   angle=math.radians(deg);v=dict(settings,vr_source_layout=layout,vr_flat_mono=1 if layout==0 else 0,blink_top_bottom=1 if layout==2 else 0,vr_native_tb=0,vr_swap_eyes=cross,vr_cross_eye=cross,vr_head_roll=angle,vr_roll=angle)
   image=draw((w,h),v);a,b=centres(image);delta=b-a
   expected_angle=angle*(1 if cross else -1)
   error=abs(delta[1]-delta[0]*math.tan(expected_angle));axis=abs(math.degrees(math.atan2(delta[1],delta[0]))-math.degrees(expected_angle))
   print('MEAS layout',layout,'cross',cross,'headdeg',deg,'dxdy',delta,'line_error_px',error,'axis_error_deg',axis)
   if error>1 or axis>.1:fail.append((layout,cross,deg,error,axis))
   # Yaw/pitch must not alter scale/layout Jacobian. Compare centroid vector, not pan position.
   moved=draw((w,h),dict(v,vr_yaw=.05,vr_pitch=.04,vr_head_z=.2,vr_fov=math.radians(110)))
   try:c,d=centres(moved);delta2=d-c;assert np.max(np.abs(delta2-delta))<1
   except AssertionError:fail.append(('pitch-yaw-distance',layout,cross,deg))
   if layout==0 and cross==1 and deg in (-30,-20,0,20,30):rows.append((deg,image))
# Y3 depth retained after layout fit: compare disparity relative to each zero-depth layout.
# A centre landmark has exactly zero disparity on the brightness-neutral plane.
# Use a nonzero positional depth to keep this axis-retention ratio measurable.
plane_blob=np.exp(-((x-.5)**2+(y-.7)**2)/(.005**2)).astype('f4')
plane_mono=np.stack([plane_blob,plane_blob,plane_blob,np.ones_like(plane_blob)],-1)
tex.write(plane_mono.astype('f4').tobytes());depth=[]
for deg in (0,30):
 angle=math.radians(deg);v=dict(settings,vr_source_layout=0,vr_swap_eyes=1,vr_cross_eye=1,vr_head_roll=angle,vr_roll=angle)
 a,b=centres(draw((w,h),v));c,d=centres(draw((w,h),dict(v,vr_d3_gain=.08)))
 delta=(d-c)-(b-a);axis=np.array([math.cos(angle),math.sin(angle)])
 magnitude=float(np.dot(delta,axis));vertical=float(axis[0]*delta[1]-axis[1]*delta[0]);depth.append(magnitude)
 print('MEAS Y3 headdeg',deg,'axis_disparity_px',magnitude,'vertical_residual_px',vertical)
 assert abs(vertical)<1
print('MEAS Y3 depth retained ratio',depth[1]/depth[0]);assert abs(depth[1]/depth[0]-1)<.02
canvas=Image.new('RGB',(w,len(rows)*(h//2+25)),(20,20,20));d=ImageDraw.Draw(canvas)
for i,(deg,img) in enumerate(rows):
 d.text((4,i*(h//2+25)+4),'cross-eye, head '+str(deg)+' degrees',fill='white');canvas.paste(Image.fromarray((np.clip(img[::-1],0,1)*255).astype('uint8')).resize((w,h//2)),(0,i*(h//2+25)+25))
canvas.save('/tmp/head-shift-gpu.png')
assert not fail,fail
print('PASS S1 rendered-centre/axis/pitch-yaw-distance matrix')
