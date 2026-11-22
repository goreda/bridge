#!/usr/bin/env python3
"""Actual published GLSL, EGL software GPU. Before/after asymmetric viewport crop,
fixed pixel landmarks, per-eye isolation and head-ray exploration. Not Mac validation."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import re,sys,math,tempfile
from pathlib import Path
import numpy as np,moderngl
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
prefix=(root/'Tests/ThreeDAutoRoute/preview_pack_lua_test.py').read_text().split('packed = run(1)')[0]
exec(compile(prefix,str(root/'Tests/ThreeDAutoRoute/preview_pack_lua_test.py'),'exec'))
text=next(t for t in run(4) if 'vec4 pack_eye(' in t)
# Isolate MAIN from the real first-pass title statistics. Bind its dark fraction explicitly;
# source here is a bright gradient (all25 taps non-dark, so statistics=0 exactly).
text=text[text.index('//!PARAM '):]
params={}
def param(m): params[m[1]]=float(m[2]);return 'uniform float '+m[1]+';'
text=re.sub(r'//!PARAM (\w+)\n//!TYPE float\n([-+0-9.eE]+)',param,text)
text=re.sub(r'^//!.*$','',text,flags=re.M)
ctx=moderngl.create_standalone_context(backend='egl')
vs='#version 330\nin vec2 p;out vec2 HOOKED_pos;void main(){gl_Position=vec4(p,0,1);HOOKED_pos=p*.5+.5;}'
fs='#version 330\nuniform sampler2D image;uniform vec2 HOOKED_size,target_size;in vec2 HOOKED_pos;out vec4 color;vec4 HOOKED_tex(vec2 uv){return texture(image,uv);}vec4 D3_TITLE_tex(vec2 p){return vec4(0);}\n'+text+'\nvoid main(){color=hook();}'
prog=ctx.program(vertex_shader=vs,fragment_shader=fs)
print('GPU',ctx.info['GL_RENDERER'],'published GLSL compiled')
w,h=960,600
xx,yy=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
arr=np.stack([.15+.8*xx,.15+.8*yy,.2+.5*((np.floor(xx*16)+np.floor(yy*10))%2),np.ones_like(xx)],-1).astype('f4')
tex=ctx.texture((w,h),4,arr.tobytes(),dtype='f4');tex.use();tex.filter=(moderngl.LINEAR,moderngl.LINEAR)
vao=ctx.simple_vertex_array(prog,ctx.buffer(np.array([-1,-1,1,-1,-1,1,1,1],dtype='f4').tobytes()),'p')
base=dict(params,vr_gap_frac=0,vr_gap_blur_frac=0,vr_vignette_darken=0,vr_vignette_blur=0,vr_fov=math.radians(135),vr_source_w=1,vr_source_h=1,vr_crop_x=1,vr_crop_y=1,vr_pk_zoom=1,vr_pk_soft=0,vr_d3_gain=.04,vr_flat_sbs=1,vr_flat_mono=1,vr_pack=3,vr_eye_aspect=16/9,blink_sbs_strength=1)
def draw(size,settings):
 fbo=ctx.simple_framebuffer(size,components=4,dtype='f4');fbo.use();ctx.viewport=(0,0,*size)
 for k,v in dict(base,**settings).items():
  if k in prog:prog[k].value=v
 prog['HOOKED_size'].value=(w,h);prog['target_size'].value=size
 vao.render(moderngl.TRIANGLE_STRIP)
 result=np.frombuffer(fbo.read(components=4,dtype='f4'),dtype='f4').reshape(size[1],size[0],4)[:,:,:3].copy()
 # Releasing an FBO does not release its owned renderbuffers in ModernGL.
 for attachment in fbo.color_attachments:attachment.release()
 if fbo.depth_attachment is not None:fbo.depth_attachment.release()
 fbo.release();return result
cases={'plain':dict(vr_plain=1,vr_flat_sbs=0,vr_flat_mono=0,vr_pack=0),'nativeSBS':dict(vr_flat_mono=0,vr_pack=0),'nativeTB':dict(vr_flat_mono=0,vr_pack=0,blink_top_bottom=1),'monoSBS':dict(vr_pack=3),'TB':dict(vr_pack=1),'anaglyph':dict(vr_pack=2),'VR180preview':dict(vr_pack=4),'VR180native':dict(vr_flat_mono=0,vr_flat_sbs=0,vr_pack=0,vr_source_layout=3)}
rows=[]
for name,v in cases.items():
 before=draw((w,h),v)
 anchored=dict(v,vr_surface_w=w,vr_surface_h=h,vr_surface_x=.1,vr_surface_y=-.1)
 after=draw((672,360),anchored)
 # Cropping each local eye canvas by x=.25..95,y=.10..70. Partitions stay current.
 if name=='TB':expected=np.concatenate([before[30:210,240:912],before[330:510,240:912]],axis=0)
 elif name in ('plain','anaglyph'):expected=before[60:420,240:912]
 else:expected=np.concatenate([before[60:420,120:456],before[60:420,600:936]],axis=1)
 err=float(np.abs(after-expected).max());mean=float(np.abs(after-expected).mean())
 # Exclude fixed display gap from native spherical comparison; physical gap is not film content.
 tolerance=.01 if name!='VR180native' else .15
 print('ANCHOR',name,'max',err,'mean',mean)
 assert mean<.001 and err<tolerance,(name,err,mean)
 exploration=dict(anchored)
 if name not in ('VR180native','VR180preview'):
  exploration['vr_fov']=2*math.atan(math.tan(math.radians(67.5))/1.1)
 at_approach=draw((672,360),exploration)
 explored=draw((672,360),dict(exploration,vr_yaw=.30))
 assert np.isfinite(explored).all() and np.abs(explored-at_approach).mean()>.001
 print('PASS',name,'fixed landmarks, fixed source aspect/domain, head ray remains active')
 rows.append((name,before,after,explored))
# Actual reset uniforms, then pixels: no crop/aspect/manual state may leak through Shift+R.
replay_file=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py'
replay_prefix=replay_file.read_text().split('# Independent seeded',1)[0]
ns={'__file__':str(replay_file)};exec(compile(replay_prefix,str(replay_file),'exec'),ns)
for aspect in (4/3,16/9,1.85,2.39):
 replay=ns['Replay'](flat=True);replay.msg('vr180-look-set-projection','flat-2d3d',aspect)
 for i in range(60):replay.tick(i/30);replay.pose(x=.2,y=-.1,z=.2,yaw=.3,roll=.4,fov=110)
 replay.msg('vr180-look-menu-crop','.7|.6|960','.6|.4|600');replay.msg('vr180-look-motion','step',2,1,3)
 replay.msg('vr180-look-full-fit');actual=replay.values()
 # Pure geometry pass: zero disparity/convergence isolates full-fit from192c common crop.
 image=draw((w,h),dict(actual,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0,vr_gap_frac=0,vr_gap_blur_frac=0))
 replay.g.events['start-file']();opening=draw((w,h),dict(replay.values(),vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0,vr_gap_frac=0,vr_gap_blur_frac=0))
 assert np.array_equal(image,opening),'opening/reset pixels differ'
 shift=max(-.8,min(.8,actual.get('vr_parallax_disparity',-.4)*(math.tan(math.radians(45))/math.tan(actual['vr_fov']/2)-1)*actual.get('vr_parallax_strength',.4)+actual.get('vr_base_ipd',0)+actual.get('vr_ipd_nudge',0)))
 exact_fraction=1.0
 for side in (0,1):
  eye=image[:,side*w//2:(side+1)*w//2];mask=eye.sum(axis=-1)>.1
  ys,xs=np.where(mask);width=xs.max()-xs.min()+1;height=ys.max()-ys.min()+1
  assert width/(w/2)>=exact_fraction-2/(w/2),'extra full-fit shrink beyond exact IPD footprint'
  # A coverage mask includes the antialiased pixel on each opposing edge.
  assert abs(width-height*aspect)<=2*max(1,aspect),(aspect,side,width,height)
  samples=eye[mask]
  # Full original film in each eye, including original corner colours within one source pixel.
  tol_x=.8*2/width;tol_y=.8*2/height
  assert samples[:,0].min()<.15+tol_x and samples[:,0].max()>.95-tol_x,(aspect,side,'horizontal source corners missing')
  assert samples[:,1].min()<.15+tol_y and samples[:,1].max()>.95-tol_y,(aspect,side,'vertical source corners missing')
 print('PASS reset GPU full original source/corners, aspect',aspect,'film bbox',width,height,'width fraction',width/(w/2),'minimal IPD fraction',exact_fraction)
 rows.append(('reset originalAR %.3f'%aspect,image,image,image))
# Owner21:05: normal2D must NOT feed one source half to each eye.
# Replay real Lua after a stale VR180 state, then use its real uniforms on the compiled published GLSL.
replay=ns['Replay']();replay.msg('vr180-look-set-projection','vr180','0')
replay.msg('vr180-look-plan-lock','off');replay.msg('vr180-look-set-projection','flat-2d3d',16/9)
replay.msg('vr180-look-set-enabled','true');replay.msg('vr180-look-set-pack',3,1,.5,1,0)
actual=replay.values();assert actual['vr_flat_mono']==1 and actual['vr_flat_sbs']==1 and actual['vr_pack']==3
# Whole-source ownership is independent of the approved convergence support crop.
# Keep the real gap and its committed frame spacing in sync. Zero convergence
# only in this source-ownership probe; reset/crop/tilt gates above remain separate.
source_probe=dict(actual,vr_parallax_strength=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_vignette_darken=0,vr_vignette_blur=0)
for gain in (0,.04):
 image=draw((w,h),dict(source_probe,vr_d3_gain=gain))
 for side in (0,1):
  eye=image[:,side*w//2:(side+1)*w//2];samples=eye[eye[:,:,2]>.699]
  # Blue=.7 checker interiors identify opaque source samples, excluding
  # black coverage AA that can make a half-source red falsely look near zero.
  # Source red gradient uniquely encodes original X, green original Y. Half-frame sampling fails one bound.
  assert samples[:,0].min()<.19 and samples[:,0].max()>.91,(gain,side,'source half split',samples[:,0].min(),samples[:,0].max())
  assert samples[:,1].min()<.20 and samples[:,1].max()>.90,(gain,side,'vertical source crop')
  print('PASS actual Lua+GLSL2D full-frame both eyes gain',gain,'eye',side,'sourceX',(float(samples[:,0].min()),float(samples[:,0].max())))
 rows.append(('2D whole frame gain %.2f'%gain,image,image,image))
# Mutant: treating a2D source as native SBS must fail the full-width assertion.
mutant=draw((w,h),dict(source_probe,vr_flat_mono=0,vr_pack=0,vr_d3_gain=0))
seen=[]
for side in (0,1):
 eye=mutant[:,side*w//2:(side+1)*w//2];samples=eye[eye[:,:,2]>.699]
 seen.append(samples[:,0].min()<.19 and samples[:,0].max()>.91)
assert not any(seen),'half-split mutant escaped test'
print('PASS half-split mutant fails whole-source bound in BOTH eyes')
menu=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(root)).read_text());route=(root/'Sources/gor/Stereo/LookToolsRoute.swift').read_text();auto=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDAutoRoute.swift'+' '):_b.index('// END relocated '+'ThreeDAutoRoute.swift'+'\n')])((_threed_split().path(root)).read_text());coord=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRenderCoordinator.swift'+' '):_b.index('// END relocated '+'ThreeDRenderCoordinator.swift'+'\n')])((_threed_split().path(root)).read_text())
assert 'static let routedMode = "full_sbs"' in auto and 'case .convert2D: return "flat-2d3d"' in route
assert 'store.dispatch(.setOutput(.sbs))' in menu and 'output: OutputMode.parse(prefs.mode) ?? .fullSBS' in coord
assert 'var lastOutput = ThreeDOutput.sbs' in (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDState.swift'+' '):_b.index('// END relocated '+'ThreeDState.swift'+'\n')])((_threed_split().path(root)).read_text()),'reopen lost output state'
print('PASS static default2D is flat2d3d+fullSBS, late resolution preserves explicit output; Mac controller NOT_RUN')
canvas=Image.new('RGB',(1120, len(rows)*150),(20,20,20));pen=ImageDraw.Draw(canvas)
for j,(name,before,after,explored) in enumerate(rows):
 pen.text((4,j*150+4),name+' | before | asymmetric viewport crop | head exploration',fill='white')
 for i,frame in enumerate((before,after,explored)):
  im=Image.fromarray((np.clip(frame[::-1],0,1)*255).astype('uint8'));im.thumbnail((360,125));canvas.paste(im,(i*370,j*150+22))
canvas.save('/downloads/surface-anchor-gpu.png')
print('PASS all fixed-surface GPU comparisons')
