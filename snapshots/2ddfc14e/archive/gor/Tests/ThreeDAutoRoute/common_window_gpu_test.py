#!/usr/bin/env python3
"""192c T2 real generated GLSL: common source crop, no added seam band or repeated samples.
Known gradient source plus processed owner capture205.247s. Original film not verified.
"""
import os,subprocess
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
base.update(vr_pack=3,vr_source_layout=0,vr_flat_mono=1,vr_flat_sbs=1,vr_parallax_strength=0,vr_gap_frac=.0125,vr_eye_aspect=1.6)
old=subprocess.check_output(['git','show','a9c9b30:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],cwd=root,text=True)
def compile_source(source):
 text=next(t for t in run(4,source=source) if 'vec4 pack_eye(' in t)
 text=text[text.index('//!PARAM '):]
 text=re.sub(r'//!PARAM (\w+)\n//!TYPE float\n([-+0-9.eE]+)',lambda m:'uniform float '+m[1]+';',text)
 text=re.sub(r'^//!.*$','',text,flags=re.M)
 fragment='#version 330\nuniform sampler2D image;uniform vec2 HOOKED_size,target_size;in vec2 HOOKED_pos;out vec4 color;vec4 HOOKED_tex(vec2 uv){return texture(image,uv);}vec4 D3_TITLE_tex(vec2 p){return vec4(0);}\n'+text+'\nvoid main(){color=hook();}'
 p=ctx.program(vertex_shader=vs,fragment_shader=fragment)
 v=ctx.simple_vertex_array(p,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
 return p,v
candidate=(prog,vao);baseline=compile_source(old)
# Each source coordinate is unique. Positive derivative means no clamped, repeated or reversed rows/columns.
coords=np.stack([.15+.8*xx,.15+.8*yy,np.full_like(xx,.4),np.ones_like(xx)],-1).astype('f4');tex.write(coords.tobytes())
def check_image(image,strict=True):
 global w,h
 gap=np.where(image[h//2].sum(axis=-1)<.01)[0]
 seam=gap[(gap>w//2-80)&(gap<w//2+80)]
 assert len(seam)<=round(w*.0125*.5),('extra seam band',len(seam))
 for side in (0,1):
  # Exclude only physical gutter and one antialiased boundary pixel.
  eye=image[:,side*w//2+4:(side+1)*w//2-4]
  active=np.where(eye[:,eye.shape[1]//2].sum(axis=-1)>.1)[0];assert len(active)>10
  eye=eye[active[2]:active[-2]]
  assert eye.sum(axis=-1).min()>.01,'black band inside eye'
  if strict:
   dx=np.diff(eye[:,:,0],axis=1);dy=np.diff(eye[:,:,1],axis=0)
   assert dx.min()>1e-6 and dy.min()>1e-6,('repeated source row/column',dx.min(),dy.min())
   # Crop must be uniform, no directional stretching of original source pixels.
   ratio=np.median(dx)/np.median(dy)
   assert abs(ratio-1/1.6)<.02,('anisotropic source crop',ratio)
 return len(seam)
settings=dict(vr_d3_gain=.08,vr_base_ipd=0,vr_ipd_nudge=0,vr_pk_conv=.5)
prog,vao=baseline;before=draw((w,h),settings)
try:check_image(before)
except AssertionError as error:print('PASS old actual shader rejected:',error)
else:raise AssertionError('baseline seam/stretch defect not reproduced')
prog,vao=candidate
for gain in (0,.04,.08,.2):
 for ipd in (-.2,0,.2):
  image=draw((w,h),dict(settings,vr_d3_gain=gain,vr_base_ipd=ipd));seam=check_image(image)
  print('PASS known-source gain',gain,'ipd',ipd,'seam_px',seam,'no repeated/stretched rows/columns')
after=image.copy();rows=[('known-source old',before),('known-source common crop',after)]
owner=os.environ.get('GOR_EDGE_OWNER_FRAME')
if owner:
 im=Image.open(owner).convert('RGB');data=np.asarray(im);mask=data[:,:im.width//2].max(axis=-1)>16;ys,xs=np.where(mask)
 # Captured output is not original source. Crop only measured visible left-eye frame.
 box=(int(xs.min()),int(ys.min()),int(xs.max())+1,int(ys.max())+1)
 im=im.crop(box).resize((w,h));a=np.asarray(im)[::-1].astype('f4')/255
 tex.write(np.dstack([a,np.ones((h,w),dtype='f4')]).tobytes())
 prog,vao=baseline;before=draw((w,h),settings);prog,vao=candidate;after=draw((w,h),settings)
 rows += [('owner processed frame before',before),('owner processed frame after',after)]
 print('MEAS owner205.247s captured-output replay bbox',box,'original frame NOT_VERIFIED; existing baked repeats cannot be repaired or attributed to new shader')
canvas=Image.new('RGB',(960,len(rows)*324),(20,20,20));pen=ImageDraw.Draw(canvas)
for j,(name,frame) in enumerate(rows):
 pen.text((5,j*324+3),name,fill='white');canvas.paste(Image.fromarray((np.clip(frame[::-1],0,1)*255).astype('uint8')).resize((960,300)),(0,j*324+24))
canvas.save('/downloads/common-window-gpu.png')
print('PASS actual generated GLSL common-window gate. Original frame not verified; owner playback decides.')
