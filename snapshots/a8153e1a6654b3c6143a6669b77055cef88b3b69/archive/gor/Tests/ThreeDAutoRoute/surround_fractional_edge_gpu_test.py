#!/usr/bin/env python3
"""Real published GLSL, fractional film edge profile for white+soft surround."""
from pathlib import Path
import numpy as np,re,math
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
p=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(p.read_text().split("cases={'plain'",1)[0],str(p),'exec'))
C=np.array([.15,.25,.4],dtype='f4')
source=np.empty((h,w,4),dtype='f4');source[:,:,:3]=C;source[:,:,3]=1;tex.write(source.tobytes())
# Instrument the actual generated shader at its return only, to expose its own
# UV and coverage. No independent geometry/coverage implementation in this test.
needle='return mix(background,blink_render(HOOKED_tex(vr_source_layout<2.5 ? blink_clamp(sample_pos,source_right):sample_pos),lid_uv,sample_pos,right,right),coverage);'
assert needle in text
probe=text.replace(needle,'return vec4(surround_uv,film_coverage,1.0);')
probeprog=ctx.program(vertex_shader=vs,fragment_shader='#version 330\nuniform sampler2D image;uniform vec2 HOOKED_size,target_size;in vec2 HOOKED_pos;out vec4 color;vec4 HOOKED_tex(vec2 uv){return texture(image,uv);}vec4 D3_TITLE_tex(vec2 p){return vec4(0);}\n'+probe+'\nvoid main(){color=hook();}')
probevao=ctx.simple_vertex_array(probeprog,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
actualprog,actualvao=prog,vao
fails=[];edges=set();panels=[]
for invert in (0,1):
 for pack in (1,2,3):
  for roll in (0,25,-45):
   for crop in (False,True):
    v=dict(vr_source_layout=0,vr_flat_mono=1,vr_flat_sbs=1,vr_pack=pack,vr_pk_zoom=.673 if crop else .827,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0,vr_gap_frac=0,vr_pk_soft=1,vr_pk_surround_invert=invert,vr_roll=math.radians(roll),vr_head_roll=math.radians(roll))
    if crop:v.update(vr_source_x=.12,vr_source_y=.21,vr_source_w=.71,vr_source_h=.63)
    result=draw((963,601),v)
    prog,vao=probeprog,probevao;geometry=draw((963,601),v);prog,vao=actualprog,actualvao
    q=geometry[:,:,2];mask=(q>.02)&(q<.98)
    if not mask.any():continue
    uv=geometry[:,:,:2];distance=np.linalg.norm(np.maximum(np.maximum(-uv,uv-1),0),axis=2)
    t=np.clip(distance/.65,0,1);fade=.45*(1-t*t*(3-2*t))
    background=C*fade[:,:,None]+invert*(1-fade[:,:,None])
    expected=C*q[:,:,None]+background*(1-q[:,:,None])
    error=np.abs(result-expected).max(-1)
    maximum=float(error[mask].max())
    local=geometry[:,:,:2][mask];idx=np.argmin(np.stack([abs(local[:,0]),abs(1-local[:,0]),abs(local[:,1]),abs(1-local[:,1])],-1),axis=1)
    edges.update(idx.tolist())
    print('fractional edge',invert,pack,roll,crop,'pixels',int(mask.sum()),'max',maximum)
    if maximum>.001:
     bad=np.unravel_index(np.where(mask,error,-1).argmax(),mask.shape);print('worst',bad,'uv,q',geometry[bad],'actual',result[bad],'expect',expected[bad])
    if maximum>.001:fails.append((pack,roll,crop,maximum))
    if invert==1 and pack==3 and roll==25 and crop:
     edgeMask=mask & (np.max(np.maximum(np.maximum(-uv,uv-1),0),axis=2)<.002)
     coordinates=np.argwhere(edgeMask);y,x=coordinates[len(coordinates)//2]
     region=result[max(0,y-18):y+19,max(0,x-36):x+37]
     diff=np.abs(result-expected)*4
     panels=[('Actual white + soft edge',region),('Expected continuous edge',expected[max(0,y-18):y+19,max(0,x-36):x+37]),('Absolute difference x4',diff[max(0,y-18):y+19,max(0,x-36):x+37])]
assert edges=={0,1,2,3},edges
if panels:
 canvas=Image.new('RGB',(730,3*390),(25,25,25));d=ImageDraw.Draw(canvas)
 for i,(label,img) in enumerate(panels):
  d.text((8,i*390+8),label,fill='white');canvas.paste(Image.fromarray(np.uint8(np.clip(img[::-1],0,1)*255)).resize((730,360),Image.Resampling.NEAREST),(0,i*390+30))
 canvas.save('/downloads/surround-fractional-edge.png')
assert not fails,fails
print('PASS all four fractional film edges use soft surround, not a white border; TB/anaglyph/SBS, roll,crop,zoom. Physical Mac NOT_RUN')
