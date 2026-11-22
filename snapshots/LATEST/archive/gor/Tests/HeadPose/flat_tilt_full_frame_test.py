#!/usr/bin/env python3
"""Production Lua-published GLSL: all four original source corners under tilt.
Offscreen software EGL, not a Mac/camera acceptance claim.
"""
from pathlib import Path
import math,numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
# Encode original source position in colour, so missing source corners cannot hide.
X,Y=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
texture=np.stack([.15+.8*X,.15+.8*Y,np.full_like(X,.5),np.ones_like(X)],-1).astype('f4');tex.write(texture.tobytes())
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
# Flat rails apply at pose ingestion, final uniform publication, key step and held key.
for native in (False,True):
 replay=ns['Replay'](flat=not native)
 if native:replay.msg('vr180-look-set-projection','vr180','0')
 limit=157.5 if native else 179.0
 replay.pose(fov=179)
 assert abs((math.degrees(replay.values()['vr_fov'])+(0 if native else replay.values().get('vr_manual_view',0)))-limit)<.0001
 replay.msg('vr180-look-full-fit');replay.pose()
 replay.msg('vr180-look-motion','step',0,0,-100)
 assert abs((math.degrees(replay.values()['vr_fov'])+(0 if native else replay.values().get('vr_manual_view',0)))-limit)<.0001
 replay.msg('vr180-look-full-fit');replay.pose()
 for i in range(120):
  replay.msg('vr180-look-motion','hold',0,0,-1);replay.tick(i/60)
 assert abs((math.degrees(replay.values()['vr_fov'])+(0 if native else replay.values().get('vr_manual_view',0)))-limit)<.0001
 print('PASS actual Lua pose/step/held maximum',limit,'native',native)
failures=[];frames=[]
for aspect in (4/3,16/9,2.39):
 for deg in (0,25,-45,90,135):
  replay=ns['Replay'](flat=True)
  replay.msg('vr180-look-set-enabled','false');replay.msg('vr180-look-tools-active','true')
  replay.g.props['osd-width']=int(h*aspect);replay.g.props['osd-height']=h
  replay.g.props['video-params/aspect']=aspect
  replay.pose(roll=math.radians(deg))
  # Actual existing menu-minus route. Exhaust the old spherical FOV ceiling.
  replay.msg('vr180-look-motion','step',0,0,-100)
  actual=replay.values()
  assert actual['vr_crop_x']==1 and actual['vr_crop_y']==1 and actual['vr_source_w']==1 and actual['vr_source_h']==1
  # Stop at an adequate rotate-aware fit, rather than testing an unreadably tiny frame.
  bound=max(abs(math.cos(math.radians(deg)))+abs(math.sin(math.radians(deg)))/aspect,
            abs(math.cos(math.radians(deg)))+abs(math.sin(math.radians(deg)))*aspect)
  fit=1/bound
  fit_fov=2*math.atan(math.tan(math.radians(67.5))/(fit*.9))
  permitted=actual['vr_fov']
  replay.msg('vr180-look-nudge',0,0,math.degrees(fit_fov)-math.degrees(permitted))
  actual=replay.values()
  #194p separates flat manual camera from tracked FOV. The combined camera remains capped.
  combined=math.degrees(actual['vr_fov'])+actual.get('vr_manual_view',0)
  assert 20<=combined<=179.0001
  assert actual['vr_fov']==permitted
  settings=dict(actual,vr_plain=1,vr_flat_sbs=0,vr_flat_mono=0,vr_pack=0,vr_roll=math.radians(deg),vr_fov=actual['vr_fov'],vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0)
  image=draw((int(h*aspect),h),settings)
  for cx,cy in ((.15,.15),(.95,.15),(.15,.95),(.95,.95)):
   distance=np.maximum(np.abs(image[:,:,0]-cx),np.abs(image[:,:,1]-cy)).min()
   if distance>.025:failures.append((aspect,deg,cx,cy,float(distance),permitted))
  if aspect==16/9:frames.append((deg,image))
canvas=Image.new('RGB',(600,len(frames)*200),(18,18,18));pen=ImageDraw.Draw(canvas)
for i,(deg,img) in enumerate(frames):
 pen.text((8,i*200+4),'2D full source, tilt %g deg, manual zoom-out to full frame'%deg,fill='white')
 im=Image.fromarray((np.clip(img[::-1],0,1)*255).astype('uint8'));im.thumbnail((590,175));canvas.paste(im,(5,i*200+22))
canvas.save('/downloads/flat-tilt-full-frame.png')
print('four-corner cases',15,'failures',len(failures),'first',failures[:5])
assert not failures,failures[:8]
print('PASS all four original corners, tilt25/-45/90/135 reached by actual manual zoom-out, 4:3/16:9/2.39')
