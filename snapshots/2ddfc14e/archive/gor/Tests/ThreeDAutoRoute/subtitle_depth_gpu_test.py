#!/usr/bin/env python3
"""Actual published GLSL depth-field/glyph replay, EGL software GPU. Not Mac acceptance."""
import os
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
im=Image.new('RGBA',(w,h),(30,25,20,255));d=ImageDraw.Draw(im)
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf',42)
d.text((50,440),'It would be a present.',font=font,fill=(255,205,100),stroke_width=2,stroke_fill=(0,0,0))
d.text((50,490),'I know how to return a favor.',font=font,fill=(255,205,100),stroke_width=2,stroke_fill=(0,0,0))
if os.environ.get('GOR_SUBTITLE_FRAME'):im=Image.open(os.environ['GOR_SUBTITLE_FRAME']).convert('RGBA').resize((w,h))
tex.write((np.asarray(im).astype('f4')/255).tobytes())
fp=ctx.program(vertex_shader=vs,fragment_shader=fs.replace('color=hook();','color=vec4(d3_depth(HOOKED_pos,0.5),0,0,1);'))
fv=ctx.simple_vertex_array(fp,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
fbo=ctx.simple_framebuffer((w,h),components=4,dtype='f4');fbo.use();ctx.viewport=(0,0,w,h);fv.render(moderngl.TRIANGLE_STRIP)
depth=np.frombuffer(fbo.read(components=4,dtype='f4'),dtype='f4').reshape(h,w,4)[:,:,0];shift=depth*.08*w*.5
peak=max(float(np.abs(np.diff(shift,axis=0)).max()),float(np.abs(np.diff(shift,axis=1)).max()))
curvature=max(float(np.abs(np.diff(shift,n=2,axis=0)).max()),float(np.abs(np.diff(shift,n=2,axis=1)).max()))
print('MEAS adjacent displacement max_px',peak,'second difference max_px',curvature)
assert peak<1,'source-pixel skips';assert curvature<1/255,'glyph-scale oscillation'
settings=dict(vr_swap_eyes=0,vr_source_layout=0,vr_flat_sbs=1,vr_flat_mono=1,vr_pack=3,vr_eye_aspect=16/9,vr_parallax_strength=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_gap_frac=0,vr_vignette_darken=0,vr_vignette_blur=0)
canvas=Image.new('RGB',(w*2,h*3))
for i,gain in enumerate((0,.04,.08)):
 rendered=draw((w,h),dict(settings,vr_d3_gain=gain));assert np.isfinite(rendered).all()
 canvas.paste(im.convert('RGB'),(0,i*h));canvas.paste(Image.fromarray((np.clip(rendered,0,1)*255).astype('uint8')),(w,i*h))
canvas.save(os.environ.get('GOR_SUBTITLE_EVIDENCE','/tmp/subtitle-depth-gate.png'))
print('PASS actual published shader depth field and glyph renders')
