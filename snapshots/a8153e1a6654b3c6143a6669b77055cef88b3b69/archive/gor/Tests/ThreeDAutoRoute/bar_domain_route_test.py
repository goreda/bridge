#!/usr/bin/env python3
"""Production accepted-bar route validity, reset/file boundaries and publisher wiring."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import math
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
r=ns['Replay'](flat=True)
keys=['vr_source_x','vr_source_y','vr_source_w','vr_source_h']
def domain():return tuple(r.values()[k] for k in keys)
r.msg('vr180-look-bar-crop',.12,.21,.71,.63)
assert domain()==(.12,.21,.71,.63)
for deg in (0,25,-45,90):
 r.pose(roll=math.radians(deg),fov=145,x=.1,y=-.1)
 assert domain()==(.12,.21,.71,.63)
for message in ('vr180-look-full-fit','vr180-look-source-eye-crop'):
 r.msg(message)
 assert domain()==(.12,.21,.71,.63),message
for args in ((-.1,0,.8,1),(0,0,0,1),(.5,0,.8,1),('bad',0,1,1)):
 r.msg('vr180-look-bar-crop',*args);assert domain()==(.12,.21,.71,.63)
r.msg('vr180-look-bar-crop',0,0,1,1);assert domain()==(0,0,1,1)
r.msg('vr180-look-set-projection','vr180',0);r.msg('vr180-look-bar-crop',.1,.2,.7,.6)
assert domain()==(0,0,1,1),'flat crop crossed native projection'
r.msg('vr180-look-set-projection','flat-2d3d',16/9);r.msg('vr180-look-bar-crop',.1,.2,.7,.6)
r.g.events['start-file']();r.msg('vr180-look-set-enabled','true');assert domain()==(0,0,1,1),'bar domain leaked to next file'
print('PASS accepted domain stable across pose/full-fit/packing callbacks; malformed bounds rejected; native excluded; new file clears')
s=(_pp_split().path(root,'PPController.swift')).read_text()
a=s.index('    private func publishSurfaceWindowCrop(');b=s.index('    private func flatEyeContentBounds',a);publish=s[a:b]
assert '!menuCropOwnsSelection, let rect=cropRect' in publish and 'vr180-look-bar-crop' in publish
assert publish.index('vr180-look-menu-crop') < publish.index('vr180-look-bar-crop')
assert s.count('"vr180-look-bar-crop","0","0","1","1"')==2
print('PASS only accepted detector rect, not manual ratio, follows viewport publication; reset/revert clears')
# Compile the actual publisher method with boundary-only drawable and IPC spies.
import subprocess,tempfile,os,json
start=s.index('    private func publishSurfaceWindowCrop(');end=s.index('    private func flatEyeContentBounds',start)
method=s[start:end].replace('private func','func')
program='''import Foundation
class Probe {
var menuCropOwnsSelection=false,surfaceCropAwaitingDrawable=false
var nativeVideoAspect:Double?=16.0/9,manualMenuCropAspect:Double?
var cropRect:CGRect?=CGRect(x:0.12,y:0.21,width:0.71,height:0.63)
func surfaceDrawableReceipt()->(Double,Double)? {(960,540)}
func ipcCommand(_ value:String){print(value)}
'''+method+'''
}
let p=Probe();_=p.publishSurfaceWindowCrop(x:0.71,y:0.63,cx:0.475,cy:0.525)
p.menuCropOwnsSelection=true;_=p.publishSurfaceWindowCrop(x:0.8,y:1)
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 commands=[json.loads(line)['command'] for line in subprocess.check_output([str(p/'test')],text=True).splitlines()]
assert len(commands)==3 and commands[0][2]=='vr180-look-menu-crop' and commands[1][2]=='vr180-look-bar-crop' and commands[2][2]=='vr180-look-menu-crop'
r=ns['Replay'](flat=True)
for c in commands[:2]:r.msg(c[2],*c[3:])
assert domain()==(.12,.21,.71,.63)
assert r.values()['vr_surface_w']==0 and r.values()['vr_surface_h']==0,'old anchor double-cropped accepted domain'
print('PASS actual Swift publisher JSON -> real Lua: accepted per-eye source domain, no double viewport crop; manual ratio never emits bar-crop')
