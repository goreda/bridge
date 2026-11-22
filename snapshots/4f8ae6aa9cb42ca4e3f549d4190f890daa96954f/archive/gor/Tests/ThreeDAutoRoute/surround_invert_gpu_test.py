"""Shipping generated GLSL on software EGL: white backing, never RGB inversion.
Not owner Mac playback. Actual Lua handler, uniform, reducer/keymap tested separately.
"""
from pathlib import Path
import subprocess,re
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
p=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(p.read_text().split("cases={'plain'",1)[0],str(p),'exec'))
# A deliberately red-biased film. A full-RGB inversion would turn it cyan.
source=np.stack([np.full_like(xx,.8),np.full_like(xx,.2),np.full_like(xx,.1),np.ones_like(xx)],-1).astype('f4');tex.write(source.tobytes())
values=dict(vr_source_layout=0,vr_flat_mono=1,vr_flat_sbs=1,vr_pack=3,vr_pk_zoom=.65,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0,vr_gap_frac=0,vr_gap_blur_frac=0)
images=[]
for pack in (1,2,3):
 v=dict(values,vr_pack=pack)
 dark=draw((w,h),dict(v,vr_pk_soft=0,vr_pk_surround_invert=0))
 white=draw((w,h),dict(v,vr_pk_soft=0,vr_pk_surround_invert=1))
 soft=draw((w,h),dict(v,vr_pk_soft=1,vr_pk_surround_invert=0))
 light=draw((w,h),dict(v,vr_pk_soft=1,vr_pk_surround_invert=1))
 inside=np.abs(dark[:,:,0]-.8)<1e-7;outside=dark.max(axis=2)<1e-6
 assert inside.sum()>1000 and outside.sum()>1000
 print('FILM ERROR',pack,np.max(abs(white[inside]-dark[inside])),np.max(abs(light[inside]-soft[inside])));assert np.max(abs(white[inside]-dark[inside]))<1e-6 and np.max(abs(light[inside]-soft[inside]))<1e-6,'film changed'
 assert np.max(abs(white[outside]-1))<1e-6,'Black must become White'
 # White changes only achromatic backing. Channel differences are invariant,
 # which rules out RGB inversion, desaturation and source-eye color swapping.
 delta=light[outside]-soft[outside]
 assert np.max(abs(delta[:,0]-delta[:,1]))<2e-7 and np.max(abs(delta[:,1]-delta[:,2]))<2e-7
 assert np.all(light[outside,0]>=light[outside,1]) and np.all(light[outside,1]>=light[outside,2])
 assert np.array_equal(draw((w,h),dict(v,vr_pk_soft=1,vr_pk_surround_invert=0)),soft),'Off recovery changed pixels'
 print('PASS pack',pack,'film within3e-8 float, black->white, original soft chroma, off recovery')
 if pack==3:images=[('Black / Invert off',dark),('Black / Invert on',white),('Soft / Invert off',soft),('Soft / Invert on',light)]
# Verify exact old output when disabled, using the parent source generated through production Lua.
old=subprocess.check_output(['git','show','3307bfdc:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],cwd=root,text=True)
text=next(t for t in run(4,source=old) if 'vec4 pack_eye(' in t);text=text[text.index('//!PARAM '):]
text=re.sub(r'//!PARAM (\w+)\n//!TYPE float\n([-+0-9.eE]+)',lambda m:'uniform float '+m[1]+';',text)
text=re.sub(r'^//!.*$','',text,flags=re.M)
past=ctx.program(vertex_shader=vs,fragment_shader='#version 330\nuniform sampler2D image;uniform vec2 HOOKED_size,target_size;in vec2 HOOKED_pos;out vec4 color;vec4 HOOKED_tex(vec2 uv){return texture(image,uv);}vec4 D3_TITLE_tex(vec2 p){return vec4(0);}\n'+text+'\nvoid main(){color=hook();}')
oldvao=ctx.simple_vertex_array(past,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
newprog,newvao=prog,vao
for softmode in (0,1):
 settings=dict(values,vr_pk_soft=softmode,vr_pk_surround_invert=0)
 after=draw((w,h),settings);prog,vao=past,oldvao;before=draw((w,h),settings);prog,vao=newprog,newvao
 if softmode==0:
  assert np.array_equal(before,after),'Black default-off differs from parent'
 else:
  interior=before.min(-1)>.09
  interior &= abs(before[:,:,0]-.8)<1e-7
  assert interior.sum()>1000 and np.array_equal(before[interior],after[interior]),'Soft opaque film changed'
print('PASS Black default-off byte-identical; Soft opaque film unchanged, fractional backing intentionally repaired')
canvas=Image.new('RGB',(960,4*324),(20,20,20));pen=ImageDraw.Draw(canvas)
for i,(label,img) in enumerate(images):
 pen.text((6,i*324+5),label,fill='white');canvas.paste(Image.fromarray((np.clip(img[::-1],0,1)*255).astype('uint8')).resize((960,300)),(0,i*324+24))
canvas.save('/downloads/surround-invert-gpu.png')
