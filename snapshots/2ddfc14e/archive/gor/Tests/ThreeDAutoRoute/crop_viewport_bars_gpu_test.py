#!/usr/bin/env python3
"""Original shader pixels: black-bar viewport removes bars without rescaling landmarks."""
import runpy
from pathlib import Path
ns=runpy.run_path(str(Path(__file__).with_name('surface_anchor_gpu_test.py')))
globals().update(ns)
# Reuse the real generated shader and renderer, not a shader approximation.
black=arr.copy();mask=(xx<.15)|(xx>.85)|(yy<.2)|(yy>.8);black[mask,:3]=0
rows=[]
for name,size,flags in [('mono',(960,540),dict(vr_plain=1,vr_flat_sbs=0,vr_flat_mono=0,vr_pack=0)),('mono-to-SBS',(960,270),dict(vr_plain=0,vr_flat_sbs=1,vr_flat_mono=1,vr_pack=3)),('source-SBS',(960,270),dict(vr_plain=0,vr_flat_sbs=1,vr_flat_mono=0,vr_pack=0)),('source-TB',(960,270),dict(vr_plain=0,vr_flat_sbs=1,vr_flat_mono=0,vr_pack=0,blink_top_bottom=1))]:
 localx=(xx*2)%1 if name=='source-SBS' else xx
 localy=(yy*2)%1 if name=='source-TB' else yy
 black=arr.copy();mask=(localx<.15)|(localx>.85)|(localy<.2)|(localy>.8);black[mask,:3]=0
 tex.write(black.tobytes())
 flags=dict(flags,vr_d3_gain=0,vr_base_ipd=0,vr_ipd_nudge=0,vr_parallax_strength=0,vr_eye_aspect=16/9,vr_surface_w=0,vr_surface_h=0,vr_yaw=0,vr_pitch=0,vr_roll=0)
 before=draw(size,flags)
 sw,sh=size;target=(int(sw*.7),int(sh*.6))
 after=draw(target,dict(flags,vr_surface_w=sw,vr_surface_h=sh,vr_surface_x=0,vr_surface_y=0))
 if name=='mono':expected=before[int(sh*.2):int(sh*.8),int(sw*.15):int(sw*.85)]
 else:expected=np.concatenate([before[int(sh*.2):int(sh*.8),72:408],before[int(sh*.2):int(sh*.8),552:888]],axis=1)
 err=float(np.abs(after-expected).max());mean=float(np.abs(after-expected).mean())
 print('BAR VIEWPORT',name,'max',err,'mean',mean,'before dark',float((before.sum(-1)<.02).mean()),'after dark',float((after.sum(-1)<.02).mean()))
 assert mean<.001 and err<.015
 assert (before.sum(-1)<.02).mean()>.5
 assert (after.sum(-1)<.02).mean()<.01
 rows.append((name,before,after))
canvas=Image.new('RGB',(1000,720),(30,30,30));pen=ImageDraw.Draw(canvas)
for j,(name,before,after) in enumerate(rows):
 pen.text((8,j*180+4),name+' | original black bars | accepted viewport',fill='white')
 for i,frame in enumerate((before,after)):
  im=Image.fromarray((np.clip(frame[::-1],0,1)*255).astype('uint8'));im.thumbnail((480,150));canvas.paste(im,(i*500,j*180+25))
canvas.save('/downloads/crop194e-bars.png')
print('PASS actual generated GLSL bars removed; content landmarks unchanged. Camera/depth zero isolates crop.')
