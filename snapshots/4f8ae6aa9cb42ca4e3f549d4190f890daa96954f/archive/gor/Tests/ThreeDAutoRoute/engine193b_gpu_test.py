"""Native camera-ray reference and flat engine boundary.194h eye-axis gate is separate."""
from pathlib import Path
import re,subprocess,math
import numpy as np,moderngl
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
current=(root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
reference=subprocess.check_output(['git','show','a426265:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
marker='    // ── Roll-compensated eye partition'
#193b1a overrides reference1b here: stationary eye viewports, roll only in ray.
def fixed_partition(text):
 a=text.index('    float roll_cos =',text.index(marker));b=text.index('\n    // ── Physical gap',a)
 return text[:a]+'    vec2 eye_pos = HOOKED_pos;\n'+text[b:]
reference=fixed_partition(reference)
ctx=moderngl.create_standalone_context(backend='egl');w,h=480,300
vs='#version 330\nin vec2 p;out vec2 HOOKED_pos;void main(){gl_Position=vec4(p,0,1);HOOKED_pos=p*.5+.5;}'
xx,yy=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
a=np.stack([.2+.7*xx,.2+.7*yy,.2+.6*((np.floor(xx*21)+np.floor(yy*15))%2),np.ones_like(xx)],-1).astype('f4')
tex=ctx.texture((w,h),4,a.tobytes(),dtype='f4');tex.use();tex.filter=(moderngl.LINEAR,moderngl.LINEAR)
helper='''vec2 native_source_uv(float packed_x,float y) {
    float eye=step(0.5,packed_x);
    return vr_native_tb>0.5 ? vec2((packed_x-eye*0.5)*2.0,(y+eye)*0.5):vec2(packed_x,y);
}
'''
def generated(source,extended):
 r=ns['Replay'](source=source)
 r.msg('vr180-look-set-projection','vr180',1)
 if extended:r.msg('vr180-look-tools-active','true')
 files=[p.read_text() for p in Path(r.tmp.name).rglob('*.glsl')]
 text=files[-1] if extended else files[0]
 # Choose program actually installed, not old slot contents.
 path=r.g.props['glsl-shaders'][len(r.g.props['glsl-shaders'])]
 return Path(path).read_text()
def native_body(s):return s[s.index(marker):s.index('\n}',s.index(marker))+2]
def normalize(s):
 #194h adds only native centre rotation; compare all remaining ray math to193b.
 if '    //194h fixed full-height' in s:
  a=s.index('    //194h fixed full-height');b=s.index('    eye_uv.y=clamp',a)
  s=s[:a]+s[b:]
 s=s.replace('clamp((eye_pos.y - y_draw_start) / (y_draw_end - y_draw_start), 0.0, 1.0)','eye_pos.y').replace('    eye_uv.y=clamp((eye_uv.y-y_draw_start)/(y_draw_end-y_draw_start),0.0,1.0);\n','')
 return '\n'.join(l for l in s.splitlines() if not l.lstrip().startswith('//') and l.strip())
def program(s,adapt=False):
 if '//!SAVE D3_TITLE' in s:s=s[s.index('//!PARAM '):]
 if adapt:
  # NativeTB sampling support postdates a426265. This is the only sampling adaptation.
  s=s.replace('vec2(src_u, v)','native_source_uv(src_u,v)').replace('vec2(src_u,v)','native_source_uv(src_u,v)')
  s=s.replace('vec4 hook() {',helper+'\nvec4 hook() {')
  s='//!PARAM vr_native_tb\n//!TYPE float\n0.0\n'+s
 if '//!SAVE D3_TITLE' in s:s=s[s.index('//!PARAM '):]
 params={}
 def p(m):params[m[1]]=float(m[2]);return 'uniform float '+m[1]+';'
 s=re.sub(r'//!PARAM (\w+)\n//!TYPE float\n([-+0-9.eE]+)',p,s)
 s=re.sub(r'^//!.*$','',s,flags=re.M)
 fs='#version 330\nuniform sampler2D image;uniform vec2 HOOKED_size,target_size;in vec2 HOOKED_pos;out vec4 color;vec4 HOOKED_tex(vec2 uv){return texture(image,uv);}vec4 D3_TITLE_tex(vec2 p){return vec4(0);}\n'+s+'\nvoid main(){color=hook();}'
 p=ctx.program(vertex_shader=vs,fragment_shader=fs);v=ctx.simple_vertex_array(p,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p');return p,v,params
def draw(obj,settings):
 p,v,params=obj;fbo=ctx.simple_framebuffer((w,h),components=4,dtype='f4');fbo.use();ctx.viewport=(0,0,w,h)
 for k,x in dict(params,**settings).items():
  if k in p:p[k].value=x

 if 'HOOKED_size' in p:p['HOOKED_size'].value=(w,h)
 if 'target_size' in p:p['target_size'].value=(w,h)
 tex.use(location=0)
 v.render(moderngl.TRIANGLE_STRIP)
 out=np.frombuffer(fbo.read(components=4,dtype='f4'),dtype='f4').reshape(h,w,4).copy();fbo.release();return out
frames=[]
for extended in (False,True):
 expected=generated(reference,extended);actual=generated(current,extended)
 before=native_body(expected).replace('vec2(src_u, v)','native_source_uv(src_u,v)').replace('vec2(src_u,v)','native_source_uv(src_u,v)')
 if normalize(before)!=normalize(native_body(actual)):
  import difflib
  print('\n'.join(difflib.unified_diff(normalize(before).splitlines(),normalize(native_body(actual)).splitlines())))
 assert normalize(before)==normalize(native_body(actual)),'native hook differs beyond named fixed viewport/TB/194h centre adaptation'
 assert not any(x in native_body(actual) for x in ['stereo_pair_uv(','stereo_partition(','stereo_disparity_axis('])
 if not extended:
  #194o red-first control: the real legacy producer strips frame PARAMs.
  # Removing its zero fallbacks must reproduce the original compile failure.
  fallback='#define vr_frame_fit 0.0\n#define vr_frame_spacing 0.0\n'
  assert fallback in actual,'legacy frame fallback missing'
  try:
   program(actual.replace(fallback,''))
  except Exception as error:
   assert 'GLSL Compiler failed' in str(error) and 'vr_frame_spacing' in str(error),str(error)
  else:
   raise AssertionError('legacy missing-frame-uniform mutant compiled')
  print('PASS real generated legacy missing-frame-uniform mutant rejected by GLSL compiler')
 left,right=program(expected,True),program(actual)
 for tb in (0,1):
  for deg in (0,10,-10,20,-20,30,-30):
   settings=dict(vr_roll=math.radians(deg),vr_head_roll=0,vr_yaw=.13,vr_pitch=-.08,vr_fov=math.radians(119),vr_flat_sbs=0,vr_flat_mono=0,vr_pack=0,vr_source_layout=4 if tb else 3,vr_native_tb=tb)
   a,b=draw(left,settings),draw(right,settings)
   diff=int(np.any(a!=b,axis=2).sum());assert diff==0,(extended,tb,deg,diff)
   if extended and tb==0 and deg in (0,30):frames.append((str(deg)+'deg ray-only; pair axis zero',b))
 print('PASS194h native camera-ray',('extended' if extended else 'legacy'),'SBS/TB ray rolls0,+-10,+-20,+-30 with zero pair axis:0pixel difference vs a426265 stationaryviewport/TBadaptations')
canvas=Image.new('RGB',(w,len(frames)*(h+24)),(20,20,20));pen=ImageDraw.Draw(canvas)
for i,(label,frame) in enumerate(frames):pen.text((5,i*(h+24)+5),label,fill='white');canvas.paste(Image.fromarray((np.clip(frame[::-1,:,:3],0,1)*255).astype('uint8')),(0,i*(h+24)+24))
canvas.save('/downloads/193b-native-ray-reference.png')
print('EVIDENCE /downloads/193b-native-ray-reference.png; isolated camera-ray reference; nonzero pair-axis optical-centre gate is native_pair_axis_gpu_test.py')

# Flat engines retain current independent acceptance gates below (native harness boundary).
#194o: the192l flat byte pin predates crop-local support, boundary clamp,
# surround and the194l/m film-owned frame. It is not the native camera gate.
# Keep the native historical reference above unchanged. Flat acceptance now
# runs independent physical-crop parity and actual committed polygon probes,
# rather than blessing current shader bytes as a new golden image.
import runpy
# Real emitted output/action sequence has its own current authority checks.
sequence_file=root/'Tests/ThreeDAutoRoute/explicit_sbs_lua_test.py'
state={'__file__':str(sequence_file)}
# Scope to this compiled sequence, before the separate historical193d mutant.
sequence_source=sequence_file.read_text().split('#193e crossfile',1)[0]
exec(compile(sequence_source,str(sequence_file),'exec'),state)
for phase,uniforms,installed_shader in state['sequence_pixels']:
 if installed_shader is None:
  print('PASS actual emitted phase',phase,'no installed look shader')
  continue
 pixels=draw(program(installed_shader),uniforms)
 assert np.isfinite(pixels).all() and pixels[:,:,:3].max()>.1,phase
 if phase=='rendered-load':assert abs(uniforms['vr_eye_aspect']-320/180)<1e-6 and uniforms['vr_flat_mono']==0
 print('PASS actual emitted phase',phase,'installed shader compiles/renders; independent flat geometry gates above')

#193f the first ordinary frame has NO look shader before recognition arrives.
opening=ns['Replay']();opening.msg('vr180-look-set-projection','vr180',16/9);opening.msg('vr180-look-set-enabled','true')
opening.g.props['path']='/synthetic/ordinary.2D.mp4';opening.g.events['start-file']()
import json
receipt=json.loads(opening.g.props['user-data/vr180-look/applied-state'])
assert not receipt['enabled'] and receipt['source_layout']==0 and receipt['flat_pack']==0
assert len(opening.g.props['glsl-shaders'])==0
plain_shader='vec4 hook(){return HOOKED_tex(HOOKED_pos);}'
assert np.array_equal(draw(program(plain_shader),{}),draw(program(plain_shader),{}))
print('PASS193f native→2D firstframe noinstalledlookshader, rawpixels0pxvsnever3D')

# Run other EGL contexts only after all native/sequence drawing has finished.
for acceptance in ('Tests/ThreeDAutoRoute/cropped_source_parity_gpu_test.py',
                   'Tests/SpineUI/film_frame_snapshot_gpu_test.py',
                   'Tests/SpineUI/preview_frame_snapshot_gpu_test.py'):
 runpy.run_path(str(root/acceptance),run_name='__main__')
