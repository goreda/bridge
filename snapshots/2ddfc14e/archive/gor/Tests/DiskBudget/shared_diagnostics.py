#!/usr/bin/env python3
"""Real Lua emission -> native record parser -> multi-process flock byte cap."""

# Platform source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _plat_iu
from pathlib import Path as _PlatPath
_plat_root=next(p for p in _PlatPath(__file__).resolve().parents if (p/'Tests/Structure/platform_source.py').is_file())
_plat_spec=_plat_iu.spec_from_file_location('platform_source_view',_plat_root/'Tests/Structure/platform_source.py')
_plat_view=_plat_iu.module_from_spec(_plat_spec);_plat_spec.loader.exec_module(_plat_view)
_plat_read=_plat_view.read_source
_plat_bytes=_plat_view.read_bytes
_plat_compile_input=_plat_view.compile_input

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
from lupa import lua51
import tempfile,subprocess,shutil,os,json
r=Path(__file__).resolve().parents[2]
swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
src=_plat_read(r/'Resources/vendor/mpv/scripts/photon.lua')
a=src.index('function COST.diag_mirror(');b=src.index('\nCOST.diag_mirror("ident"',a)
c=src.index('function COST.write(');d=src.index('\nend',c)+4
lua=lua51.LuaRuntime();lua.execute('rows={};mp={msg={info=function(s) rows[#rows+1]=s end}};COST={media_telemetry=true}\n'+src[a:b]+'\n'+src[c:d])
lua.globals().COST.diag_mirror('test','native relay\nkeeps records')
lua.globals().COST.write('x'*10000)
rows=[v for _,v in lua.globals().rows.items()];assert len(rows)==2 and all(len(s.encode())<=4096 for s in rows)
assert '\n' not in rows[0] and 'native relay keeps records' in rows[0]
main=r'''
import Foundation
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

let output=URL(fileURLWithPath:CommandLine.arguments[1]);let text=try String(contentsOfFile:CommandLine.arguments[2],encoding:.utf8)
precondition(SharedDiagnosticRecord.payload(from:"ordinary mpv line")==nil)
for _ in 0..<100 {for line in text.components(separatedBy:"\n") {if let bytes=SharedDiagnosticRecord.payload(from:"[1.234] [photon] "+line) {
 precondition(!bytes.isEmpty && bytes.count<=16385)
 _=BoundedDiskWriter.append(bytes,to:output,cap:8192)
}}}
'''
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text(main);(t/'records').write_text('\n'.join(rows))
 diag=_plat_read(r/'Sources/gor/GorCore/Diag.swift')
 (t/'BoundedDiskWriter.swift').write_text(diag.split('// BEGIN relocated BoundedDiskWriter.swift (195w 2a, behavior unchanged)\n',1)[1].split('// END relocated BoundedDiskWriter.swift',1)[0])
 (t/'SharedDiagnosticRecord.swift').write_text(diag.split('// BEGIN relocated SharedDiagnosticRecord.swift (195w 2a, behavior unchanged)\n',1)[1].split('// END relocated SharedDiagnosticRecord.swift',1)[0])
 subprocess.run([swift,str(_sec_file(r,'DepthCacheBudget.swift')),str(t/'BoundedDiskWriter.swift'),str(t/'SharedDiagnosticRecord.swift'),str(t/'main.swift'),'-o',str(t/'writer')],check=True)
 log=t/'diag.log'
 ps=[subprocess.Popen([str(t/'writer'),str(log),str(t/'records')]) for _ in range(8)]
 assert all(p.wait()==0 for p in ps)
 data=_plat_bytes(log);assert len(data)<=8192 and b'native relay keeps records' in data
 assert data.endswith(b'\n') and b'GOR_DIAG_RECORD' not in data
 old=t/'legacy.log';original=b'L'*16384;old.write_bytes(original)
 subprocess.run([str(t/'writer'),str(old),str(t/'records')],check=True);assert _plat_bytes(old)==original
 print('PASS actual Lua records -> native parser ->8processes serialized append cap; complete records and oversized legacy unchanged',len(data))
for name in ['photon.lua','photon-grain.lua','photon-hud.lua','vr180-look.lua']:
 s=_plat_read(r/'Resources/vendor/mpv/scripts'/name);assert 'io.open("/tmp/gor_diag.log"' not in s;assert 'GOR_DIAG_RECORD ' in s
for name in ['Diag.swift','AppDelegate.swift','OverlaySpaceGate.swift']:
 s=_plat_read(r/'Sources/gor'/name);assert 'Darwin.open(StagedRunPaths.tmp("/tmp/gor_diag.log")' not in s
 assert 'BoundedDiskWriter.append(' in s and 'SharedDiagnosticRecord.cap' in s
assert 'SharedDiagnosticRecord.payload(from: line)' in _plat_read(r/'Sources/gor/App/AppDelegate.swift')
print('PASS all discovered Lua/native shared-log append paths use serialized native sink; no Lua subprocess. Framework pipe wiring parse-only.')
