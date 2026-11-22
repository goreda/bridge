#!/usr/bin/env python3
"""Native VR180 head roll must remain the original raw pose path.

The 2D->3D cinema smoothing is for converted/flat presentations. A native
spherical film uses the pre-2D-to-3D viewer semantics: the roll sent by the
controller is the roll published to the shader on that same pose message.
Runs the production vr180-look.lua under lupa and measures the actual IPC
uniform payload; no shader text mirror.
"""
from pathlib import Path
import math, re, sys, tempfile
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

def payloads(g):
    out = []
    for i in range(1, len(g.cmds) + 1):
        row = g.cmds[i]
        vals = [str(row[j]) for j in range(1, len(row) + 1)]
        if vals[:3] == ['change-list', 'glsl-shader-opts', 'add']:
            out.append(vals[3])
    return out

def last_roll(g):
    ps = payloads(g)
    if not ps: return None
    m = re.search(r'/vr_roll=([-+0-9.eE]+)', ps[-1])
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
    msg('vr180-look-set-pack', '0', '1', '0.5', '1', '1')
    target = math.radians(15)
    msg('vr180-look-set-orientation', '0', '0', '135', str(target), '0', '0', '0', '0')
    got = last_roll(g)
    check('native VR180 +15deg roll is published raw on the same pose message',
          got is not None and abs(got - target) < 1e-6,
          'target=%.9f got=%s' % (target, got))
    target2 = math.radians(-15)
    msg('vr180-look-set-orientation', '0', '0', '135', str(target2), '0', '0', '0', '0')
    got2 = last_roll(g)
    check('native VR180 -15deg roll is published raw on the same pose message',
          got2 is not None and abs(got2 - target2) < 1e-6,
          'target=%.9f got=%s' % (target2, got2))

print('native roll parity: %d failure(s)' % len(fails))
sys.exit(1 if fails else 0)
