"""Execute production Lua: uniform payloads, lid animation and all pitch inputs. No GPU claim."""
from pathlib import Path
import ast, math, re, tempfile
from lupa import LuaRuntime
root=Path(__file__).resolve().parents[2]
l=LuaRuntime(unpack_returned_tuples=True)
setup=Path(__file__).with_name('hold-lua.py').read_text()
setup=setup[setup.index("l.execute(")+len("l.execute("):setup.index("\ng=l.globals()")].strip()
# Reuse only the test boundary setup, not the hold test or its expired temp directory.
l.execute(ast.literal_eval(setup[:-1]))
g=l.globals()
tmp=tempfile.TemporaryDirectory();g.props['config-dir']=tmp.name;g.props['osd-width']=960
g.props['glsl-shaders']=l.table()
l.execute((root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
l.execute('''last_uniforms="";mp.commandv=function(a,b,c,d)
 if a=="change-list" and b=="glsl-shader-opts" then last_uniforms=d end
 return true end''')
def msg(name,*args):g.handlers[name](*map(str,args))
def tick(t):
 g.clock=t
 for f in list(g.timers.values()):f()
def uniform(name):
 m=re.search('/'+re.escape(name)+r'=([-0-9.]+)',g.last_uniforms)
 assert m, (name,g.last_uniforms)
 return float(m[1])
msg('vr180-look-set-enabled','true')
# Make the shader active in this stub even after the prior file-change test.
msg('vr180-look-set-orientation',0,0,90,0)
tick(33)
assert uniform('vr_swap_eyes')==1
print('PASS Lua cross-eye initial uniform defaults ON')
for swap in ['0','1']:
 msg('vr180-look-set-swap-eyes',swap)
 g.clock=34;msg('vr180-look-set-lids',1,0,'false')
 # Continuous fresh measurements avoid the production 200 ms stale-frame fail-open.
 for i in range(1,30):
  t=34+i*.02;g.clock=t;msg('vr180-look-set-lids',1,0,'false');tick(t)
 assert uniform('blink_lid_l')==0 and uniform('blink_lid_r')>.99
 g.clock=35;msg('vr180-look-set-lids',0,1,'false')
 for i in range(1,30):
  t=35+i*.02;g.clock=t;msg('vr180-look-set-lids',0,1,'false');tick(t)
 assert uniform('blink_lid_l')>.99 and uniform('blink_lid_r')==0
print('PASS observed camera-side inversion corrected exactly once; source cross-eye OFF/ON does not flip lids again')
msg('vr180-look-set-orientation',0,2,90,0)
assert abs(uniform('vr_pitch')-math.radians(55))<1e-6
msg('vr180-look-set-orientation',0,-2,90,0)
assert abs(uniform('vr_pitch')-math.radians(-45))<1e-6
msg('vr180-look-set-orientation',0,0,90,0)
msg('vr180-look-nudge',0,2,0)
assert abs(uniform('vr_pitch')-math.radians(55))<1e-6
print('PASS production orientation + manual nudge: down clamp 55 degrees, up remains 45 degrees')
print('UNVERIFIED native camera anatomical labels and rendered side/pitch pixels; payload proof only')

# The dial must affect the actual shader uniform even when no distance is available.
msg('vr180-look-set-orientation',0,0,90,0,0,0,0,0,'none','no-face',0.25)
msg('vr180-look-set-ipd-mm',0);before=uniform('vr_base_ipd')
msg('vr180-look-set-ipd-mm',2);after=uniform('vr_base_ipd')
assert after>before,(before,after)
assert uniform('blink_sbs_strength')==1
print('PASS IPD +2mm changes actual shader separation without distance; SBS blink strength equals VR opaque strength1')
msg('vr180-look-set-orientation',0,0,90,0,0,0,0,0,300,'ok',0.25)
import json
trace=json.loads(g.props['user-data/vr180-look/distance-trace'])
assert trace['cap_met'] is True,trace
print('PASS actual IPD distance cap still met after direct dial offset')
msg('vr180-look-source-eye-crop',.11875,0,.7625,1)
assert abs(uniform('vr_source_x')-.11875)<1e-6 and abs(uniform('vr_source_w')-.7625)<1e-6
print('PASS actual Lua publishes per-eye source crop independently of menu crop and eye swap')
