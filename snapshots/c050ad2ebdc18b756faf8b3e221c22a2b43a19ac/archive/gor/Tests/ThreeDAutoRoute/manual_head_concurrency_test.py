#!/usr/bin/env python3
"""Real Lua: continuous head poses + manual pan/zoom/roll with playback unpaused."""
from pathlib import Path
import math
root=Path(__file__).resolve().parents[2]
ns={'__file__':str(root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py')}
exec(compile(Path(ns['__file__']).read_text().split('# Independent seeded',1)[0],ns['__file__'],'exec'),ns)
fails=[]
for kind,pack in [('vr180',0),('flat-sbs',0),('flat-tb',0),('flat-2d3d',1),('flat-2d3d',2),('flat-2d3d',3),('flat-2d3d',4)]:
 r=ns['Replay']();r.g.props['pause']=False
 r.msg('vr180-look-set-projection',kind,16/9)
 if pack:r.msg('vr180-look-set-pack',pack,.5,1,1)
 r.pose(yaw=.1,pitch=.2,roll=.15)
 before=r.values()
 r.msg('vr180-look-nudge',.2,-.1,-8,.25)
 for i in range(20):r.pose(yaw=.1+i*.002,pitch=.2,roll=.15)
 after=r.values()
 if abs(after['vr_roll']-.4)>1e-5:fails.append((kind,pack,'manual roll overwritten/absent',after['vr_roll']))
 assert abs(after['vr_manual_yaw']-.2)<1e-5 and abs(after['vr_manual_pitch']+.1)<1e-5
 assert abs(after['vr_manual_view']+8)<1e-5
 if kind!='vr180':
  assert abs(after['vr_yaw']-(.1+19*.002))<1e-5,'flat manual yaw composed twice'
  assert abs(after['vr_fov']-math.radians(135))<1e-5,'flat manual zoom composed twice'
 # Both directions are available beyond the previous45/55degree clamp.
 r.pose(pitch=math.radians(75))
 if abs(r.values()['vr_pitch']-(math.radians(75)-(.1 if kind=='vr180' else 0)))>1e-5:fails.append((kind,pack,'pitch still restricted',r.values()['vr_pitch']))
 r.pose(pitch=math.radians(-75))
 assert abs(r.values()['vr_pitch']-(math.radians(-75)-(.1 if kind=='vr180' else 0)))<1e-5
 if kind=='vr180':
  r.msg('vr180-look-set-orientation',0,0,135,.15,0,0,0,0,'none','ok',.1,.15,.3)
  assert abs(r.values()['vr_roll']-.55)<1e-5,'native raw pose erased manual roll'
 r.msg('vr180-look-motion','hold',1,1,0);r.tick(.1);r.tick(.2)
 assert r.values()['vr_manual_yaw']!=after['vr_manual_yaw']
 r.msg('vr180-look-motion','hold',0,0,0)
 assert r.g.props['pause']==False
 print('manual/head unpaused',kind,pack,'roll',after['vr_roll'],'manual pan',after['vr_manual_yaw'])
 r.msg('vr180-look-full-fit');r.pose(roll=.15)
 assert abs(r.values()['vr_roll']-.15)<1e-5
assert not fails,fails
print('PASS native/flatSBS/TB and pack1-4: head+manual pan/roll/zoom retained while playing,wide pitch,held move,release,fullfit clears manual roll. Native event dispatch NOT_RUN')
