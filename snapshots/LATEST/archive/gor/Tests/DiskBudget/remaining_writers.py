#!/usr/bin/env python3
"""Execute production Swift log/artifact guards and Python archive publisher."""

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
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,shutil,sys,os,importlib.util
r=Path(__file__).resolve().parents[2]
swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
main=r'''
import Foundation
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

let root=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
let log=root.appendingPathComponent("geom_trace.log")
for _ in 0..<100 {_=BoundedDiskWriter.append(Data(repeating:1,count:20),to:log,cap:128)}
let n=(try FileManager.default.attributesOfItem(atPath:log.path)[.size] as! NSNumber).intValue;precondition(n<=128)
let old=root.appendingPathComponent("quit-debug.log");let original=Data(repeating:2,count:1024);try original.write(to:old)
precondition(!BoundedDiskWriter.append(Data([3]),to:old,cap:128));let preserved=try Data(contentsOf:old);precondition(preserved==original)
print("PASS production append guards cap repeated writes and preserve oversized legacy logs byte-for-byte")
let traces=root.appendingPathComponent("av-traces");try FileManager.default.createDirectory(at:traces,withIntermediateDirectories:true)
let legacy=traces.appendingPathComponent("old.jsonl");try original.write(to:legacy)
for i in 0..<100 {_=BoundedDiskWriter.save(Data(repeating:4,count:40),name:"trace-\(i).jsonl",under:traces,cap:512,entries:4)}
let bounded=traces.appendingPathComponent("bounded-v1");let bytes=try DepthCacheBudget.bytes(bounded);precondition(bytes<=512)
let files=try FileManager.default.contentsOfDirectory(atPath:bounded.path).filter{!$0.hasPrefix(".")};precondition(files.count<=4)
let untouched=try Data(contentsOf:legacy);precondition(untouched==original)
precondition(BoundedDiskWriter.save(Data([1]),name:"../original.mp4",under:traces,cap:512)==nil)
let outside=root.appendingPathComponent("outside.mp4");try original.write(to:outside)
let link=bounded.appendingPathComponent("link.jsonl");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:outside)
precondition(BoundedDiskWriter.save(Data([8]),name:"new.jsonl",under:traces,cap:4096)==nil)
let outsidePreserved=try Data(contentsOf:outside);precondition(outsidePreserved==original)
print("PASS production AV trace aggregate/count caps and legacy/source path preservation; symlink store refuses without touching target")
'''
with tempfile.TemporaryDirectory(prefix='gor-writer-test-') as t:
 t=Path(t);(t/'main.swift').write_text(main)
 relocated=t/'BoundedDiskWriter.swift';relocated.write_text(_core_read(r/'Sources/gor/GorCore/Diag.swift').split('// BEGIN relocated BoundedDiskWriter.swift (195w 2a, behavior unchanged)\n',1)[1].split('// END relocated BoundedDiskWriter.swift',1)[0])
 subprocess.run([swift,str(_sec_file(r,'DepthCacheBudget.swift')),str(relocated),str(t/'main.swift'),'-o',str(t/'test')],check=True)
 subprocess.run([str(t/'test'),str(t/'files')],check=True)
 spec=importlib.util.spec_from_file_location('archives',r/'tools/bounded_log_archives.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
 legacy=t/'old-gor-log.zip';legacy.write_bytes(b'owner-legacy')
 first=Path(mod.publish({'log':b'first'},t,session='a',started=1,cap=2048,per_file=800,count=1))
 second=Path(mod.publish({'log':b'latest'},t,session='a',started=1,cap=2048,per_file=800,count=1));assert second==first
 with __import__('zipfile').ZipFile(second) as z:assert z.read('log')==b'latest' and z.testzip() is None
 before=_core_bytes(second)
 try:mod.publish({'huge':os.urandom(8192)},t,session='a',started=1,cap=1024,per_file=512);raise AssertionError('per-file')
 except mod.LimitReached:pass
 assert _core_bytes(second)==before and _core_bytes(legacy)==b'owner-legacy'
 assert len(list(t.glob('[1-9]*-gor-log.zip')))==1
 print('PASS actual ZIP byte cap, stable one-output CRC-valid replacement, failed publication preserves last valid ZIP and legacy files')
# Code-route checks accompany executable helpers, not substitute for them.
pp=_core_read(_pp_split().path(r,'PPController.swift'));app=_core_read(r/'Sources/gor/App/AppDelegate.swift');diag=_core_read(r/'Sources/gor/GorCore/Diag.swift');build=_core_read(r/'build.sh')
assert 'BoundedDiskWriter.append(Data(line.utf8),to:p)' in pp
assert 'BoundedDiskWriter.append(Data(line.utf8),to:URL(fileURLWithPath:path))' in app
assert diag.count('BoundedDiskWriter.save(')==2
assert 'output=bounded_log_archives.publish(entries,session=' in build and '"$res/bounded_log_archives.py"' in build
print('PASS production geom/quit/AV/ZIP call sites use tested helpers; native framework integration parse-only')
# Shared diagnostic Lua/native pipeline has its own executable process-lock test.
assert 'SharedDiagnosticRecord.payload(from: line)' in app
print('PASS native diagnostic relay call-site present; run shared_diagnostics.py for actual Lua/Swift/concurrency checks')
