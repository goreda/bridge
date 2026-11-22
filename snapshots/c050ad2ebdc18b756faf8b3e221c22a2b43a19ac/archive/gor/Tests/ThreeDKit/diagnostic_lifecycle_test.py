#!/usr/bin/env python3
"""Compiled actual stage logger plus real Python CLI parser; diagnostics only, no native render claim."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util, os, pathlib, shutil, subprocess, sys, tempfile
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

sys.dont_write_bytecode = True
R=pathlib.Path(__file__).resolve().parents[2]
sp=importlib.util.spec_from_file_location('checker',R/'tools/update_3d_check.py'); m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
rows=['gor3d-selftest-cli v1 begin build=x kit=/k','gor3d-selftest-cli v1 stage self-test total begin t=0.0','gor3d-selftest-cli v1 stage render vr180 begin t=1.0','gor3d-selftest-cli v1 stage render vr180 end ms=70 t=1.1','gor3d-selftest-cli v1 end code=2 errors=5 meaning=ran_with_errors']
assert m.cli_status(rows)==(True,2,5,1), ('RED nested stage begin is not another CLI invocation',m.cli_status(rows))
assert m.cli_status(rows+rows)==(False,2,5,2)
assert m.cli_status(rows[:-1])[0] is False
assert m.cli_status(rows[:-1]+['gor3d-selftest-cli v1 end code=0 errors=0 meaning=ok'])==(True,0,0,1)
print('PASS four real parser cases: nested stages complete, duplicate invocation/cut incomplete, success complete')
sw=os.environ.get('SWIFTC') or shutil.which('swiftc');assert sw
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d);(p/'main.swift').write_text('''import Foundation
var lines: [String] = []; let lock = NSLock()
ThreeDStageLog.sink = {lock.lock();lines.append($0);lock.unlock()}
ThreeDStageLog.enabled = true;ThreeDStageLog.beat = 0.02;ThreeDStageLog.start()
ThreeDStageLog.time("total") {
 ThreeDStageLog.time("render vr180") {ThreeDStageLog.progress("stereo-synthesis-vr180",done:0,total:48);Thread.sleep(forTimeInterval:0.08)}
 ThreeDStageLog.time("realtime probe") {Thread.sleep(forTimeInterval:0.12)}
}
ThreeDStageLog.stop();lock.lock();let rows=lines;lock.unlock()
let end=rows.firstIndex {$0.contains("stage render vr180 end")}!
precondition(rows[..<end].contains {$0.contains("progress stage=stereo-synthesis-vr180")})
precondition(!rows[(end+1)...].contains {$0.contains("progress stage=stereo-synthesis-vr180")}, "RED completed render progress replayed in realtime probe")
precondition(rows[(end+1)...].contains {$0.contains("alive stage=realtime probe")})
print("PASS compiled logger clears completed render counter and names realtime probe")
''')
 subprocess.run([sw,str(_sec_file(R,'ThreeDStageLog.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
