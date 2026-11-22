#!/usr/bin/env python3
"""Actual GLSL film pixels versus production subtitle layer coordinates, one screen."""

# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
import json,math,os,subprocess,tempfile
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/zoom_content_gpu_test.py'
exec(compile(_sub_read(f).split('for deg in (0,20,-20):')[0],str(f),'exec'))
main='''import Foundation
for cross in [false,true] {for deg in [-30.0,-20,-10,10,20,30] {
let a=deg*Double.pi/180,p=SubtitleTiltGeometry.place(ink:CGRect(x:70,y:440,width:320,height:70),screen:CGRect(x:0,y:0,width:960,height:600),shift:483,left:0,offset:0,roll:a,pairRoll:a*(cross ? 1:-1))
print("\\(cross ? 1:0) \\(deg) \\(p.angle) \\(p.leftX) \\(p.leftY) \\(p.replicaX) \\(p.replicaY)")
}}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sub_compile_input(root/'Sources/gor/Subtitles/SubtitleTiltGeometry.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 rows=[list(map(float,line.split())) for line in subprocess.check_output([str(p/'test')],text=True).splitlines()]
frames=[];font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',24)
def centroid(v):
 weight=np.maximum(v-.05,0);yy,xx=np.indices(v.shape);return np.array([(xx*weight).sum()/weight.sum(),(yy*weight).sum()/weight.sum()])
for cross,deg,a,lx,ly,dx,dy in rows:
 r=math.radians(deg)
 # Existing production shader renders two colour-coded points at the same source Y.
 film=draw((w,h),dict(common,vr_roll=r,vr_head_roll=r,vr_cross_eye=cross,vr_fov=math.radians(135),vr_head_z=0))
 measured=[]
 for side in (0,1):
  eye=film[:,side*w//2:(side+1)*w//2]
  delta=centroid(eye[:,:,1])-centroid(eye[:,:,0])
  # GL framebuffer is Y-up; convert to the same top-down screenshot space
  # that displays the AppKit-backed subtitle layer.
  film_angle=math.atan2(-delta[1],delta[0])
  subtitle_angle=a
  error=abs(math.degrees(math.atan2(math.sin(subtitle_angle-film_angle),math.cos(subtitle_angle-film_angle))))
  assert error<.05,(cross,deg,side,math.degrees(film_angle),math.degrees(subtitle_angle),error)
  # The previous compositor used +roll without converting the displayed Y axis.
  old_error=abs(math.degrees(math.atan2(math.sin(r-film_angle),math.cos(r-film_angle))))
  assert old_error>19.9,'previous wrong-sign source mutant escaped'
  measured.append(math.degrees(film_angle))
 # Centre separation uses the same coordinate conversion as the tilted divider.
 pair=r*(1 if cross else -1)
 assert abs(math.atan2(dy,dx)+pair)<1e-10
 print('MEAS cross',int(cross),'headdeg',deg,'film_topdown_deg',measured,'subtitle_topdown_deg',math.degrees(a),'max_baseline_error_deg',max(abs(v-math.degrees(a)) for v in measured),'old_sign_error_deg',old_error)
 if cross==1:
  canvas=Image.fromarray((np.clip(film[::-1],0,1)*255).astype('uint8')).convert('RGBA')
  ink=Image.new('RGBA',(320,70));pen=ImageDraw.Draw(ink);pen.text((6,10),'Subtitles follow the film',font=font,fill='white')
  c,s=math.cos(a),math.sin(a);cx,cy=230,475
  for side in (0,1):
   tx=lx+side*dx;ty=ly+side*dy;ox=cx-c*cx+s*cy+tx;oy=cy-s*cx-c*cy+ty
   inv=(c,s,-c*ox-s*oy-70,-s,c,s*ox-c*oy-440)
   canvas.alpha_composite(ink.transform((w,h),Image.Transform.AFFINE,inv,resample=Image.Resampling.BICUBIC))
  frames.append((deg,canvas))
proof=Image.new('RGB',(w,len(frames)*(h+24)),(20,20,20));pen=ImageDraw.Draw(proof)
for i,(deg,img) in enumerate(frames):
 y=i*(h+24);pen.text((8,y+4),'same-screen actual GLSL film landmarks + production subtitle transform: head%ddeg'%deg,fill='white');proof.paste(img,(0,y+24))
proof.save('/downloads/subtitle-film-sign.png')
print('PASS24 same-screen signed film/subtitle baselines, SBS both eyes and parallel/cross; old wrong-sign mutant rejected. Native Mac screenshot still required.')
