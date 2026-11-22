#!/usr/bin/env python3
"""Compare working Lua shader-option payloads and frame receipts to taking194u."""
from pathlib import Path
import subprocess,math
root=Path(__file__).resolve().parents[2];f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
old=subprocess.check_output(['git','show','7b9bc2dd7751fae83764432f9d442c6c934e8982:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
new=(root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text();count=0
for mode,kind,aspect in [('mono','flat-2d3d',1.5),('full_sbs','flat-2d3d',1.5),('full_sbs','flat-2d3d',16/9),('full_sbs','flat-sbs',16/9),('top_bottom','flat-2d3d',1.5),('anaglyph','flat-2d3d',1.5),('vr180','vr180',16/9)]:
 for size in [(819,546),(2048,1280),(960,540),(600,800)]:
  for crop in [False,True]:
   for roll in [0,.25,-.4]:
    results=[]
    for source in [old,new]:
     r=ns['Replay'](source=source);r.g.props['path']='/working-'+kind
     r.g.props['osd-width'],r.g.props['osd-height']=size
     r.g.props['video-params/w']=1080;r.g.props['video-params/h']=720;r.g.props['video-params/par']=1
     r.msg('vr180-look-set-projection',kind,aspect)
     if mode=='mono':r.msg('vr180-look-set-enabled','false');r.msg('vr180-look-tools-active','true')
     else:
      r.msg('vr180-look-set-output',mode);r.msg('vr180-look-set-pack',{'top_bottom':1,'anaglyph':2}.get(mode,3),0,.5,1,0)
     if crop:r.msg('vr180-look-bar-crop',0,.1,1,.8)
     r.pose(roll=roll)
     frame=r.g.props['user-data/vr180-look/film-frame']
     frame=dict(frame) if frame is not False and frame is not None else frame
     payloads=[]
     for i in range(1,len(r.g.cmds)+1):
      args=[r.g.cmds[i][j] for j in range(1,len(r.g.cmds[i])+1)]
      if args[:3]==['change-list','glsl-shader-opts','add']:payloads.append(tuple(sorted(args[3].split(','))))
     results.append((frame,payloads))
    assert results[0]==results[1],(mode,kind,size,crop,roll)
    count+=1
print('PASS',count,'working cases: identical canonical shader-option payload sequences (Lua pairs order ignored) and exact committed frame receipts vs194u; mono, Movie/Himiko SBS, native, TB/anaglyph, crop, window/fullscreen/portrait sizes')
