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
 means={};asserts=[]
 for name,level in [('bright',.75),('dark',.08)]:
  y,x=np.mgrid[:360,:960];pattern=level*(.8+.2*((x//8+y//8)%2));a=np.clip(np.repeat(pattern[:,:,None],3,axis=2)*255,0,255).astype('u1');tex=ctx.texture((960,360),3,a.tobytes());tex.use();tex.filter=(moderngl.LINEAR,moderngl.LINEAR)
  def shot(lid,adapt):
   for k,v in {'blink_lid_l':lid,'blink_lid_r':lid,'blink_reopen_l':adapt,'blink_reopen_r':adapt}.items():prog[k]=v
   vao.render(moderngl.TRIANGLE_STRIP);return np.asarray(Image.frombytes('RGB',(960,360),fb.read(components=3))).copy()
  baseline=shot(0,0);off=shot(0,0);assert np.array_equal(baseline,off);asserts.append(name+' lid0 byte equality PASS')
  for label,lid,adapt in [('0',0,0),('0.3',.3,0),('0.7',.7,0),('1',1,0),('reopen100ms',0,.6)]:
   pixels=shot(lid,adapt);Image.fromarray(pixels).save(out/(name+'-'+label+'.png'))
   if lid==1:
    avg=pixels.mean(axis=(0,1));means[name]=float(avg.mean());assert avg[0]>avg[1]>avg[2] and avg.min()>0;asserts.append(name+' closure warm nonzero PASS')
   if label=='reopen100ms':
    assert pixels.mean()>=baseline.mean();assert not np.array_equal(pixels,baseline);asserts.append(name+' reopening blur/residual and >=baseline PASS')
   if lid==.3:
    # Actual pixels: upper covered region boundary, center must lead corners.
    def edge(xx):
     delta=np.abs(pixels[:,xx].astype(float)-baseline[:,xx].astype(float)).mean(axis=1);rows=np.where(delta>level*255*.5)[0];return rows.max() if len(rows) else -1
    # UV y grows up, PNG raw rows use bottom-origin here. Upper boundary lower at center.
    assert edge(240)<edge(12) or np.mean(pixels[260:300,240])<np.mean(pixels[260:300,12]);asserts.append(name+' actual curved edge PASS')
 assert means['bright']>means['dark'];asserts.append('bright glow > dark glow PASS')
 (out/'verdicts.json').write_text(json.dumps({'assertions':asserts,'meanRGB':means,'scope':'actual generated production GLSL via EGL; no native mpv/AppKit acceptance'},indent=2));print('\n'.join(asserts))
