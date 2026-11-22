#!/usr/bin/env python3
"""Production plain2D Lua-published GLSL: automatic full-source tilt fit.
Offscreen software EGL, not a Mac/camera acceptance claim.
"""
from pathlib import Path
import math,numpy as np,os,subprocess
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
# Replay the exact taking shader for a reproducible red-first run.
if os.environ.get('PLAIN_TILT_SOURCE'):
 original_read=Path.read_text
 lua=root/'Resources/vendor/mpv/scripts/vr180-look.lua'
 old=subprocess.check_output(['git','show',os.environ['PLAIN_TILT_SOURCE']+':archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
 Path.read_text=lambda p,*a,**k:old if p==lua else original_read(p,*a,**k)
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
# Encode original source position in colour, so missing source corners cannot hide.
X,Y=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
texture=np.stack([.15+.8*X,.15+.8*Y,np.full_like(X,.5),np.ones_like(X)],-1).astype('f4');tex.write(texture.tobytes())
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
failures=[];frames=[]
for aspect in (4/3,16/9,2.39):
 for deg in (0,25,-45,90,135):
  replay=ns['Replay'](flat=True)
  replay.msg('vr180-look-set-enabled','false');replay.msg('vr180-look-tools-active','true')
  replay.g.props['osd-width']=int(h*aspect);replay.g.props['osd-height']=h
  replay.msg('vr180-look-full-fit');replay.pose(roll=math.radians(deg))
  # No manual zoom command is allowed to rescue ordinary head tilt.
  actual=replay.values()
  assert actual['vr_crop_x']==1 and actual['vr_crop_y']==1 and actual['vr_source_w']==1 and actual['vr_source_h']==1
  assert actual['vr_plain']==1 and actual['vr_roll']==round(math.radians(deg),6)
  settings=dict(actual,vr_plain=1,vr_flat_sbs=0,vr_flat_mono=0,vr_pack=0,vr_roll=math.radians(deg),vr_fov=actual['vr_fov'],vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0)
  image=draw((int(h*aspect),h),settings)
  for cx,cy in ((.15,.15),(.95,.15),(.15,.95),(.95,.95)):
   distance=np.maximum(np.abs(image[:,:,0]-cx),np.abs(image[:,:,1]-cy)).min()
   if distance>.025:failures.append((aspect,deg,cx,cy,float(distance),actual['vr_fov']))
  if aspect==16/9:frames.append((deg,image))
canvas=Image.new('RGB',(600,len(frames)*200),(18,18,18));pen=ImageDraw.Draw(canvas)
for i,(deg,img) in enumerate(frames):
 pen.text((8,i*200+4),'2D full source, tilt %g deg, head tilt; no manual zoom'%deg,fill='white')
 im=Image.fromarray((np.clip(img[::-1],0,1)*255).astype('uint8'));im.thumbnail((590,175));canvas.paste(im,(5,i*200+22))
canvas.save('/downloads/plain194i-auto-fit.png')
print('four-corner cases',15,'failures',len(failures),'first',failures[:5])
assert not failures,failures[:8]
print('PASS all four original corners, tilt25/-45/90/135 without a manual zoom command, 4:3/16:9/2.39')
