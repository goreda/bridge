#!/usr/bin/env python3
"""Drive the actual compiled capture-free worker on native Darwin. No camera access."""
from pathlib import Path
import subprocess,sys,json,selectors,os,time
import numpy as np
from PIL import Image
exe,image=map(Path,sys.argv[1:3]);im=Image.open(image).convert('RGBA');a=np.asarray(im)[:,:,[2,1,0,3]].copy();h,w,_=a.shape
for kind in ['ambient']:
 p=subprocess.Popen([str(exe),'--camera-vision-worker'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 pending=b''
 def line():
  global pending
  deadline=time.monotonic()+12
  while b'\n' not in pending:
   with selectors.DefaultSelector() as s:
    s.register(p.stdout,selectors.EVENT_READ)
    assert s.select(max(0,deadline-time.monotonic())),(kind,'worker output deadline')
   part=os.read(p.stdout.fileno(),65536);assert part,(kind,p.poll(),'unexpected EOF');pending+=part
  row,pending=pending.split(b'\n',1);return json.loads(row)
 try:
  hello=line();assert hello['ev']=='hello' and hello['pid']==p.pid
  times=[]
  for n in range(6):
   now=time.monotonic()
   f=dict(generation=7,window=1,now=now,pts=now,age=0,pixelWidth=w,pixelHeight=h,ambientOnly=True,settled=True,consecutiveSettled=3,seenFirstSettled=True,ambientSettled=True,processed=False,visionFailed=False,visionMS=0,exposureChanging=0,visionToken=0)
   packet=dict(frame=f,kind=kind,stride=w*4,bytes=a.nbytes)
   p.stdin.write(json.dumps(packet).encode()+b'\n'+a.tobytes());p.stdin.flush()
   while True:
    event=line()
    if event['ev']=='log':print(event['message'],flush=True);continue
    assert event['ev']=='frame';result=event['frame'];break
   assert result['delivery']==kind and result['processed'] and not result['visionFailed']
   assert result['generation']==7 and result['now']==now
   measured=result['rect']
   assert measured['faceCount']==1
   pose=result['rect']
   assert all(isinstance(pose.get(k),(int,float)) and __import__('math').isfinite(pose[k]) for k in ['yaw','pitch','roll']),pose
   print('NATIVE_MEASURED_POSE',kind,{k:pose[k] for k in ['yaw','pitch','roll']},flush=True)
   regions=result['lumaRectFace']
   assert all(isinstance(regions.get(k),(int,float)) and __import__('math').isfinite(regions[k]) for k in ['face','room','combined']),regions
   assert abs(regions['combined']-(regions['room']*0.75+regions['face']*0.25))<1e-9,regions
   print('NATIVE_AMBIENT_SAME_FRAME_REGIONS',regions,flush=True)
   times.append(result['visionMS'])
  print('PASS native actual ambient worker',kind,'requests=6 ms=',times,'camera_session=false configured_cpu=true actual_device_not_exposed',flush=True)
 finally:
  p.kill();p.wait(timeout=5)
