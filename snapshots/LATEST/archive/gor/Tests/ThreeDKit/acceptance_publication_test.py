#!/usr/bin/env python3
"""Compiled production publication boundary; native render is a controlled producer.
Not AVFoundation/Metal execution, a valid MP4 or a decoded-pixel acceptance test.
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[2]
s=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDSelfTest.swift'+' '):_b.index('// END relocated '+'ThreeDSelfTest.swift'+'\n')])((_threed_split().path(root)).read_text())
pure=s.split('#if canImport(AVFoundation)',1)[0]
main=r'''
import Foundation
let fm=FileManager.default
let base=fm.temporaryDirectory.appendingPathComponent("gor194u-"+UUID().uuidString)
try fm.createDirectory(at:base,withIntermediateDirectories:true)
defer {try? fm.removeItem(at:base)}
let evidence=base.appendingPathComponent("evidence"),work=base.appendingPathComponent("run")
try fm.createDirectory(at:evidence,withIntermediateDirectories:true)
try fm.createDirectory(at:work,withIntermediateDirectories:true)
let unrelated=evidence.appendingPathComponent("owner-film.mp4")
try Data("must survive".utf8).write(to:unrelated)
let sentinel=work.appendingPathComponent("unrelated-work.mp4")
try Data("also survives".utf8).write(to:sentinel)
for name in ["sbs","vr180"] {
 let dst=evidence.appendingPathComponent(name+".mp4")
 try Data("prior acceptance".utf8).write(to:dst)
 var stagedURLs=Set<URL>()
 for run in 1...3 {
  let current=Data((name+" current run "+String(run)).utf8)
  let out=try ThreeDSelfTest.acceptanceRender(work:work,evidence:evidence,name:name) {staged in
   precondition(staged.deletingLastPathComponent().path==work.path && staged != dst)
   precondition(!fm.fileExists(atPath:staged.path),"insert-only renderer receives existing output")
   precondition(try! Data(contentsOf:dst) != current,"published before render finished")
   precondition(stagedURLs.insert(staged).inserted,"reused render filename")
   try current.write(to:staged)
  }
  precondition(out==dst && (try! Data(contentsOf:dst))==current)
 }
 let good=try Data(contentsOf:dst)
 var decoded=false
 do {
  _=try ThreeDSelfTest.acceptanceRender(work:work,evidence:evidence,name:name) {staged in
   try Data("partial".utf8).write(to:staged);throw CocoaError(.fileWriteUnknown)
  }
  decoded=true
 } catch {}
 precondition(!decoded && (try! Data(contentsOf:dst))==good,"failed render reused or damaged previous acceptance")
 do {_=try ThreeDSelfTest.acceptanceRender(work:work,evidence:evidence,name:name) {try Data().write(to:$0)};preconditionFailure("empty output accepted")} catch {}
 precondition((try! Data(contentsOf:dst))==good)
 do {_=try ThreeDSelfTest.acceptanceRender(work:work,evidence:base.appendingPathComponent("missing"),name:name) {try Data("new".utf8).write(to:$0)};preconditionFailure("publication failure accepted")} catch {}
 print("PASS "+name+": three replacements, fresh producer paths, render/empty/publication failure closed; last-good output retained")
}
for name in ["../owner-film","owner-film","sbs/other",""] {
 var called=false
 do {_=try ThreeDSelfTest.acceptanceRender(work:work,evidence:evidence,name:name) {_ in called=true};preconditionFailure("unowned name accepted")} catch {}
 precondition(!called)
}
precondition((try! Data(contentsOf:unrelated))==Data("must survive".utf8))
precondition((try! Data(contentsOf:sentinel))==Data("also survives".utf8))
precondition(try! fm.contentsOfDirectory(atPath:work.path)==["unrelated-work.mp4"],"own staging not cleaned")
print("PASS only sbs/vr180 can be replaced; unrelated outputs untouched; current-run staging cleaned")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(pure+main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
assert 'completed = try acceptanceRender(work: work, evidence: evidence, name: name)' in s
assert 'out: staged)' in s
assert 'if let out = completed, let hash = firstFrameHash(out), saveFrame(out, png: png)' in s
assert 'removeItem(at: evidence' not in s
writer=(lambda _b: _b[_b.index('// BEGIN relocated '+'RenderShotWriter.swift'+' '):_b.index('// END relocated '+'RenderShotWriter.swift'+'\n')])((_threed_split().path(root)).read_text())
assert 'try FileManager.default.moveItem(at:out,to:destination)' in writer
assert 'replaceItemAt' not in writer
print('PASS real selftest wiring decodes only successful current publication; playback cache insert-only writer unchanged')
