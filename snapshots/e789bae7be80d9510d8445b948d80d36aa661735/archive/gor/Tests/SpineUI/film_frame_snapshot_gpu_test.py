#!/usr/bin/env python3
"""Real Lua snapshot -> same published GLSL; UI polygon equals film coordinates.
Software EGL, not AppKit/GPU presentation-time atomicity evidence.
"""
from pathlib import Path
import math,numpy as np,json,os,subprocess
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/surface_anchor_gpu_test.py'
exec(compile(f.read_text().split("cases={'plain'",1)[0],str(f),'exec'))
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
texture=np.stack([.15+.7*xx,.15+.7*yy,np.full_like(xx,.5),np.ones_like(xx)],-1).astype('f4');tex.write(texture.tobytes())
failures=[];frames=[];proof=[]
for mode in ("plain","converted","baked"):
 plain=mode=="plain"
 for degrees in (0,25,-45,90):
  for fov in (130,135,140):
   r=ns['Replay'](flat=True,source=(subprocess.check_output(['git','show',os.environ['FRAME_SOURCE']+':archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True) if os.environ.get('FRAME_SOURCE') else None))
   r.g.props['osd-width']=960;r.g.props['osd-height']=540
   if plain:
    r.msg('vr180-look-set-enabled','false');r.msg('vr180-look-tools-active','true')
   else:
    if mode=='baked':r.msg('vr180-look-set-projection','flat-sbs',16/9)
    r.msg('vr180-look-set-pack',3,0,.5,1,0)
   r.msg('vr180-look-full-fit');r.pose(roll=math.radians(degrees),fov=fov,x=.1,y=-.08)
   values=r.values();frame=r.g.props['user-data/vr180-look/film-frame']
   assert frame is not None,'no committed film snapshot'
   frame=dict(frame);assert abs(frame['fit']-values['vr_frame_fit'])<1e-8
   v=dict(values,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0)
   if mode=='baked':
    localx=(xx*2)%1
    baked=np.stack([.15+.7*localx,.15+.7*yy,np.full_like(xx,.5),np.ones_like(xx)],-1).astype('f4');tex.write(baked.tobytes())
    v=dict(values,vr_d3_gain=0)
   else:tex.write(texture.tobytes())
   image=draw((960,540),v)
   # Production layers transform the same crop-local polygon. No extra UI fit.
   angle=-frame['angle'];c,s=math.cos(angle),math.sin(angle)
   for right in ([0] if plain else [0,1]):
    for qx,qy in ((.2,.2),(.8,.2),(.2,.8),(.8,.8),(.5,.5)):
     dx=(qx-.5)*frame['frameW']*960;dy=(qy-.5)*frame['frameH']*540
     x=(frame['leftX']+right*frame['replicaX'])*960+frame['scale']*(c*dx-s*dy)
     y=(frame['leftY']+right*frame['replicaY'])*540+frame['scale']*(s*dx+c*dy)
     ix,iy=round(x-.5),round(y-.5)
     if not(0<=ix<960 and 0<=iy<540):continue
     expected=np.array([.15+.7*qx,.15+.7*qy,.5])
     error=float(np.abs(image[iy,ix]-expected).max())
     if error>.012:failures.append((plain,degrees,fov,right,qx,qy,error))
   if fov==135:proof.append((mode,degrees,image.copy(),frame.copy()))
   frames.append({'mode':mode,'plain':plain,'degrees':degrees,'fov':fov,**frame})
print('frame/film cases',len(frames),'failures',len(failures),'first',failures[:6])
assert not failures,failures[:10]
Path('/tmp/film-frame-snapshots.json').write_text(json.dumps(frames,indent=2))
print('PASS same committed fit/scale/angle/centre polygon samples the same film-local coordinates; no UI-only fit')

from PIL import Image,ImageDraw
canvas=Image.new('RGB',(1050,920),'#15171c');pen=ImageDraw.Draw(canvas)
pen.text((10,8),'194l published film pixels + committed UI polygon (green). Software EGL, not Mac UI.',fill='white')
for mode,degrees,image,frame in proof:
 col=['plain','converted','baked'].index(mode);row=[0,25,-45,90].index(degrees);x=col*350;y=28+row*220
 tile=Image.fromarray(np.uint8(np.clip(image[::-1],0,1)*255));tile=tile.resize((340,191));canvas.paste(tile,(x+5,y+18));pen.text((x+8,y),mode+' tilt '+str(degrees),fill='white')
 angle=-frame['angle'];c,s=math.cos(angle),math.sin(angle)
 for right in ([0] if mode=='plain' else [0,1]):
  polygon=[]
  for qx,qy in ((0,0),(1,0),(1,1),(0,1)):
   dx=(qx-.5)*frame['frameW']*960;dy=(qy-.5)*frame['frameH']*540
   px=(frame['leftX']+right*frame['replicaX'])*960+frame['scale']*(c*dx-s*dy)
   py=(frame['leftY']+right*frame['replicaY'])*540+frame['scale']*(s*dx+c*dy)
   polygon.append((x+5+px*340/960,y+18+(540-py)*191/540))
  pen.line(polygon+[polygon[0]],fill='#00ff80',width=1)
canvas.save('/downloads/frame194l-proof.png')
# The UI receipt must never get ahead of a failed shader publication.
r=ns['Replay'](flat=True);r.pose(roll=.2)
before=dict(r.g.props['user-data/vr180-look/film-frame'])
r.lua.execute('original_commandv=mp.commandv;mp.commandv=function(name,...) if name=="change-list" then return false,"injected" end return original_commandv(name,...) end')
r.pose(roll=.7)
assert dict(r.g.props['user-data/vr180-look/film-frame'])==before
print('PASS failed shader publication holds the previous committed UI receipt')
# Combined crop + snapshot proof: the published UI rail is post-crop, not packed-source sized.
crop_failures=[];crop_cases=0
for mode in ('converted','baked'):
 for degrees in (0,25,-45,90):
  r=ns['Replay'](flat=True);r.g.props['osd-width']=960;r.g.props['osd-height']=540
  if mode=='baked':r.msg('vr180-look-set-projection','flat-sbs',16/9)
  r.msg('vr180-look-set-pack',3,0,.5,1,0);r.msg('vr180-look-full-fit')
  r.msg('vr180-look-bar-crop',.12,.21,.71,.63);r.pose(roll=math.radians(degrees),fov=135,x=.1,y=-.08)
  frame=dict(r.g.props['user-data/vr180-look/film-frame']);v=r.values()
  if mode=='baked':
   localx=(xx*2)%1;tex.write(np.stack([.15+.7*localx,.15+.7*yy,np.full_like(xx,.5),np.ones_like(xx)],-1).astype('f4').tobytes())
   v=dict(v,vr_d3_gain=0)
  else:tex.write(texture.tobytes());v=dict(v,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0)
  image=draw((960,540),v);angle=-frame['angle'];c,s=math.cos(angle),math.sin(angle)
  for right in (0,1):
   for qx,qy in ((.2,.2),(.8,.2),(.2,.8),(.8,.8),(.5,.5)):
    dx=(qx-.5)*frame['frameW']*960;dy=(qy-.5)*frame['frameH']*540
    x=(frame['leftX']+right*frame['replicaX'])*960+frame['scale']*(c*dx-s*dy)
    y=(frame['leftY']+right*frame['replicaY'])*540+frame['scale']*(s*dx+c*dy)
    ix,iy=round(x-.5),round(y-.5)
    if not(0<=ix<960 and 0<=iy<540):continue
    expected=np.array([.15+.7*(.12+.71*qx),.15+.7*(.21+.63*qy),.5])
    error=float(np.abs(image[iy,ix]-expected).max())
    if error>.012:crop_failures.append((mode,degrees,right,qx,qy,error))
  crop_cases+=1
assert not crop_failures,crop_failures[:10]
print('PASS',crop_cases,'combined asymmetric crop / committed UI polygon / actual GLSL cases')
