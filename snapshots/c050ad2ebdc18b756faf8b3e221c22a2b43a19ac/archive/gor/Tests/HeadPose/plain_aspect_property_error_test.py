#!/usr/bin/env python3
"""Use mpv's real missing-property return contract: nil, error string.
Not a native presentation-time or owner-symptom reproduction.
"""
from pathlib import Path
import runpy
root=Path(__file__).resolve().parents[2]
Replay=runpy.run_path(str(root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py'))['Replay']
r=Replay(flat=True)
r.msg('vr180-look-set-projection','flat-2d3d',0)
r.msg('vr180-look-set-pack',3,0,.5,1,0)
r.pose(roll=.35)
assert r.g.props['user-data/vr180-look/film-frame'] is False
r.msg('vr180-look-set-projection','flat-2d3d',1.5)
r.pose(roll=.35)
assert abs(r.g.props['user-data/vr180-look/film-frame']['angle']+.35)<1e-9
print('PASS zero aspect has no frame; corrected source aspect restores matching film/UI tilt receipt')
r.lua.execute('''
mp.get_property=function(k)
 local value=props[k]
 if value==nil then return nil,"property unavailable" end
 return tostring(value)
end
''')
# A file boundary legitimately clears video-params. Publishing must not kill the
# script, whether packing, plain Tools or return-to-file is active.
for mode in ('converted','plain'):
 if mode=='plain':
  r.msg('vr180-look-set-enabled','false')
  r.msg('vr180-look-tools-active','true')
 r.pose(roll=.25)
 r.g.props['video-params/dw']=1080
 r.g.props['video-params/dh']=720
 r.pose(roll=.30)
 assert abs(r.values()['vr_plain_aspect']-1.5)<1e-6
 r.g.props['video-params/dw']=None
 r.g.props['video-params/dh']=None
print('PASS missing aspect has mpv nil/error return; fallback and later pose publication survive')
