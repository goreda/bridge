#!/usr/bin/env python3
"""Owner-confirmed192l whole-frame output parity: real generated Lua+GLSL.
192p changed accepted alignment/divider/tilt; keep192l pixels, not a new axis oracle.
Software boundary evidence, not Mac playback or true physical motion labels.
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import math,re,subprocess,numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/zoom_content_gpu_test.py'
exec(compile(f.read_text().split('for deg in (0,20,-20):')[0],str(f),'exec'))
current=(root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
broken=subprocess.check_output(['git','show','f1d7e78:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
restoredOnly=current.replace('float delta=vr_roll-angle;','float delta=0.0;').replace('float bound_w=spacing*abs(cos(angle))','float bound_w=spacing*abs(cos(vr_roll*(vr_cross_eye>0.5 ? 1.0:-1.0)))').replace('float bound_h=spacing*abs(sin(angle))','float bound_h=spacing*abs(sin(vr_roll*(vr_cross_eye>0.5 ? 1.0:-1.0)))').replace('float angle=-vr_head_roll*(vr_cross_eye>0.5 ? 1.0:-1.0);','float angle=-vr_roll*(vr_cross_eye>0.5 ? 1.0:-1.0);')
def build(src):
 text=next(t for t in run(4,source=src) if 'vec4 pack_eye(' in t);text=text[text.index('//!PARAM '):]
 text=re.sub(r'//!PARAM (\w+)\n//!TYPE float\n([-+0-9.eE]+)',lambda m:'uniform float '+m[1]+';',text)
 text=re.sub(r'^//!.*$','',text,flags=re.M)
 shader='#version 330\nuniform sampler2D image;uniform vec2 HOOKED_size,target_size;in vec2 HOOKED_pos;out vec4 color;vec4 HOOKED_tex(vec2 uv){return texture(image,uv);}vec4 D3_TITLE_tex(vec2 p){return vec4(0);}\n'+text+'\nvoid main(){color=hook();}'
 p=ctx.program(vertex_shader=vs,fragment_shader=shader)
 return p,ctx.simple_vertex_array(p,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
fbo=ctx.simple_framebuffer((w,h),components=4,dtype='f4')
def draw(size,settings):
 fbo.use();ctx.viewport=(0,0,w,h)
 for k,v in dict(base,**settings).items():
  if k in prog:prog[k].value=v
 prog['HOOKED_size'].value=(w,h);prog['target_size'].value=(w,h);vao.render(moderngl.TRIANGLE_STRIP)
 return np.frombuffer(fbo.read(components=4,dtype='f4'),dtype='f4').reshape(h,w,4)[:,:,:3].copy()
corner=np.ones((h,w,4),dtype='f4');kx,ky=round(w*.08),round(h*.08)
colors=[(.95,.12,.12),(.12,.95,.12),(.12,.12,.95),(.95,.95,.12)]
for (ys,xs),color in zip([(slice(0,ky),slice(0,kx)),(slice(0,ky),slice(w-kx,w)),(slice(h-ky,h),slice(0,kx)),(slice(h-ky,h),slice(w-kx,w))],colors):corner[ys,xs,:3]=color

def counts(image):
 rr,g,b=np.moveaxis(image,-1,0)
 return np.array([((rr>.7)&(g<.4)&(b<.4)).sum(),((g>.7)&(rr<.4)&(b<.4)).sum(),((b>.7)&(rr<.4)&(g<.4)).sum(),((rr>.7)&(g>.7)&(b<.4)).sum()])
settings=dict(common,vr_fov=math.radians(135),vr_head_z=0,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0,vr_gap_frac=.0125,vr_gap_blur_frac=0)

reference=subprocess.check_output(['git','show','6834cff28ad0ae49e8c062d61658513eddf998f8:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
# The newer AppKit '+' intentionally replaces the old green shader mark only.
def without_green(src):
 src=re.sub(r'bool calibration_mark\(vec2 uv,float aspect\) \{.*?\n\}\n\n','',src,flags=re.S)
 return '\n'.join(l for l in src.split('\n') if 'if(calibration_mark(' not in l and '&& calibration_mark(' not in l)
reference=without_green(reference)
#193b separates native ray-only geometry; its reference test owns that engine.
assert current[current.index('vec2 stereo_pair_uv'):current.index('float screen_coverage')]==reference[reference.index('vec2 stereo_pair_uv'):reference.index('float screen_coverage')]
print('PASS flat pair/disparity helpers byte-identical192l; native owned byengine193b_gpu_test')
# Black surround preserves the accepted film/reference exactly; soft exterior has its own outside-only GPU gate.
# Whole-film UV field and textured colour film. Neither is a centre-marker oracle.
X,Y=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
uvfilm=np.stack([X,Y,np.full_like(X,.7),np.ones_like(X)],-1).astype('f4')
film=np.stack([.5+.45*np.sin(X*83)*np.cos(Y*31),.5+.45*np.sin(Y*73),.5+.45*np.cos(X*47+Y*59),np.ones_like(X)],-1).astype('f4')
cases=[]
for native in (False,):
 for cross in (0,1):
  for sign in (-1,1):
   for blink in (0,.65):cases.append((native,cross,sign,blink))
images={};uniforms={};count=0
for name,src in [('192l',reference),('repair',current),('failed192p',broken)]:
 prog,vao=build(src)
 for native,cross,sign,blink in cases:
  r=ns['Replay'](flat=not native,source=src)
  if native:r.msg('vr180-look-set-projection','vr180',0)
  # film roll != pre-follow roll != native raw roll, all signed.
  r.msg('vr180-look-set-orientation',.03,-.02,119,sign*.1,.02,.01,-.01,0,'none','fov-unavailable',0,sign*.4,sign*.3)
  values=r.values()
  if name=='192l':uniforms[(native,sign)]=values.copy()
  if name=='repair':assert values==uniforms[(native,sign)],('uniform mismatch',native,sign)
  values.update(vr_pk_soft=0,vr_cross_eye=cross,vr_swap_eyes=cross,vr_pack=3,vr_source_layout=3 if native else 0,vr_flat_sbs=0 if native else 1,vr_flat_mono=0 if native else 1,blink_lid_l=blink,blink_lid_r=blink*.8,vr_d3_gain=0,vr_base_ipd=.16,vr_parallax_strength=0,vr_gap_frac=.0125,vr_gap_blur_frac=0)
  for pattern,source in [('UV',uvfilm),('textured',film)]:
   tex.write(source.tobytes());im=draw((w,h),dict(settings,**values));key=(native,cross,sign,blink,pattern)
   if name=='192l':images[key]=im
   elif name=='repair':assert np.array_equal(images[key],im),('whole-frame mismatch',key);count+=1
   elif not native and blink==0 and cross==1 and sign==1 and pattern=='textured':
    pixels=int(np.any(images[key]!=im,axis=2).sum());assert pixels>10000
    print('MEAS failed192p vs192l changed pixels',pixels,'of',w*h)
    before=images[key];after=im
canvas=Image.new('RGB',(w,2*(h+30)),(22,22,22));pen=ImageDraw.Draw(canvas)
for i,(label,img) in enumerate([('Owner-confirmed192l = restored current whole frame',before),('Failed192p same inputs, film .1rad / fusion .4rad',after)]):
 y=i*(h+30);pen.text((8,y+8),label,fill='white');canvas.paste(Image.fromarray((np.clip(img[::-1],0,1)*255).astype('uint8')),(0,y+30))
canvas.save('/downloads/192r-192l-whole-frame.png')
features=(_pp_split().path(root,'PPController_Features.swift')).read_text()
assert 'let pairRoll=projectionKind.hasPrefix("vr") ? (direction * (pose.fusionRoll ?? pose.roll)):roll' in features
print('PASS',count,'whole-frame UV/textured flat converted cross+parallel signed tilt/blink renders EXACT192l; actual Lua uniforms identical; subtitle axis192l. Mac acceptance pending')

#192t actual plain2D activation, selectedshader and signed pixel motion regression.
parent=subprocess.check_output(['git','show','0fb75b9:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
for name,src in [('broken',parent),('repair',current)]:
 r=ns['Replay'](flat=True,source=src);r.msg('vr180-look-set-enabled','false');r.msg('vr180-look-tools-active','true');r.msg('vr180-look-set-orientation',0,0,135,.2,0,0,0,0)
 v=r.values();print(name,'vr_plain',v.get('vr_plain'),'shader_count',len(r.g.props['glsl-shaders']))
 if name=='broken':assert v.get('vr_plain',0)==0;continue
 assert v['vr_plain']==1 and r.g.props['user-data/vr180-look/enabled']==False
 files=list(Path(r.tmp.name).rglob('*.glsl'));shader=next(p.read_text() for p in files if 'if(vr_plain>0.5)' in p.read_text())
 # Compile the actual shader selected by the Off->explicit-tools transition.
 shader=shader[shader.index('//!PARAM '):];shader=re.sub(r'//!PARAM (\w+)\n//!TYPE float\n([-+0-9.eE]+)',lambda m:'uniform float '+m[1]+';',shader);shader=re.sub(r'^//!.*$','',shader,flags=re.M)
 fs='#version 330\nuniform sampler2D image;uniform vec2 HOOKED_size,target_size;in vec2 HOOKED_pos;out vec4 color;vec4 HOOKED_tex(vec2 uv){return texture(image,uv);}vec4 D3_TITLE_tex(vec2 p){return vec4(0);}\n'+shader+'\nvoid main(){color=hook();}'
 prog=ctx.program(vertex_shader=vs,fragment_shader=fs);vao=ctx.simple_vertex_array(prog,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
 tex.write(texture.tobytes());r.msg('vr180-look-set-orientation',0,0,135,0,0,0,0,0);rest=draw((w,h),r.values());frames=[('neutral',rest)]
 for label,args in [('tilt',(0,0,135,.2,0,0,0,0)),('left',(-.15,0,135,0,0,0,0,0)),('right',(.15,0,135,0,0,0,0,0)),('up',(0,.15,135,0,0,0,0,0)),('down',(0,-.15,135,0,0,0,0,0)),('closer',(0,0,120,0,0,0,0,.2)),('farther',(0,0,150,0,0,0,0,-.2)),('translateX',(0,0,135,0,0,.1,0,0)),('translateY',(0,0,135,0,0,0,.1,0))]:
  r.msg('vr180-look-set-orientation',*args);im=draw((w,h),r.values());delta=np.abs(im-rest).mean();assert delta>.0001;print('PASS actual plain2D Lua selected shader motion',label,delta);frames.append((label,im))
 def geometry(im):
  points=[]
  for ch in (0,1,2):
   weight=np.maximum(im[:,:,ch]-.02,0);yy,xx=np.indices(weight.shape);points.append(np.array([(xx*weight).sum()/weight.sum(),(yy*weight).sum()/weight.sum()]))
  return points[2],np.linalg.norm(points[1]-points[0]),math.atan2((points[1]-points[0])[1],(points[1]-points[0])[0])
 g={label:geometry(im) for label,im in frames};center,width,angle=g['neutral']
 assert g['left'][0][0]>center[0] and g['right'][0][0]<center[0]
 assert g['up'][0][1]<center[1] and g['down'][0][1]>center[1]
 assert g['closer'][1]>width and g['farther'][1]<width and abs(g['tilt'][2]-angle)>.1
 print('PASS measured signed XY directions, nonzero tilt, closer larger/farther smaller; centre/scale/angle from rendered pixels')
 canvas=Image.new('RGB',(w*2,math.ceil(len(frames)/2)*(h+25)),(20,20,20));pen=ImageDraw.Draw(canvas)
 for i,(label,im) in enumerate(frames):
  x=(i%2)*w;y=(i//2)*(h+25);pen.text((x+8,y+5),label,fill='white');canvas.paste(Image.fromarray((np.clip(im[::-1],0,1)*255).astype('uint8')),(x,y+25))
 canvas.save('/downloads/192t-plain-head-motion.png')
 r.msg('vr180-look-tools-active','false');assert len(r.g.props['glsl-shaders'])==0
 r.msg('vr180-look-tools-active','true');r.msg('vr180-look-set-enabled','false');assert len(r.g.props['glsl-shaders'])==0
 print('PASS independent toolsOFF and explicit3DOff remove shader; enabled state remainsfalse')
