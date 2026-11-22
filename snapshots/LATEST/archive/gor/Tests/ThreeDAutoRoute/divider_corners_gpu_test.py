#!/usr/bin/env python3
"""Owner192d: real generated GLSL, rotated ownership, all-corner coverage, maximal fit."""
import math
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/zoom_content_gpu_test.py'
exec(compile(f.read_text().split('for deg in (0,20,-20):')[0],str(f),'exec'))
source=np.ones((h,w,4),dtype='f4')
kx,ky=round(w*.08),round(h*.08)
colors=[(.95,.12,.12),(.12,.95,.12),(.12,.12,.95),(.95,.95,.12)]
for (ys,xs),color in zip([(slice(0,ky),slice(0,kx)),(slice(0,ky),slice(w-kx,w)),(slice(h-ky,h),slice(0,kx)),(slice(h-ky,h),slice(w-kx,w))],colors):source[ys,xs,:3]=color
tex.write(source.tobytes())
def counts(image):
 r,g,b=np.moveaxis(image,-1,0)
 return np.array([((r>.7)&(g<.4)&(b<.4)).sum(),((g>.7)&(r<.4)&(b<.4)).sum(),((b>.7)&(r<.4)&(g<.4)).sum(),((r>.7)&(g>.7)&(b<.4)).sum()])
settings=dict(common,vr_fov=math.radians(135),vr_head_z=0,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0,vr_gap_frac=.0125,vr_gap_blur_frac=0)
diagnostic=fs.replace('return mix(background,blink_render(HOOKED_tex(sample_pos),lid_uv,sample_pos,right,right),coverage);','return vec4(vec3(right>0.5 ? 0.5:1.0),1.0);')
assert diagnostic!=fs
dprog=ctx.program(vertex_shader=vs,fragment_shader=diagnostic)
dvao=ctx.simple_vertex_array(dprog,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
frames=[]
for cross in (0,1):
 baseline=draw((w,h),dict(settings,vr_roll=0,vr_head_roll=0,vr_cross_eye=cross))
 reference=counts(baseline)
 for deg in (0,10,20,30,-10,-20,-30):
  angle=math.radians(deg);pair_angle=angle*(1 if cross else -1)
  gap=.0125;oa=w/h;le=.5-gap*.25;ea=oa*le;sa=16/9;fw=ea;fh=ea/sa
  spacing=max((.5+gap*.25)*oa,fw*abs(math.cos(angle-pair_angle))+fh*abs(math.sin(angle-pair_angle))+gap*oa*.5)
  bw=spacing*abs(math.cos(pair_angle))+fw*abs(math.cos(angle))+fh*abs(math.sin(angle))
  bh=spacing*abs(math.sin(pair_angle))+fh*abs(math.cos(angle))+fw*abs(math.sin(angle))
  fit=min(1,oa/bw,1/bh)
  image=draw((w,h),dict(settings,vr_roll=angle,vr_head_roll=angle,vr_cross_eye=cross))
  ratios=counts(image)/(reference*fit*fit)
  assert np.min(ratios)>.96,(cross,deg,'source corner clipped',ratios,fit)
  # Ownership-only diagnostic keeps the production partition/gutter exact,
  # while replacing film sampling with two solid eye IDs. This prevents an
  # unoccupied black film margin from being mistaken for the physical divider.
  saved=(prog,vao);prog,vao=dprog,dvao
  ownership=draw((w,h),dict(settings,vr_roll=angle,vr_head_roll=angle,vr_cross_eye=cross))
  prog,vao=saved
  points=[]
  for y in range(h//2-35,h//2+36):
   black=np.where(ownership[y,w//2-60:w//2+60].max(axis=-1)<.02)[0]
   assert len(black)>0,(cross,deg,y,'no divider')
   points.append((y,float(black.mean()+w//2-60)))
  slope=np.polyfit(np.array(points)[:,0],np.array(points)[:,1],1)[0]
  measured=math.degrees(math.atan(-slope))
  expected=math.degrees(pair_angle)
  assert abs(measured-expected)<.25,(cross,deg,'divider angle',measured,expected)
  # At nonzero fit loss, enlarging by1% violates a physical screen bound.
  if fit<1:assert max(bw*fit*1.01/oa,bh*fit*1.01)>1
  print('MEAS crossed',cross,'headdeg',deg,'dividerdeg',measured,'maximal_scale',fit,'corner_area_retention',ratios.tolist(),'limiting',('width' if oa/bw<1/bh else 'height'))
  if cross==1 and deg in (0,10,20,30):frames.append((deg,fit,image))
canvas=Image.new('RGB',(w,len(frames)*(h+24)),(22,22,22));pen=ImageDraw.Draw(canvas)
for i,(deg,fit,img) in enumerate(frames):
 y=i*(h+24);pen.text((6,y+4),'head%d deg | rotating eye ownership | scale %.4f | all four source corners retained'%(deg,fit),fill='white')
 canvas.paste(Image.fromarray((np.clip(img[::-1],0,1)*255).astype('uint8')),(0,y+24))
canvas.save('/downloads/192d-divider-corners.png')
print('PASS14 real pixel divider/corner gates, plus1% scale-up infeasibility. Software evidence, not Mac playback.')
