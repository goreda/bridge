#!/usr/bin/env python3
"""Compile and render the REAL Lua-published GLSL on EGL/llvmpipe. Requires lupa, moderngl, numpy, Pillow.
Measures yaw, pitch, roll, zoom and blink pixel response for plain/native/converted cases.
No camera, macOS mpv or real Apple GPU is exercised. Image is saved to GOR_GPU_EVIDENCE or /tmp/gor-head-blink-gpu.png.
"""
import os
from pathlib import Path
import re,sys,json,math
import numpy as np, moderngl
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
prefix=(root/'Tests/ThreeDAutoRoute/preview_pack_lua_test.py').read_text().split('packed = run(1)')[0]
exec(compile(prefix,str(root/"Tests/ThreeDAutoRoute/preview_pack_lua_test.py"),"exec"))
source=next(t for t in run(4) if 'vec4 pack_eye(' in t)
source=source[source.index('//!PARAM '):] # MAIN only; actual D3_TITLE statistics pass is bound below
params={}
def param(m):
 params[m[1]]=float(m[2]);return 'uniform float '+m[1]+';'
source=re.sub(r'//!PARAM (\w+)\n//!TYPE float\n([-+0-9.eE]+)',param,source)
source=re.sub(r'^//!.*$', '',source,flags=re.M)
ctx=moderngl.create_standalone_context(backend='egl')
vs='#version 330\nin vec2 p; out vec2 HOOKED_pos;void main(){gl_Position=vec4(p,0,1);HOOKED_pos=p*.5+.5;}'
fs='#version 330\nuniform sampler2D image;uniform vec2 HOOKED_size;uniform vec2 target_size;in vec2 HOOKED_pos;out vec4 color;vec4 HOOKED_tex(vec2 uv){return texture(image,uv);}vec4 D3_TITLE_tex(vec2 uv){return vec4(0);}\n'+source+'\nvoid main(){color=hook();}'
try: prog=ctx.program(vertex_shader=vs,fragment_shader=fs)
except Exception as e: print(e);sys.exit(1)
print('GPU GLSL compiled',ctx.info['GL_RENDERER'])
w,h=320,180
x,y=np.meshgrid(np.linspace(0,1,w),np.linspace(0,1,h));arr=np.stack([x,y,.25+.5*((np.floor(x*12)+np.floor(y*8))%2),np.ones_like(x)],axis=-1).astype('f4')
tex=ctx.texture((w,h),4,arr.tobytes(),dtype='f4');tex.use();tex.filter=(moderngl.LINEAR,moderngl.LINEAR)
fbo=ctx.simple_framebuffer((w,h),components=4,dtype='f4');fbo.use()
vao=ctx.simple_vertex_array(prog,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
base=dict(params,vr_fov=math.radians(135),vr_source_w=1,vr_source_h=1,vr_crop_x=1,vr_crop_y=1,vr_pk_zoom=1,vr_pk_soft=0,vr_d3_gain=.04,vr_flat_sbs=1,vr_flat_mono=1,vr_pack=4,vr_eye_aspect=16/9,blink_sbs_strength=1,blink_upper=.92,blink_lower=.08,blink_arc=.08,blink_fringe=.03,blink_glow=.05)
def draw(vals):
 d=dict(base,**vals)
 for k,v in d.items():
  if k in prog:prog[k].value=v
 prog['HOOKED_size'].value=(w,h);prog['target_size'].value=(w,h)
 vao.render(moderngl.TRIANGLE_STRIP)
 return np.frombuffer(fbo.read(components=4,dtype='f4'),dtype='f4').reshape(h,w,4)[:,:,:3].copy()
cases={'plain 2d':dict(vr_plain=1,vr_flat_mono=0,vr_flat_sbs=0,vr_pack=0),'converted sbs':dict(vr_pack=3),'converted half sbs':dict(vr_pack=3),'converted top bottom':dict(vr_pack=1),'converted anaglyph':dict(vr_pack=2),'converted vr180 interim':dict(vr_pack=3),'native sbs':dict(vr_flat_mono=0,vr_pack=0),'native half sbs':dict(vr_flat_mono=0,vr_pack=0),'native top bottom':dict(vr_flat_mono=0,vr_pack=0,blink_top_bottom=1),'native vr180':dict(vr_flat_mono=0,vr_flat_sbs=0,vr_source_layout=3,vr_pack=0)}
rows=[];fails=0
for name,v in cases.items():
 rest=draw(v);frames=[rest]
 for n,pose in [('yaw',{'vr_yaw':.14}),('pitch',{'vr_pitch':.14}),('roll',{'vr_roll':.2}),('zoom',{'vr_head_z':.15,'vr_fov':math.radians(120)}),('blink',{'blink_lid_l':1,'blink_lid_r':1})]:
  comparison=rest
  if n in ('yaw','pitch') and name!='native vr180':
   # Head look-around uses crop room created by approach, not blank-screen pan at fit.
   approach=2*math.atan(math.tan(math.radians(67.5))/1.1)
   comparison=draw(dict(v,vr_fov=approach));pose=dict(pose,vr_fov=approach)
  frame=draw(dict(v,**pose));delta=float(np.abs(comparison-frame).mean());ok=np.isfinite(frame).all() and delta>.0005;fails+=not ok;print(('PASS' if ok else 'FAIL'),name,n,'pixel mean delta %.6f'%delta);frames.append(frame)
 rows.append((name,frames))
# Raster edge regression: solid source, rotated screen. Smooth one-output-pixel coverage must exist; rest eyes have matching clean bounds.
tex.write(np.ones((h,w,4),dtype='f4').tobytes())
edge=draw(dict(cases['converted sbs'],vr_roll=.19)); values=edge[:,:,0]
soft=int(((values>.001)&(values<.999)).sum())
print(('PASS' if soft>20 else 'FAIL'),'rotated film border has antialiased coverage pixels',soft);fails+=soft<=20
rest=draw(cases['converted sbs'])[:,:,0]
left=rest[:,:w//2]>.5;right=rest[:,w//2:]>.5
area_delta=abs(int(left.sum())-int(right.sum()))
print(('PASS' if area_delta<=h else 'FAIL'),'rest left/right rectangular canvas area difference',area_delta);fails+=area_delta>h
# Every occupied row has one contiguous film span in each eye: no detached border spikes/holes.
for side in (0,1):
    mask=values[:,side*w//2:(side+1)*w//2]>.01
    transitions=np.abs(np.diff(np.pad(mask.astype(int),((0,0),(1,1))),axis=1)).sum(axis=1)
    ok=bool((transitions<=2).all());fails+=not ok
    print(('PASS' if ok else 'FAIL'),'rotated edge has no detached spikes, eye',side)
# Black borders inside the source remain a separate unresolved content-depth case: measure rather than claim fixed.
inset=np.zeros((h,w,4),dtype='f4');inset[:,:,3]=1;inset[20:-20,30:-30,:3]=1;tex.write(inset.tobytes())
warped=draw(cases['converted sbs'])[:,:,0]
for side in (0,1):
    spans=[]
    for yy in range(h):
        xx=np.flatnonzero(warped[yy,side*w//2:(side+1)*w//2]>.5)
        if xx.size:spans.append((int(xx[0]),int(xx[-1])))
    print('DIAGNOSTIC embedded black-border width range eye',side,min(b-a+1 for a,b in spans),max(b-a+1 for a,b in spans))
canvas=Image.new('RGB',(w*6,h*len(rows)+24*len(rows)),(24,24,24));pen=ImageDraw.Draw(canvas)
for j,(name,frames) in enumerate(rows):
 yy=j*(h+24);pen.text((4,yy+4),name+' | rest | yaw | pitch | roll | zoom | blink',fill='white')
 for i,frame in enumerate(frames):canvas.paste(Image.fromarray((np.clip(frame[::-1],0,1)*255).astype('uint8')),(i*w,yy+24))
canvas.save(os.environ.get('GOR_GPU_EVIDENCE','/tmp/gor-head-blink-gpu.png'))
print('FAILURES',fails);sys.exit(1 if fails else 0)
