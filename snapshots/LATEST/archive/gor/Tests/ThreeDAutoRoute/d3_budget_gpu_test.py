#!/usr/bin/env python3
"""Generated D shader before/after on EGL software GPU, not Mac playback."""
from pathlib import Path
import runpy,time
import numpy as np,moderngl
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
ns=runpy.run_path(str(root/'Tests/Photon/d3_budget_test.py'))
new=ns['new'];new.mode(True,0);new.budget.on=True
source=new.budget.source(new.pack)
def compile_pack(source):
    text=source[source.index('//!PARAM '):]
    text=re.sub(r'//!PARAM (\w+)\n//!TYPE float\n([-+0-9.eE]+)',lambda m:'uniform float '+m[1]+';',text)
    text=re.sub(r'^//!.*$','',text,flags=re.M)
    fragment='#version 330\nuniform sampler2D image;uniform vec2 HOOKED_size,target_size;in vec2 HOOKED_pos;out vec4 color;vec4 HOOKED_tex(vec2 uv){return texture(image,uv);}vec4 D3_TITLE_tex(vec2 p){return vec4(0);}\n'+text+'\nvoid main(){color=hook();}'
    p=ctx.program(vertex_shader=vs,fragment_shader=fragment)
    v=ctx.simple_vertex_array(p,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
    return p,v
candidate=compile_pack(source);baseline=(prog,vao)
old=compile_pack(ns['old'].pack)
settings=dict(vr_pack=3,vr_source_layout=0,vr_flat_mono=1,vr_flat_sbs=1,vr_parallax_strength=0,vr_d3_gain=.02,vr_base_ipd=0,vr_ipd_nudge=0,vr_pk_conv=.5)
canvas=Image.new('RGB',(w*2,h*3+72));pen=ImageDraw.Draw(canvas)
for i in range(3):
    frame=np.stack([.15+.7*xx,.15+.7*yy,.2+.5*((np.floor(xx*16+i)+np.floor(yy*10))%2),np.ones_like(xx)],-1).astype('f4')
    tex.write(frame.tobytes())
    prog,vao=old;a=draw((w,h),settings)
    prog,vao=baseline;b=draw((w,h),settings)
    assert np.array_equal(a,b),'flag off pixels changed'
    prog,vao=candidate;c=draw((w,h),settings)
    assert np.isfinite(c).all() and np.abs(b-c).mean()>0
    print('MEAS frame',i,'off maxerror',float(np.abs(a-b).max()),'on/off meanabs',float(np.abs(b-c).mean()))
    for j,image in enumerate((b,c)):
        canvas.paste(Image.fromarray((np.clip(image[::-1],0,1)*255).astype('uint8')),(j*w,i*(h+24)+24))
    pen.text((4,i*(h+24)+4),f'Synthetic fixed frame {i}: default/off | default-off D enabled, same plane',fill='white')
canvas.save('/downloads/d3-budget-before-after.png')
print('PASS software EGL actual generated shaders, 3 flag-off frames pixel-identical; no depth-model/realism/Mac claim')
