#!/usr/bin/env python3
"""Actual shipped Lua-generated GLSL rendered by Mesa EGL. Supplemental Linux proof, not native acceptance."""
from pathlib import Path
import tempfile,re,json,sys
from lupa import LuaRuntime
import moderngl,numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]) if len(sys.argv)>1 else root/'Tests/Block185/rendered';out.mkdir(parents=True,exist_ok=True)
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''props={};handlers={};mp={msg={info=function()end,warn=function()end,error=function()end},get_time=function()return 0 end,add_periodic_timer=function(t,f)return {kill=function()end}end,add_hook=function()end,observe_property=function()end};mp.get_property=function(k)return props[k]end;mp.get_property_number=mp.get_property;mp.get_property_native=mp.get_property;mp.set_property=function(k,v)props[k]=v end;mp.set_property_number=mp.set_property;mp.set_property_native=mp.set_property;mp.register_script_message=function(k,f)handlers[k]=f end;mp.commandv=function(...)return true end''')
with tempfile.TemporaryDirectory() as d:
 g=lua.globals();g.props['config-dir']=d;g.props['osd-width']=960
 lua.execute((root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text());g.handlers['vr180-look-set-enabled']('true');g.handlers['vr180-look-set-projection']('flat-sbs','1.333333')
 text=next(p.read_text() for p in (Path(d)/'shader').glob('*.glsl') if 'if (vr_flat_sbs > 0.5)' in p.read_text())
 params=re.findall(r'//!PARAM (\w+)\n//!TYPE float\n([^\n]+)',text)
 shader=text[text.index('#define '):]
 head='#version 330\nuniform sampler2D tex;in vec2 uv;out vec4 colour;\n#define HOOKED_pos uv\n#define HOOKED_size vec2(960,360)\n#define target_size vec2(960,360)\n#define HOOKED_tex(p) texture(tex,p)\n'+''.join(f'uniform float {n};\n' for n,v in params)
 ctx=moderngl.create_standalone_context(backend='egl');prog=ctx.program(vertex_shader='#version 330\nin vec2 p;out vec2 uv;void main(){gl_Position=vec4(p,0,1);uv=p*.5+.5;}',fragment_shader=head+shader+'\nvoid main(){colour=hook();}')
 for n,v in params:
  if n in prog:prog[n]=float(v)
 for k,v in {'vr_flat_sbs':1,'vr_eye_aspect':4/3,'vr_gap_frac':0,'blink_sbs_strength':1}.items():
  if k in prog:prog[k]=v
 vbo=ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes());vao=ctx.simple_vertex_array(prog,vbo,'p');fb=ctx.simple_framebuffer((960,360));fb.use()

 # Actual source texture has20px encoded bars inside EACH160px eye.
 a=np.zeros((360,960,3),dtype='u1')
 for eye in [0,1]:a[:,eye*480+60:eye*480+420]=[180,80,40]
 tex=ctx.texture((960,360),3,a.tobytes());tex.use();tex.filter=(moderngl.NEAREST,moderngl.NEAREST)
 prog['vr_eye_aspect']=4/3
 def shot():
  vao.render(moderngl.TRIANGLE_STRIP)
  return np.asarray(Image.frombytes('RGB',(960,360),fb.read(components=3))).copy()
 before=shot()
 prog['vr_source_x']=60/480;prog['vr_source_w']=360/480
 after=shot()
 assert before[180,5].max()==0 and after[180,5].min()>10
 assert before[180,475].max()==0 and after[180,475].min()>10
 Image.fromarray(before).save(out/'before.png');Image.fromarray(after).save(out/'after.png')
 print('PASS actual production GLSL/EGL: encoded left/right bars removed within each eye, seam respected; no native mpv claim')
