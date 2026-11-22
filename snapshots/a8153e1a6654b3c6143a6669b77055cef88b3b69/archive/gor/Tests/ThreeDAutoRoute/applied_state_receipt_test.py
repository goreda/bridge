#!/usr/bin/env python3
"""Applied-state IPC receipts for the owner action leg.

Swift publishes the store/controller decision at
user-data/gor/3d-applied-state. vr180-look.lua publishes the values it
actually applied at user-data/vr180-look/applied-state. This test checks the
Swift publication contract from source and drives the production Lua to
measure its receipt values.
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json, sys, tempfile
try:
    from lupa import LuaRuntime
except Exception:
    print('SKIPPED (no lupa)')
    sys.exit(0)

ROOT = Path(__file__).resolve().parents[2]
fails = []
def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + ((' ' + detail) if detail else ''))
    if not ok: fails.append(name)

swift = (_pp_split().path(ROOT,'PPController_Features.swift')).read_text()
check('Swift publishes user-data/gor/3d-applied-state', 'MPVCommand.make(["set_property", "user-data/gor/3d-applied-state", payload])' in swift)
for field in ['"pid"', '"build"', '"timestamp"', '"stereoSource"', '"engine"', '"output"', '"vr_mode"']:
    check('Swift applied-state field ' + field, field in swift)
check('Swift build receipt uses the installed source-manifest digest', 'BuildID.value()' in swift)
check('Swift receipt reports the controller vrModeEnabled', 'vrModeEnabled' in swift)

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
props={pause=false,["osd-width"]=1600,["osd-height"]=900}
handlers={}
mp={msg={info=function()end,warn=function()end,error=function(...) print("LUAERR",...) end,verbose=function()end,debug=function()end}}
function mp.get_property(k) return props[k] end
mp.get_property_number=mp.get_property
mp.get_property_native=mp.get_property
function mp.set_property(k,v) props[k]=v end
mp.set_property_number=mp.set_property
mp.set_property_native=mp.set_property
function mp.get_time() return 0 end
function mp.register_script_message(k,f) handlers[k]=f end
function mp.register_event(k,f) end
function mp.add_periodic_timer(t,f) return {kill=function()end} end
mp.add_timeout=mp.add_periodic_timer
function mp.add_hook() end
function mp.observe_property() end
function mp.commandv(...) return true end
function mp.command(...) return true end
function mp.add_key_binding() end
function mp.register_idle() end
function mp.get_script_name() return "vr180_look" end
function mp.command_native() return {} end
mp.utils=nil
function mp.get_opt() end
''')
g = lua.globals()
with tempfile.TemporaryDirectory() as folder:
    g.props['config-dir'] = folder
    lua.execute((ROOT / 'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
    key = 'user-data/vr180-look/applied-state'
    def receipt():
        raw = g.props[key]
        return json.loads(raw) if raw else None
    route_kind = ['vr180']
    def msg(name, *args):
        args = list(map(str, args))
        counts = {'vr180-look-set-projection': 2, 'vr180-look-set-output': 1,
                  'vr180-look-set-enabled': 1, 'vr180-look-set-pack': 5,
                  'vr180-look-plan-lock': 2}
        if name in counts:
            if name == 'vr180-look-set-projection': route_kind[0] = args[0]
            g.handlers['vr180-look-store-revision']('1', route_kind[0], 'store-applier')
            while len(args) < counts[name]: args.append('false' if name == 'vr180-look-plan-lock' else '1')
            args += ['1', 'store-applier']
        g.handlers[name](*args)
    r = receipt()
    check('Lua baseline applied-state receipt exists', isinstance(r, dict), repr(r))
    if isinstance(r, dict):
        check('Lua baseline actuals', r.get('source_layout') == 0 and r.get('flat_pack') == 0 and r.get('plan_lock') is None and r.get('enabled') is False, repr(r))
    msg('vr180-look-set-projection', 'flat-2d3d', '1.7777778')
    msg('vr180-look-set-output', 'full_sbs')
    msg('vr180-look-set-pack','3','1','0','1','0')
    msg('vr180-look-set-enabled', 'true')
    r = receipt()
    check('Lua SBS applied-state actuals', isinstance(r, dict) and r.get('source_layout') == 0 and r.get('flat_pack') == 3 and r.get('plan_lock') is None and r.get('enabled') is True, repr(r))
    before = receipt()
    g.handlers['vr180-look-set-output']('off')
    g.handlers['vr180-look-set-enabled']('false', '0', 'store-applier')
    check('unversioned and stale route writes leave real receipt unchanged', receipt() == before)
    msg('vr180-look-plan-lock', 'on', 'true')
    r = receipt()
    check('Lua plan-lock true actual', isinstance(r, dict) and r.get('plan_lock') is True, repr(r))
    msg('vr180-look-set-pack', '3', '1.5', '.4', '.8', '0')
    r = receipt()
    check('current revision parameters remain live under prepared-shot lock', isinstance(r, dict) and r.get('flat_pack') == 3 and r.get('plan_lock') is True)
    msg('vr180-look-plan-lock', 'on', 'false')
    r = receipt()
    check('Lua plan-lock false actual', isinstance(r, dict) and r.get('plan_lock') is False, repr(r))
    msg('vr180-look-plan-lock', 'off')
    msg('vr180-look-set-output', 'off')
    msg('vr180-look-set-enabled', 'false')
    installed=g.props['user-data/vr180-look/installed-shader']
    check('retiring shader files invalidates the former PASS receipt',installed is not None and installed['verdict']=='PENDING' and installed['entry']=='none')
    r = receipt()
    check('Lua Off applied-state actuals', isinstance(r, dict) and r.get('flat_pack') == 0 and r.get('plan_lock') is None and r.get('enabled') is False, repr(r))

from pathlib import Path
import re
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
for prior in ('fresh','native'):
 r=ns['Replay']()
 if prior=='native':r.msg('vr180-look-set-projection','vr180',1)
 r.msg('vr180-look-set-enabled','false')
 # Snapshot actual submitted options at EACH activation, including transient ones.
 r.g.snapshot_shader=lambda path:Path(path).read_text()
 r.lua.execute('''activations={};local old=mp.set_property_native
 mp.set_property_native=function(k,v)
  if k=="glsl-shaders" and #v>0 then
   local submitted={};for i=1,#cmds do
    if cmds[i][1]=="change-list" and cmds[i][2]=="glsl-shader-opts" then submitted[#submitted+1]=cmds[i][4] end
   end
   activations[#activations+1]={path=v[#v],source=snapshot_shader(v[#v]),options=table.concat(submitted,"|")}
  end
  return old(k,v)
 end''')
 r.msg('vr180-look-tools-active','true')
 assert len(r.g.activations)>0
 for i in range(1,len(r.g.activations)+1):
  a=r.g.activations[i];stem=Path(a['path']).stem
  assert 'if(vr_plain>0.5)' in a['source'],('native shader exposed during plain tools activation',prior)
  assert stem+'/vr_plain=1.0' in a['options'],('plain uniforms not published before shader installation',prior)
 assert not r.g.props['user-data/vr180-look/enabled']
 assert r.values()['vr_plain']==1 and r.values()['vr_source_layout']==0 and r.values()['vr_pack']==0
 r.msg('vr180-look-set-blink-analog','true');r.msg('vr180-look-set-lids',1,1,'false')
 r.tick(.1)
 assert r.values()['blink_lid_l']>.9 and r.values()['blink_lid_r']>.9,'plain blink animation never advanced'
 r.msg('vr180-look-set-lids',0,0,'false');r.tick(.3)
 assert r.values()['blink_lid_l']<.01 and r.values()['blink_lid_r']<.01,'plain blink did not reopen'
 r.msg('vr180-look-tools-active','false')
 assert len(r.g.props['glsl-shaders'])==0
 print('PASS plain tools publication-before-activation, layout0/pack0, independent blink and toolsOFF',prior)

print('applied-state receipts: %d failure(s)' % len(fails))
sys.exit(1 if fails else 0)
