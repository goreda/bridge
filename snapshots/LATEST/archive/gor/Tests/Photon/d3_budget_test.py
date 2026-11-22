#!/usr/bin/env python3
"""Production Lua shader generation and disparity math. No GPU/pixel claim."""
from pathlib import Path
from lupa import lua51
import hashlib, subprocess, random, tempfile
root=Path(__file__).resolve().parents[2]
p=root/'Resources/vendor/mpv/scripts/vr180-look.lua'
# Reuse the existing production-script API double, with Lua5.1 unpack support.
harness=(root/'test-vr-ui-ceiling-lua.py').read_text().split("lua.execute('''",1)[1].split("''')",1)[0].replace('table.unpack','unpack')
def load(text,new):
    lua=lua51.LuaRuntime(unpack_returned_tuples=True);lua.execute(harness)
    lua.globals().props['config-dir']=tempfile.gettempdir()
    lua.globals().props['osd-width']=1400;lua.globals().props['osd-height']=800
    extra='\nTEST={extended=VR180_LOOK_EXTENDED_SOURCE,legacy=VR180_LOOK_LEGACY_SOURCE,pack=VR180_LOOK_PACK_SOURCE}\n'
    if new: extra+='TEST.budget=d3_budget; function TEST.mode(mono,layout) flat_mono=mono;source_layout=layout end\n'
    lua.execute(text+extra)
    return lua,lua.globals().TEST
baseline=subprocess.check_output(['git','show','a8e3548ab:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],cwd=root,text=True)
_,old=load(baseline,False);lua,new=load(p.read_text(),True)
for kind in ('extended','legacy','pack'):
    assert old[kind] == new[kind],kind
    new.mode(True,0)
    assert new.budget.source(new[kind])==old[kind]
    print('OFF golden',kind,hashlib.sha256(old[kind].encode()).hexdigest())
new.budget.on=True
for kind in ('extended','pack'):
    new.mode(True,0);on=new.budget.source(new[kind]);assert on != new[kind]
    assert 'disp=d3_budget_map(disp);' in on
    # Baked SBS/TB/native and ordinary mono never change, even with opt enabled.
    for mono,layout in [(False,0),(False,1),(False,2),(False,3),(True,3)]:
        new.mode(mono,layout);assert new.budget.source(new[kind])==old[kind]
f=new.budget.map
for x in [-.01,-.005,0,.005,.01]: assert abs(f(x,0,0,.01,.01,.015)-x)<1e-9
last=-1
for i in range(1001):
    x=-.01+i*.00002;y=f(x,0,.35,.01,.02,.02)
    assert y>=last;last=y
    assert abs(y+f(-x,0,.35,.01,.02,.02))<1e-9
    assert -.015<=f(x,.2,.35,.01,.005,.015)<=.005
print('PASS off byte-identical all 3 shaders; baked-source bypass; monotonicity/symmetry/clamps/linear identity')
# Exercise the real route/selector, not only the pure source transform.
replay=root/'Tests/ThreeDAutoRoute/preview_pack_lua_test.py'
ns={'__file__':str(replay)}
exec(compile(replay.read_text().split('packed = run(1)')[0],str(replay),'exec'),ns)
enabled='mp.get_opt=function(k) if k=="gor3d_budget" then return "yes" end end\n'+p.read_text()
installed=ns['run'](1,source=enabled)
assert any('disp=d3_budget_map(disp);' in text and 'vec4 pack_eye(' in text for text in installed)
print('PASS actual route selects installed budget shader when explicitly enabled')
print('No mpv installed: native GPU compile/render/pixels/ms NOT_RUN')
