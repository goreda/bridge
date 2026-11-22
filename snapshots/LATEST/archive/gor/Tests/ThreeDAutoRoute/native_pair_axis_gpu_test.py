#!/usr/bin/env python3
"""Native194h fixed-viewport optical centres and cross/parallel interocular axis.
Real generated Lua shader; source marker centroids measured in GPU pixels.
"""
from pathlib import Path
import math,os
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/engine193b_gpu_test.py'
exec(compile(f.read_text().split('frames=[]',1)[0],str(f),'exec'))
if os.environ.get('NATIVE_AXIS_SOURCE'):
 current=subprocess.check_output(['git','show',os.environ['NATIVE_AXIS_SOURCE']+':archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
frames=[]
for tb in (0,1):
 localx=xx if tb else (xx*2)%1
 localy=(yy*2)%1 if tb else yy
 marker=np.exp(-((localx-.5)**2+(localy-.5)**2)/.0002)
 tag=np.where((yy if tb else xx)<.5,.15,.85)
 fixture=np.stack([marker,np.ones_like(xx),tag,np.ones_like(xx)],-1).astype('f4');tex.write(fixture.tobytes())
 for extended in (False,True):
  p=program(generated(current,extended))
  for cross in (0,1):
   for swap in (0,1):
    for deg in (-30,-10,0,10,30):
     angle=math.radians(deg)*(1 if cross else -1)
     values=dict(vr_roll=math.radians(deg),vr_head_roll=math.radians(deg),vr_cross_eye=cross,vr_swap_eyes=swap,vr_source_layout=4 if tb else 3,vr_native_tb=tb,vr_flat_sbs=0,vr_flat_mono=0,vr_pack=0,vr_yaw=0,vr_pitch=0,vr_fov=math.radians(90),vr_base_ipd=0,vr_ipd_nudge=0,vr_surface_w=w,vr_surface_h=h,vr_aspect_override=1,vr_gap_frac=0,vr_gap_blur_frac=0,vr_vignette_darken=0,vr_vignette_blur=0,vr_parallax_strength=0,vr_parallax_disparity=0)
     image=draw(p,values);centres=[]
     for eye in (0,1):
      red=image[:,eye*w//2:(eye+1)*w//2,0];weights=red**4
      cx=float((weights*(xx[:,:w//2]*w+eye*w//2)).sum()/weights.sum())
      cy=float((weights*(yy[:,:w//2]*h)).sum()/weights.sum());centres.append((cx,cy))
      ex=w/2+(eye-.5)*w/2*math.cos(angle);ey=h/2+(eye-.5)*w/2*math.sin(angle)
      assert abs(cx-ex)<1.2 and abs(cy-ey)<1.2,('centre/axis',tb,extended,cross,swap,deg,eye,(cx,cy),(ex,ey))
      px=int(round(cx-.5));py=int(round(cy-.5));expected=.85 if (eye != bool(swap)) else .15
      assert abs(float(image[py,px,2]/image[py,px,1])-expected)<.025,('source-eye',tb,cross,swap,deg,eye)
     dx=centres[1][0]-centres[0][0];dy=centres[1][1]-centres[0][1]
     normal=-dx*math.sin(angle)+dy*math.cos(angle)
     assert abs(normal)<1.5,('vertical disparity in viewer-eye frame',normal)
     # Constant-blue eye ownership must stay at the fixed divider on every row.
     expected_left=.85 if swap else .15;expected_right=.15 if swap else .85
     assert np.max(abs(image[:,w//2-3,2]/image[:,w//2-3,1]-expected_left))<.025, ("divider left",tb,extended,cross,swap,deg, image[:,w//2-3,2].min(),image[:,w//2-3,2].max())
     assert np.max(abs(image[:,w//2+3,2]/image[:,w//2+3,1]-expected_right))<.025
     # Render a true spherical horizon stripe, not only a source-eye tag.
     horizon=fixture.copy();horizon[:,:,0]=np.exp(-((localy-.5)**2)/.0001)
     tex.write(horizon.tobytes());horizon_image=draw(p,values);tex.write(fixture.tobytes())
     horizon_points=[]
     for eye in (0,1):
      cx,cy=centres[eye];points=[]
      for offset in (-12,0,12):
       px=int(round(cx+offset-.5));weights=horizon_image[:,px,0]**4
       py=float((weights*(np.arange(h)+.5)).sum()/weights.sum())
       points.append((px+.5,py))
      horizon_points.append(points)
     for left_point,right_point in zip(*horizon_points):
      dx=right_point[0]-left_point[0];dy=right_point[1]-left_point[1]
      # Quantized sample columns add at most one pixel of ray-coordinate error.
      assert abs(-dx*math.sin(angle)+dy*math.cos(angle))<2.0,('horizon eye-normal error',tb,extended,cross,swap,deg,left_point,right_point)
     if not tb and extended and swap==cross and deg in (0,30):frames.append((f'{deg}deg cross={cross}',horizon_image))
print('PASS80native SBS/TB legacy/extended cross x swap x tilt: analytic optical centres, 240 horizon correspondences, eye-normal disparity, fixed divider and source ownership')
canvas=Image.new('RGB',(w,len(frames)*(h+24)),(20,20,20));pen=ImageDraw.Draw(canvas)
for i,(label,frame) in enumerate(frames):
 pen.text((5,i*(h+24)+5),label,fill='white');canvas.paste(Image.fromarray((np.clip(frame[::-1,:,:3],0,1)*255).astype('uint8')),(0,i*(h+24)+24))
canvas.save('/downloads/native194h-pair-axis.png')
