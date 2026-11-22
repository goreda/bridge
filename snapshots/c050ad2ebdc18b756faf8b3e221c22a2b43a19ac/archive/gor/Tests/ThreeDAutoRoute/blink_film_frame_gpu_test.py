#!/usr/bin/env python3
"""Actual published GLSL blink mask versus film-local source coordinates, not Mac playback."""
from pathlib import Path
import numpy as np, math
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
xx,yy=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
tex.write(np.stack([xx,yy,np.ones_like(xx),np.ones_like(xx)],-1).astype('f4').tobytes())
settings=dict(vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0,vr_gap_frac=.0125,blink_glow=0,blink_slit_blur=0,blink_contrast=0,blink_lift=0,blink_arc=0,blink_fringe=.01,blink_upper=.92,blink_lower=.08,vr_fov=math.radians(135))
frames=[]
for mode,extra in [('plain',dict(vr_plain=1,vr_pack=0)),('SBS',dict(vr_pack=3)),('TB',dict(vr_pack=1)),('anaglyph',dict(vr_pack=2)),('VRpreview',dict(vr_pack=4))]:
 for deg in [-30,-20,-10,0,10,20,30]:
  v=dict(settings,**extra,vr_roll=math.radians(deg),vr_head_roll=math.radians(deg),vr_cross_eye=1)
  opened=draw((w,h),dict(v,blink_lid_l=0,blink_lid_r=0));closed=draw((w,h),dict(v,blink_lid_l=.45,blink_lid_r=.45))
  # Solid blue channel is coverage. Green gives the actual film-local source Y.
  inside=opened[:,:,2]>.999;source_y=opened[:,:,1];edge=np.minimum((1-.92*.45)-(1-source_y),(1-source_y)-.08*.45)
  t=np.clip((edge+.01)/.02,0,1);expected=t*t*(3-2*t)
  err=np.abs(closed[:,:,2]-expected)[inside]
  print('MEAS',mode,deg,'mean_error',err.mean(),'wrong_pixels',int((err>.1).sum()),'N',inside.sum())
  assert err.mean()<.005,(mode,deg,err.mean())
  # Interior-only excludes the existing blink fringe blend, tested separately unchanged.
  safe=inside & (np.abs(edge)>.04)
  assert np.max(np.abs(closed[:,:,2]-expected)[safe])<.002
  if abs(deg)==30:frames.append((mode,deg,opened,closed))
# Exact open-state parity against the actual previous published generated GLSL.
# Both sources go through the actual Lua shader publisher.
import tempfile,subprocess
baseline=subprocess.check_output(['git','show','75637f45526964ba982e043752d782ba861a8fd1:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
# The source argument avoids mutating the production file during baseline generation.
prefix=(root/'Tests/ThreeDAutoRoute/preview_pack_lua_test.py').read_text().split('packed = run(1)')[0]
with tempfile.TemporaryDirectory() as td:
 oldpath=Path(td)/'vr180-look.lua';oldpath.write_text(baseline)
 prefix=prefix.replace("root / 'Resources/vendor/mpv/scripts/vr180-look.lua'","Path("+repr(str(oldpath))+")")
 ns={'__file__':str(root/'Tests/ThreeDAutoRoute/preview_pack_lua_test.py')}
 exec(compile(prefix,'baseline-publisher','exec'),ns)
 old=next(t for t in ns['run'](4,source=baseline) if 'vec4 pack_eye(' in t)
 old=old[old.index('//!PARAM '):]
 old=re.sub(r'//!PARAM (\w+)\n//!TYPE float\n([-+0-9.eE]+)',lambda m:'uniform float '+m[1]+';',old)
 old=re.sub(r'^//!.*$','',old,flags=re.M)
 oldprog=ctx.program(vertex_shader=vs,fragment_shader='#version 330\nuniform sampler2D image;uniform vec2 HOOKED_size,target_size;in vec2 HOOKED_pos;out vec4 color;vec4 HOOKED_tex(vec2 uv){return texture(image,uv);}vec4 D3_TITLE_tex(vec2 p){return vec4(0);}\n'+old+'\nvoid main(){color=hook();}')
 oldvao=ctx.simple_vertex_array(oldprog,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
 savedprog,savedvao=prog,vao
 for mode,extra in [('plain',dict(vr_plain=1,vr_pack=0)),('SBS',dict(vr_pack=3)),('TB',dict(vr_pack=1)),('anaglyph',dict(vr_pack=2)),('VRpreview',dict(vr_pack=4))]:
  v=dict(settings,**extra,vr_roll=math.radians(30),vr_head_roll=math.radians(30),vr_cross_eye=1)
  new=draw((w,h),dict(v,blink_lid_l=0,blink_lid_r=0))
  prog,vao=oldprog,oldvao;previous=draw((w,h),dict(v,blink_lid_l=0,blink_lid_r=0));oldclosed=draw((w,h),dict(v,blink_lid_l=.45,blink_lid_r=.45));prog,vao=savedprog,savedvao
  assert np.array_equal(new,previous),(mode,'open pixels changed')
  newclosed=draw((w,h),dict(v,blink_lid_l=.45,blink_lid_r=.45))
  assert np.abs(newclosed-oldclosed).mean()>.01,(mode,'old screen-anchored mutant escaped')
  print('PASS previous-published-source mutant rejected and open pixels identical',mode)
from PIL import Image,ImageDraw
proof=Image.new('RGB',(w*2,len(frames)*(h+25)),(20,20,20));pen=ImageDraw.Draw(proof)
for i,(mode,deg,opened,closed) in enumerate(frames):
 y=i*(h+25);pen.text((8,y+5),mode+' '+str(deg)+'deg | actual film source coordinates | film-anchored blink',fill='white')
 for j,img in enumerate([opened,closed]):proof.paste(Image.fromarray((np.clip(img[::-1],0,1)*255).astype('uint8')),(j*w,y+25))
proof.save('/downloads/blink-film-frame.png')
print('PASS35 signed film-local blink masks match actual source Y; old published shader fails; open output pixel-identical. Native Mac playback NOT_RUN.')
