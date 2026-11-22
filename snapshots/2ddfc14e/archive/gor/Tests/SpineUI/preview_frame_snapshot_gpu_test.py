#!/usr/bin/env python3
"""TB/anaglyph receipt -> actual published GLSL, crop and window sizes.
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

failures=[];count=0;visible=0;proof=[]
for source in ('mono','bakedSBS'):
 for pack in (1,2):
  for w,h in ((640,360),(960,540),(600,800)):
   for degrees in (0,25,-45,90):
    for crop in (False,True):
     r=ns['Replay'](flat=True,source=(subprocess.check_output(['git','show',os.environ['FRAME_SOURCE']+':archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True) if os.environ.get('FRAME_SOURCE') else None));r.g.props['osd-width']=w;r.g.props['osd-height']=h

     if source=='bakedSBS':r.msg('vr180-look-set-projection','flat-sbs',16/9)
     r.msg('vr180-look-set-pack',pack,0,.5,1,0);r.msg('vr180-look-full-fit')
     if crop:r.msg('vr180-look-bar-crop',.12,.21,.71,.63)
     r.pose(roll=math.radians(degrees),fov=130,x=.1,y=-.08)
     raw=r.g.props['user-data/vr180-look/film-frame'];assert raw,'affine preview has no committed film receipt'
     frame=dict(raw);assert frame['layout']==pack
     assert frame['instances']==(2 if pack==1 else 1)
     assert frame['baseY']==(.25 if pack==1 else .5)
     values=r.values();v=dict(values,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0)
     if source=='bakedSBS':
      localx=(xx*2)%1;tex.write(np.stack([.15+.7*localx,.15+.7*yy,np.full_like(xx,.5),np.ones_like(xx)],-1).astype('f4').tobytes())
     else:tex.write(texture.tobytes())
     image=draw((w,h),v)
     angle=-frame['angle'];c,s=math.cos(angle),math.sin(angle)
     for right in range(frame['instances']):
      for qx,qy in ((.2,.2),(.8,.2),(.2,.8),(.8,.8),(.5,.5)):
       dx=(qx-.5)*frame['frameW']*w;dy=(qy-.5)*frame['frameH']*h
       x=(frame['leftX']+right*frame['replicaX'])*w+frame['scale']*(c*dx-s*dy)
       y=(frame['leftY']+right*frame['replicaY'])*h+frame['scale']*(s*dx+c*dy)
       ix,iy=round(x-.5),round(y-.5)
       inBand=(0<=ix<w and right*h/2<=iy<(right+1)*h/2) if pack==1 else (0<=ix<w and 0<=iy<h)
       if not inBand:continue
       expected=np.array([.15+.7*(.12+.71*qx if crop else qx),.15+.7*(.21+.63*qy if crop else qy),.5])
       error=float(np.abs(image[iy,ix]-expected).max());visible+=1
       if error>.013:failures.append((source,pack,w,h,degrees,crop,right,qx,qy,error))
     if source=='mono' and w==960 and not crop:proof.append((pack,degrees,image.copy(),frame.copy()))
     count+=1
print('preview snapshot cases',count,'visible landmark samples',visible,'failures',len(failures),failures[:8])
assert not failures,failures[:10]
print('PASS TB/anaglyph actual Lua receipt -> published GLSL with asymmetric crop, windowed/portrait sizes and fixed eye band sampling')

from PIL import Image,ImageDraw
canvas=Image.new('RGB',(1000,1250),'#15171c');pen=ImageDraw.Draw(canvas)
pen.text((8,8),'TB / anaglyph published GLSL + output-clipped chrome polygon. Software EGL, not AppKit.',fill='white')
for pack,degree,image,frame in proof:
 col=pack-1;row=(0,25,-45,90).index(degree);ox=col*500;oy=30+row*300
 tile=Image.fromarray(np.uint8(np.clip(image[::-1],0,1)*255)).resize((480,270))
 angle=-frame['angle'];c,s=math.cos(angle),math.sin(angle)
 for right in range(frame['instances']):
  overlay=Image.new('RGBA',tile.size);drawline=ImageDraw.Draw(overlay);poly=[]
  for qx,qy in ((0,0),(1,0),(1,1),(0,1)):
   dx=(qx-.5)*frame['frameW']*960;dy=(qy-.5)*frame['frameH']*540
   x=(frame['leftX']+right*frame['replicaX'])*960+frame['scale']*(c*dx-s*dy)
   y=(frame['leftY']+right*frame['replicaY'])*540+frame['scale']*(s*dx+c*dy)
   poly.append((x*.5,(540-y)*.5))
  drawline.line(poly+[poly[0]],fill='#00ff80',width=1)
  if pack==1:
   # Shader partitions physically, not with the rotated film. The production
   # Swift clip helper is separately compiled in ui_tilt_frame_containment_test.
   band=(0,135*(1-right),480,135*(2-right))
   tile.paste(overlay.crop(band),band[:2],overlay.crop(band))
  else:tile.paste(overlay,(0,0),overlay)
 if pack==1:ImageDraw.Draw(tile).line((0,135,480,135),fill='#ffa020',width=1)
 canvas.paste(tile,(ox+6,oy+18));pen.text((ox+8,oy),('TB' if pack==1 else 'anaglyph')+' tilt '+str(degree),fill='white')
canvas.save('/downloads/preview-frame194m-proof.png')
