#!/usr/bin/env python3
"""191o T7: native VR180 pack gate and raw-roll sweep on the real Lua.

The native spherical branch must never select the pack variant. Roll is the
same raw value at 0/5/15/30 degrees for both legacy and extended runtime
selections. This is actual vr180-look.lua under lupa, not a shader text mirror.
"""
from pathlib import Path
import json, math, os, re, sys, tempfile
try:
    from lupa import LuaRuntime
except Exception:
    print('SKIPPED (no lupa)')
    sys.exit(0)

ROOT = Path(os.environ.get('GOR_ROOT', Path(__file__).resolve().parents[2]))
fails = []
def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + ((' ' + detail) if detail else ''))
    if not ok: fails.append(name)

def boot():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
props={pause=false,["osd-width"]=1600,["osd-height"]=900,["video-aspect-override"]="no"}
handlers={};cmds={};clock=0
mp={msg={info=function()end,warn=function()end,error=function(...) print("LUAERR",...) end,verbose=function()end,debug=function()end}}
function mp.get_property(k) return props[k] end
mp.get_property_number=mp.get_property
mp.get_property_native=mp.get_property
function mp.set_property(k,v) props[k]=v end
mp.set_property_number=mp.set_property
mp.set_property_native=mp.set_property
function mp.get_time() return clock end
function mp.register_script_message(k,f) handlers[k]=f end
function mp.register_event(k,f) end
function mp.add_periodic_timer(t,f) return {kill=function()end} end
mp.add_timeout=mp.add_periodic_timer
function mp.add_hook() end
function mp.observe_property() end
function mp.commandv(...) cmds[#cmds+1]={...}; return true end
function mp.command(...) return true end
function mp.add_key_binding() end
function mp.register_idle() end
function mp.get_script_name() return "vr180_look" end
function mp.command_native() return {} end
mp.utils=nil
function mp.get_opt() end
''')
    return lua, lua.globals()

def last_payload(g):
    for i in range(len(g.cmds), 0, -1):
        row = g.cmds[i]
        vals = [str(row[j]) for j in range(1, len(row) + 1)]
        if vals[:3] == ['change-list', 'glsl-shader-opts', 'add']:
            return vals[3]
    return ''

def uniform(g, name):
    m = re.search('/' + name + r'=([-+0-9.eE]+)', last_payload(g))
    return float(m.group(1)) if m else None

lua, g = boot()
with tempfile.TemporaryDirectory() as folder:
    g.props['config-dir'] = folder
    lua.execute((ROOT / 'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
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

    msg('vr180-look-set-projection', 'vr180', '1.7777778')
    msg('vr180-look-set-output', 'vr180')
    msg('vr180-look-set-enabled', 'true')
    msg('vr180-look-set-pack', '4', '1', '0.5', '1', '1')
    state = g.props['user-data/vr180-look/applied-state']
    check('native set-output forces pack 0', uniform(g, 'vr_pack') == 0.0,
          'vr_pack=%s state=%s' % (uniform(g, 'vr_pack'), state))
    pack_shaders = [p for p in (Path(folder) / 'shader').glob('*.glsl') if 'pack_eye' in p.read_text()]
    check('native set-pack cannot select the pack variant', not pack_shaders,
          'pack_shaders=%s' % ','.join(p.name for p in pack_shaders))

    for variant, tools in [('legacy', 'false'), ('extended', 'true')]:
        msg('vr180-look-tools-active', tools)
        for deg in (0, 5, 15, 30):
            target = math.radians(deg)
            msg('vr180-look-set-orientation', '0', '0', '135', str(target), '0', '0', '0', '0')
            got = uniform(g, 'vr_roll')
            check('%s native roll %ddeg publishes raw immediately' % (variant, deg),
                  got is not None and abs(got - target) < 1e-6,
                  'target=%.9f got=%s' % (target, got))
    msg('vr180-look-tools-active', 'false')

    # Interim F6: ordinary 2D presented as VR180 stays on the flat virtual-screen
    # path. The applied receipt must expose the measured source aspect, not a
    # generated VR180 shot's native projection.
    msg('vr180-look-set-projection', 'flat-2d3d', '1.7777778')
    msg('vr180-look-set-output', 'full_sbs')
    msg('vr180-look-set-pack', '3', '1', '0.5', '1', '1')
    applied = json.loads(g.props['user-data/vr180-look/applied-state'])
    check('interim twoDVR180 applied flat kind, pack 3 and aspect',
          applied.get('source_layout') == 0 and applied.get('flat_pack') == 3 and
          abs(applied.get('aspect', 0) - 1.7777778) < 1e-6,
          str(applied))

print('native pack/roll: %d failure(s)' % len(fails))
sys.exit(1 if fails else 0)
