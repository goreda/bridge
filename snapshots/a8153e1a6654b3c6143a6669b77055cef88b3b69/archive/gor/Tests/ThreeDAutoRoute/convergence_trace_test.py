#!/usr/bin/env python3
"""Actual Lua numeric evidence ring; exact shader/uniform parity, not a jitter cure."""
from pathlib import Path
import json,subprocess,math
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
instrumented=(root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
a=instrumented.index('-- Numeric convergence evidence only,')
b=instrumented.index('local function vr_push_uniforms()',a)
before=instrumented[:a]+instrumented[b:]
before=before.replace('    pcall(convergence_record,payload)\n','')
old=ns['Replay'](flat=True,source=before);new=ns['Replay'](flat=True,source=instrumented)
for i in range(930):
 for replay in [old,new]:
  replay.g.clock=i/30
  replay.msg('vr180-look-set-orientation',.01,-.02,135+i/1000,.003,.004,0,0,0,'none','fov-unavailable',0,.005,.006)
 assert old.values()==new.values(),'instrumentation changed published uniforms'
new.g.props['user-data/gor/3d-internal']=True
new.msg('vr180-look-viewing-cross','1')
new.msg('vr180-look-set-swap-eyes','1')
new.g.clock=35
new.msg('vr180-look-set-orientation',0,0,123,0,.01,0,0,0,'none','fov-unavailable',0,0,0)
path=Path(new.tmp.name)/'gor-convergence.jsonl'
rows=[json.loads(s) for s in path.read_text().splitlines()]
assert len(rows)<=900 and len(rows)>100
assert all(r['titleStatAvailable']==0 for r in rows)
assert rows[-1]['internal']==1 and abs(rows[-1]['vr_fov']-math.radians(123))<1e-6
assert rows[-1]['vr_cross_eye']==1 and rows[-1]['vr_swap_eyes']==1
assert all(k in rows[-1] for k in ('vr_manual_view','vr_eye_aspect','vr_aspect_override','vr_surface_w','vr_surface_h'))
assert rows[-1]['vr_ipd_nudge']==.01 and rows[-1]['vr_source_layout']==0
assert len({(r['sessionBirth'],r['sessionEpoch']) for r in rows})==1
assert all(all(type(v) in (int,float) for v in r.values()) for r in rows)
# Diagnostic I/O failure must never escape or interrupt a successful uniform upload.
new.lua.execute('io.open=function(...) error("test write failure") end')
new.g.clock=45
new.msg('vr180-look-set-orientation',0,0,124,0,.02,0,0,0,'none','fov-unavailable',0,0,0)
assert abs(new.values()['vr_fov']-math.radians(124))<1e-6
for i in range(1,len(new.g.timers)+1):new.g.timers[i]()
# Unchanged source means every published generated GLSL variant remains identical.
f=root/'Tests/ThreeDAutoRoute/preview_pack_lua_test.py';pub={'__file__':str(f)}
exec(compile(f.read_text().split('packed = run(1)')[0],str(f),'exec'),pub)
for pack in [0,1,2,3,4]:
 oldsh=pub['run'](pack,source=before);newsh=pub['run'](pack,source=instrumented)
 assert set(oldsh)==set(newsh),(pack,'generated shader changed')
print('PASS actual current Lua930updates identical uniforms,900row bound, numeric route/convergence/time/session, exact all-pack GLSL parity; title stats explicitly unavailable')
