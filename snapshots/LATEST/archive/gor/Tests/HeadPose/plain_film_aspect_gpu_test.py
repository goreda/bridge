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
for window in (4/3,16/9,2.39,.75):
 for film in (4/3,16/9,2.39):
  for deg in (0,25,-45,90,135):
   replay=ns['Replay'](flat=True)
   replay.msg('vr180-look-set-enabled','false');replay.msg('vr180-look-tools-active','true')
   replay.g.props['osd-width']=int(h*window);replay.g.props['osd-height']=h
   replay.g.props['video-params/aspect']=film
   replay.msg('vr180-look-full-fit');replay.pose(roll=math.radians(deg))
   actual=replay.values()
   assert abs(actual.get('vr_plain_aspect',0)-film)<1e-6,('film aspect uniform',window,film,actual.get('vr_plain_aspect'))
   image=draw((int(h*window),h),dict(actual,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0))
   for cx,cy in ((.15,.15),(.95,.15),(.15,.95),(.95,.95)):
    distance=np.maximum(np.abs(image[:,:,0]-cx),np.abs(image[:,:,1]-cy)).min()
    if distance>.025:failures.append((window,film,deg,cx,cy,float(distance)))
   if deg==0:
    mask=image[:,:,2]>.49;ys,xs=np.where(mask)
    shown=(xs.max()-xs.min()+1)/(ys.max()-ys.min()+1)
    assert abs(shown-film)<.012,(window,film,shown)
   if window==16/9 and film==4/3:frames.append((deg,image))
canvas=Image.new('RGB',(600,len(frames)*200),(18,18,18));pen=ImageDraw.Draw(canvas)
for i,(deg,img) in enumerate(frames):
 pen.text((8,i*200+4),'4:3 film in16:9 window; tilt %g; no manual zoom'%deg,fill='white')
 im=Image.fromarray((np.clip(img[::-1],0,1)*255).astype('uint8'));im.thumbnail((590,175));canvas.paste(im,(5,i*200+22))
canvas.save('/downloads/plain194q-film-window.png')
print('actual Lua+GLSL mismatch cases',60,'corner failures',len(failures),failures[:5])
assert not failures,failures[:8]
# Actual Lua fallback and accepted-crop paths, independent of model equations.
for props,crop,expected in [({'video-params/aspect':2.39},None,2.39),({'video-params/dw':1440,'video-params/dh':1080},None,4/3),({'video-params/w':720,'video-params/h':576,'video-params/par':16/15},None,4/3),({'video-params/w':1920,'video-params/h':1080,'video-params/par':1},('.1','.2','.8','.6'),(16/9)*.8/.6)]:
 replay=ns['Replay'](flat=True);replay.msg('vr180-look-set-enabled','false');replay.msg('vr180-look-tools-active','true')
 for k,v in props.items():replay.g.props[k]=v
 if crop:replay.msg('vr180-look-bar-crop',*crop)
 replay.pose();assert abs(replay.values()['vr_plain_aspect']-expected)<1e-6,(props,crop,replay.values()['vr_plain_aspect'],expected)
print('PASS60 actual film/window aspect and tilt cases; display-size/SAR/crop Lua fallbacks; Mac NOT_RUN')
