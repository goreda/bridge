#!/usr/bin/env python3
"""Compile actual experiment command state; no AppKit/UI acceptance claim."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,os,shutil,tempfile,json
r=Path(__file__).resolve().parents[2]
_b=(_threed_split().path(r)).read_text()
source=Path(tempfile.mkdtemp())/'ThreeDExperimentMenu.swift'
source.write_text(_b[_b.index('// BEGIN relocated ThreeDExperimentMenu.swift '):_b.index('// END relocated ThreeDExperimentMenu.swift\n')])
swift=os.environ.get('SWIFTC') or shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
main='''import Foundation
func chk(_ b:Bool,_ s:String){if !b{fatalError(s)};print("PASS",s)}
var s=ThreeDExperimentState()
chk(!s.budgetOn,"default off")
chk(s.convergence==0 && s.compression==0.35,"initial mapping unchanged")
for _ in 0..<100 {s.stepConvergence(0.05);s.stepCompression(0.05)}
chk(s.convergence==0.5 && s.compression==1,"upper clamps")
for _ in 0..<100 {s.stepConvergence(-0.05);s.stepCompression(-0.05)}
chk(s.convergence == -0.5 && s.compression==0,"lower clamps")
s.budgetOn=true
let cmd=try! JSONSerialization.jsonObject(with:Data(s.budgetCommand.utf8)) as! [String:[String]]
chk(cmd["command"]![0...2]==["script-message-to","vr180_look","gor3d-budget"][0...2],"exact script route")
chk(cmd["command"]![3].contains("on=yes"),"on command")
s.budgetOn=false
chk(s.budgetMessage.contains("on=no"),"off command")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(main)
 subprocess.run([swift,str(source),str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],check=True)
menu=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDMenu.swift'+' '):_b.index('// END relocated '+'ThreeDMenu.swift'+'\n')])((_threed_split().path(r)).read_text());wiring=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDWiring.swift'+' '):_b.index('// END relocated '+'ThreeDWiring.swift'+'\n')])((_threed_split().path(r)).read_text());s=source.read_text()
assert 'ThreeDExperimentMenu.shared.install(in:m)' in menu
assert 'self?.cmd($0)' in wiring and 'reapplyIfEnabled' in wiring
assert 'UserDefaults' not in s and 'setenv' not in s
print('PASS menu installer and existing player command wiring; no saved defaults/launch changes')
print('AppKit menu pixels/native action validation NOT_RUN on Linux')

sd=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDSubtitleDepth.swift'+' '):_b.index('// END relocated '+'ThreeDSubtitleDepth.swift'+'\n')])((_threed_split().path(r)).read_text())
assert 'ThreeDSubtitleDepth.setExperimental(captionsOn)' in s
assert 'private var experimental = false' in sd and 'GOR3D_SUBDEPTH' not in sd
assert 'preparedContext=(depth,thetaH,r)' in sd
print('PASS F live setter default-off, existing prepared context retained for opt-in, env launch override removed')
