#!/usr/bin/env python3
"""Current Movie mono->SBS, real Lua producer and compiled final UI consumer.
Zero/absent Swift aspect is a reproduced condition, not an owner-runtime diagnosis.
"""
from pathlib import Path
import subprocess,math,os
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
Replay=ns['Replay'];frames=[]
for fallback in ('video-out-params','video-params','video-dec-params'):
 for roll in (0,.25,-.4):
  r=Replay(flat=True);r.g.props['path']='/Movie on 20.09.2026 at 11.28.mov'
  r.g.props['osd-width']=2048;r.g.props['osd-height']=1280
  r.g.props[fallback+'/w']=1080;r.g.props[fallback+'/h']=720
  r.g.props['video-params/aspect']=1.5;r.g.props['dwidth']=1920;r.g.props['dheight']=1080
  r.msg('vr180-look-set-enabled','false');r.msg('vr180-look-tools-active','true');r.pose(roll=roll)
  assert r.g.props['user-data/vr180-look/film-frame'] is not False,'mono control failed'
  r.msg('vr180-look-set-projection','flat-2d3d',0)
  r.msg('vr180-look-set-output','full_sbs');r.msg('vr180-look-set-pack',3,0,.5,1,0)
  r.msg('vr180-look-set-enabled','true');r.msg('vr180-look-full-fit');r.pose(roll=roll)
  frame=r.g.props['user-data/vr180-look/film-frame']
  assert frame is not False,'Movie mono->SBS with Swift aspect0 dropped film receipt'
  assert frame['path']==r.g.props['path'] and abs(frame['angle']+roll)<1e-9
  assert abs(frame['frameW']*2048/(frame['frameH']*1280)-1.5)<1e-9
  frames.append({k:float(v) for k,v in frame.items() if isinstance(v,(int,float))})
# The existing harness compiles actual applyTrackedUITilt, Spine transform and input inverse.
# It checks every visual corner against the committed film polygon, not a Python UI model.
f=root/'Tests/SpineUI/ui_tilt_frame_containment_test.py';text=f.read_text()
context={'__file__':str(f),'frames':frames}
exec(compile(text[:text.index('frames=[]')],str(f),'exec'),context)
exec(compile(text[text.index("program='import Foundation"):],str(f),'exec'),context)
print('PASS9 Movie mono->SBS zero-aspect receipts: current3:2 film containment and roll follow in actual compiled UI consumer')

# Same OSD, different current films, including reopening Movie after larger Himiko.
r=Replay(flat=True);r.g.props['osd-width']=2048;r.g.props['osd-height']=1280
for path,w,h,par in [('Movie',1080,720,1),('Himiko',1920,1080,1),('Movie',1080,720,1),('anamorphic',1080,720,2)]:
 r.g.props['path']=path;r.g.events['start-file']()
 r.g.props['video-dec-params/w']=w;r.g.props['video-dec-params/h']=h;r.g.props['video-dec-params/par']=par
 r.msg('vr180-look-set-projection','flat-2d3d',0);r.msg('vr180-look-set-pack',3,0,.5,1,0);r.msg('vr180-look-set-enabled','true');r.pose(roll=.35)
 frame=r.g.props['user-data/vr180-look/film-frame'];assert frame is not False and frame['path']==path
 assert abs(r.values()['vr_eye_aspect']-w*par/h)<1e-6
 assert abs(frame['frameW']*2048/(frame['frameH']*1280)-w*par/h)<1e-9
print('PASS current-path Movie->Himiko->Movie same OSD; coded PAR applied once')
for bad in (float('inf'),float('nan'),-1,0):
 r=Replay(flat=True);r.g.props['video-dec-params/w']=bad;r.g.props['video-dec-params/h']=1080;r.g.props['video-dec-params/par']=4/3
 r.g.props['video-dec-params/dw']=1440;r.g.props['video-dec-params/dh']=1080
 r.msg('vr180-look-set-projection','flat-2d3d',0);r.msg('vr180-look-set-pack',3,0,.5,1,0);r.pose(roll=.35)
 assert abs(r.values()['vr_eye_aspect']-1440/1080)<1e-6,'Lua mixed geometry or double PAR'
print('PASS Lua finite-positive paired dimensions; invalid coded width never mixes with coded height or doubles PAR')
