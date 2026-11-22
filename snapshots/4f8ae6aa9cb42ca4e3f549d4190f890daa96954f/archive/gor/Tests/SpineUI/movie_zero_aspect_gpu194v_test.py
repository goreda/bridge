#!/usr/bin/env python3
"""Actual Lua safety uniforms/receipt -> published shader, software EGL.
Synthetic proof image, not owner-film pixels or native AppKit screenshot.
"""
from pathlib import Path
import math
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
w,h=1080,720
xx,yy=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
tex=ctx.texture((w,h),4,np.stack([.15+.7*xx,.15+.7*yy,np.full_like(xx,.5),np.ones_like(xx)],-1).astype('f4').tobytes(),dtype='f4');tex.use();tex.filter=(moderngl.LINEAR,moderngl.LINEAR)
canvas=Image.new('RGB',(960*3,648),(20,20,20));pen=ImageDraw.Draw(canvas)
errors=[]
for col,roll in enumerate((0,.25,-.4)):
 r=ns['Replay'](flat=True);r.g.props['path']='Movie1080x720';r.g.props['osd-width']=960;r.g.props['osd-height']=600
 r.g.props['video-dec-params/w']=1080;r.g.props['video-dec-params/h']=720;r.g.props['video-dec-params/par']=1
 r.msg('vr180-look-set-projection','flat-2d3d',0);r.msg('vr180-look-set-pack',3,0,.5,1,0);r.msg('vr180-look-full-fit');r.pose(roll=roll)
 frame=dict(r.g.props['user-data/vr180-look/film-frame']);v=dict(r.values(),vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0)
 image=draw((960,600),v)
 # Independent source-coordinate pixel landmarks in both eyes.
 angle=-frame['angle'];c,s=math.cos(angle),math.sin(angle)
 for right in (0,1):
  for qx,qy in ((.2,.2),(.8,.2),(.2,.8),(.8,.8),(.5,.5)):
   dx=(qx-.5)*frame['frameW']*960;dy=(qy-.5)*frame['frameH']*600
   x=(frame['leftX']+right*frame['replicaX'])*960+frame['scale']*(c*dx-s*dy)
   y=(frame['leftY']+right*frame['replicaY'])*600+frame['scale']*(s*dx+c*dy)
   if 0<=x<960 and 0<=y<600:
    error=float(np.abs(image[round(y-.5),round(x-.5)]-np.array([.15+.7*qx,.15+.7*qy,.5])).max());errors.append(error)
 im=Image.fromarray((np.clip(image[::-1],0,1)*255).astype('uint8'));canvas.paste(im,(col*960,48))
 pen.text((col*960+12,8),f'Synthetic Movie 1080x720 | Swift aspect0 | roll {roll:+.2f}',fill='white')
 pen.text((col*960+12,24),'Actual shader pixels; yellow = committed film/UI rail',fill='white')
 for right in (0,1):
  polygon=[]
  for qx,qy in ((0,0),(1,0),(1,1),(0,1)):
   dx=(qx-.5)*frame['frameW']*960;dy=(qy-.5)*frame['frameH']*600
   x=(frame['leftX']+right*frame['replicaX'])*960+frame['scale']*(c*dx-s*dy)
   y=(frame['leftY']+right*frame['replicaY'])*600+frame['scale']*(s*dx+c*dy)
   polygon.append((col*960+x,48+600-y))
  pen.line(polygon+[polygon[0]],fill='yellow',width=2)
assert max(errors)<.012,(max(errors),errors)
canvas.save('/downloads/gor194v-movie-synthetic-proof.png')
print('PASS30 actual shader pixel landmarks, zero-aspect Movie3:2 frames at3rolls; maxRGBerror',max(errors))
