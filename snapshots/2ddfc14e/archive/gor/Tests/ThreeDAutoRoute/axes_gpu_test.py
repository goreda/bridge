#!/usr/bin/env python3
"""Lua projection/output primitives and generated GLSL; software EGL, not Mac.
This directly tests Lua layout primitives. It is not the source/output plan:
Swift maps a native SOURCE to flat-sbs/flat-tb before explicit flat OUTPUT.
Tests/ThreeDState/run.py measures that production output-first mapping.
"""
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
text=(root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py').read_text().split("cases={'plain'",1)[0]
exec(compile(text,str(root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'),'exec'))
ns={ '__file__':str(root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py') }
text=(root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py').read_text().split('# Independent seeded',1)[0]
exec(compile(text,ns['__file__'],'exec'),ns)
Replay=ns['Replay'];fails=[];rows=[]
def check(name,condition):
 print(('PASS ' if condition else 'FAIL ')+name)
 if not condition:fails.append(name)
# Bright unequal-eye patterns: R encodes original X, G original Y, B is the source-eye ID.
xx,yy=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
mono=np.stack([.2+.7*xx,.2+.7*yy,np.full_like(xx,.4),np.ones_like(xx)],-1).astype('f4')
def packed(tb=False):
 a=mono.copy()
 if tb:
  a[:,:,1]=.2+.7*np.mod(yy*2,1);a[:,:,2]=np.where(yy<.5,.25,.75)
 else:
  a[:,:,0]=.2+.7*np.mod(xx*2,1);a[:,:,2]=np.where(xx<.5,.25,.75)
 return a
sources=[('2d','flat-2d3d',0,mono),('sbs-full','flat-sbs',1,packed()),('sbs-half','flat-sbs',1,packed()),('tb','flat-tb',2,packed(True)),('vr180-sbs','vr180',3,packed()),('vr180-tb','vr180-tb',4,packed(True)),('vr360-mono','vr360-mono',5,mono),('vr360-tb','vr360-tb',6,packed(True))]
outputs=[('sbs',3),('half-sbs',3),('tb',1),('anaglyph',2),('vr180',3)]
for name,kind,layout,source in sources:
 tex.write(source.tobytes());r=Replay();r.msg('vr180-look-plan-lock','off');r.msg('vr180-look-set-projection',kind,16/9)
 for out,pack in outputs:
  r.msg('vr180-look-set-output',{'sbs':'full_sbs','half-sbs':'half_sbs','tb':'over_under','anaglyph':'anaglyph','vr180':'vr180'}[out]);r.msg('vr180-look-set-pack',0 if layout>=3 else pack,1,0,1,0);v=r.values()
  expected_pack=0 if layout>=3 else pack
  native_flags=(v.get('vr_flat_mono')==0 and v.get('vr_flat_sbs')==0) if layout>=3 else True
  check(name+'->'+out+' real Lua source/output uniforms',v.get('vr_source_layout')==layout and v.get('vr_pack')==expected_pack and native_flags)
  image=draw((w,h),dict(v,vr_pk_soft=0,vr_d3_gain=0,vr_swap_eyes=0,vr_gap_frac=0,vr_gap_blur_frac=0,vr_vignette_darken=0))
  check(name+'->'+out+' finite nonblack pixels',np.isfinite(image).all() and image.mean()>.01)
  if layout>=3:
   # Native sources stay on the native engine (pack 0), so there is no output
   # partition to inspect. The original packed eye ID must remain in its own
   # source half instead of being reinterpreted or cross-packed.
   if layout==3:samples=[image[h//2-2:h//2+2,w//4-2:w//4+2],image[h//2-2:h//2+2,3*w//4-2:3*w//4+2]];expected=[.25,.75]
   elif layout in (4,6):samples=[image[h//2-2:h//2+2,w//4-2:w//4+2],image[h//2-2:h//2+2,3*w//4-2:3*w//4+2]];expected=[.25,.75] # spherical output is SBS, source is TB
   else:samples=[image[h//2-2:h//2+2,w//2-2:w//2+2]];expected=[.4]
   for eye_i,sample in enumerate(samples):
    check(name+'->'+out+' native source eye'+str(eye_i)+' identity',abs(float(sample[:,:,2].mean())-expected[eye_i])<.04)
   eyes=[]
  elif pack in (3,4):eyes=[image[:,:w//2],image[:,w//2:]]
  elif pack==1:eyes=[image[:h//2],image[h//2:]]
  else:eyes=[]
  for eye_i,eye in enumerate(eyes):
   # Converted flat outputs are partitioned; each partition must preserve the
   # baked source eye identity.
   c=eye[eye.shape[0]//2-2:eye.shape[0]//2+2,eye.shape[1]//2-2:eye.shape[1]//2+2]
   expected=.4 if layout==0 else (.25 if eye_i==0 else .75)
   check(name+'->'+out+' eye'+str(eye_i)+' baked identity',abs(float(c[:,:,2].mean())-expected)<.04)
  if out in ('sbs','vr180'):rows.append((name+' -> '+out,image))
 # Real disable must win even after pending projection/output updates.
 r.msg('vr180-look-set-enabled','false');r.msg('vr180-look-set-projection',kind,16/9)
 check(name+' OFF stays disabled after projection update',r.g.props['user-data/vr180-look/enabled']==False)
 #193e preserves explicit independent plain-head tools after an Off action.
 # This is not a late persisted effect within an Off applier batch; the compiled
 # applier test separately proves that batch finalization removes its shader.
 r.msg('vr180-look-tools-active','true');r.msg('vr180-look-full-fit')
 installed=r.g.props['glsl-shaders']
 check(name+' explicit plain head tools install plain shader without 3D',installed is not None and len(installed)==1 and r.values().get('vr_plain')==1 and not r.g.props['user-data/vr180-look/enabled'])
 r.msg('vr180-look-set-enabled','false')
 installed=r.g.props['glsl-shaders']
 check(name+' repeated Off removes explicit plain tools shader',installed is None or len(installed)==0)
 # Actual-player raw original pixels are covered by off_full_frame_test.py, not this uninstalled GLSL.

 # Full360 wrap: yaw +/-2pi identical to neutral, including seam neighbourhoods.
 if layout>=5:
  # Off cleared source layout by contract. Reapply the current film plan first.
  r.msg('vr180-look-set-projection',kind,16/9);r.msg('vr180-look-set-enabled','true');r.msg('vr180-look-set-output','full_sbs');r.msg('vr180-look-set-orientation',0,0,135,0,0,0,0,0)
  v=r.values();a=draw((w,h),dict(v,vr_swap_eyes=0,vr_gap_frac=0,vr_gap_blur_frac=0))
  for i in range(120):r.tick(i/30);r.pose(yaw=6.283185307179586)
  b=draw((w,h),dict(r.values(),vr_swap_eyes=0,vr_gap_frac=0,vr_gap_blur_frac=0))
  check(name+'360 longitude wraps after full turn',float(np.abs(a-b).mean())<.001)
# Full live Swift signs -> uniform -> actual flat GLSL samples. Not camera validation.
import sys,math
sys.path.insert(0,str(root/'tools/head_pose'))
import pose_signs
tex.write(mono.tobytes())
for path,extra in [('Off+effects',dict(vr_plain=1,vr_pack=0)),('flatSBS',dict(vr_plain=0,vr_pack=3))]:
 neutral=dict(vr_source_layout=0,vr_flat_mono=1,vr_d3_gain=0,vr_yaw=0,vr_pitch=0,vr_roll=0,vr_head_x=0,vr_head_y=0,vr_head_z=0,vr_fov=math.radians(135),**extra)
 a=draw((w,h),neutral)
 for action,axis,expected in [('look right',0,-1),('look left',0,1),('look down',1,-1),('look up',1,1),('move right',0,-1),('move up',1,1)]:
  uniforms=pose_signs.chain(action);uniforms['vr_fov']=math.radians(uniforms['vr_fov']);uniforms.pop('ipd_nudge')
  b=draw((w,h),dict(neutral,**uniforms))
  delta=float((b[h//2-2:h//2+2,w//4-2:w//4+2,axis]-a[h//2-2:h//2+2,w//4-2:w//4+2,axis]).mean())
  check(path+' live Swift->flat GPU '+action,delta*expected>.005)
canvas=Image.new('RGB',(1000,len(rows)*150),(20,20,20));p=ImageDraw.Draw(canvas)
for i,(name,image) in enumerate(rows):
 p.text((5,i*150+4),name,fill='white');im=Image.fromarray((np.clip(image[::-1],0,1)*255).astype('uint8'));im.thumbnail((960,125));canvas.paste(im,(5,i*150+22))
canvas.save('/downloads/three-d-axes-gpu.png')
# Soft is an outside-only blurred gradient, never a filter over film pixels.
tex.write(mono.tobytes())
v=dict(vr_source_layout=0,vr_flat_mono=1,vr_flat_sbs=1,vr_pack=3,vr_pk_zoom=.65,vr_pk_soft=0,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0,vr_gap_frac=.0125,vr_gap_blur_frac=0)
black=draw((w,h),v);soft=draw((w,h),dict(v,vr_pk_soft=1))
inside=black.max(axis=2)>.1
check('soft surround original film pixels exactly unchanged',np.array_equal(soft[inside],black[inside]))
outside=black.max(axis=2)<.001
check('soft surround visibly fills outside only',float(soft[outside].mean())>.005)
check('black surround remains actual black outside',float(black[outside].max())<.001)
check('soft surround stays dimmer than film',float(soft[outside].max())<.45)
from PIL import ImageDraw
sur=Image.new('RGB',(w*2,h+24),(20,20,20));labels=ImageDraw.Draw(sur)
for j,(label,image) in enumerate([('Black surround',black),('Soft blurred gradient, unchanged film',soft)]):
 labels.text((j*w+5,5),label,fill='white');sur.paste(Image.fromarray((np.clip(image[::-1],0,1)*255).astype('uint8')),(j*w,24))
sur.save('/downloads/soft-surround-outside-only.png')
# Opposite solid eyes expose even half-pixel bilinear leakage in the blurred exterior.
for layout in (1,2):
 stereo=np.zeros((h,w,4),dtype='f4');stereo[:,:,3]=1
 if layout==1:stereo[:,:w//2,0]=1;stereo[:,w//2:,2]=1
 else:stereo[:h//2,:,0]=1;stereo[h//2:,:,2]=1
 tex.write(stereo.tobytes())
 vals=dict(v,vr_source_layout=layout,vr_flat_mono=0,vr_pk_soft=0)
 dark=draw((w,h),vals);glow=draw((w,h),dict(vals,vr_pk_soft=1));outer=dark.max(axis=2)<.001
 check('soft blur exact source-eye isolation layout%d'%layout,float(np.minimum(glow[:,:,0],glow[:,:,2])[outer].max())<1e-7)
 check('soft blur visible with packed source layout%d'%layout,float(glow[outer].mean())>.001)
print('A axes softwareGPU failures',len(fails),'native Mac acceptance NOT_RUN')
raise SystemExit(bool(fails))
