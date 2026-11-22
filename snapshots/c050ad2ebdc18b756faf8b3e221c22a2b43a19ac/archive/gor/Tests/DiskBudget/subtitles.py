#!/usr/bin/env python3
"""Run production memory-only HTTP reader, SRT parser and capped cache on Linux."""

# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input

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
import subprocess, tempfile, threading, http.server, os, shutil
r=Path(__file__).resolve().parents[2]
swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
small=b'1\n00:00:01,000 --> 00:00:02,500\n<i>Exact subtitle</i>\n\n'
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  self.send_response(503 if self.path=='/error' else 200)
  if self.path!='/stream':self.send_header('Content-Length',str(8192 if self.path=='/declared' else len(small)))
  self.end_headers()
  try:self.wfile.write(b'x'*8192 if self.path in ['/declared','/stream'] else small)
  except (BrokenPipeError,ConnectionResetError):pass
 def log_message(self,*args):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
src=_sub_read(r/'Sources/gor/GorSubtitlesUI/SubtitleView.swift')
a=src.index('    static func parseSRT(at url:');b=src.index('\nprivate extension CGRect',a)
parser='enum SubtitleView {\n'+src[a:b] # closes the production extension
main=r'''
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

#endif
func fetch(_ path:String, limit:Int=128)->Data? {
 let sem=DispatchSemaphore(value:0);var result:Data?;var calls=0
 BoundedSubtitleDownload.fetch(URLRequest(url:URL(string:CommandLine.arguments[1]+path)!),limit:limit) {data in result=data;calls += 1;sem.signal()}
 precondition(sem.wait(timeout:.now()+10) == .success);Thread.sleep(forTimeInterval:0.03);precondition(calls==1);return result
}
let bytes=fetch("/small")!;let cues=SubtitleView.parseSRT(data:bytes)!
precondition(cues.count==1 && cues[0].start==1 && cues[0].end==2.5 && cues[0].text=="Exact subtitle")
precondition(fetch("/declared")==nil);precondition(fetch("/stream")==nil);precondition(fetch("/error")==nil)
for _ in 0..<12 {precondition(fetch("/small")==bytes)}
print("PASS actual ephemeral HTTP reader exact bytes/SRT cues, advertised and streaming overlimit cancellation, HTTP error, repeated single completion")
let root=URL(fileURLWithPath:CommandLine.arguments[2]);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
let legacy=root.appendingPathComponent("legacy.srt");try bytes.write(to:legacy)
for i in 0..<100 {_=BoundedDiskWriter.save(bytes,name:"film_en_\(i).srt",under:root,cap:512,entries:3)}
let managed=root.appendingPathComponent("bounded-v1");let size=try DepthCacheBudget.bytes(managed);precondition(size<=512)
let saved=try FileManager.default.contentsOfDirectory(at:managed,includingPropertiesForKeys:nil).filter{$0.pathExtension=="srt"};precondition(saved.count<=3)
let persisted=try Data(contentsOf:legacy);precondition(persisted==bytes)
// Full persistence does not affect exact in-memory loaded/export bytes.
precondition(BoundedDiskWriter.save(bytes,name:"full.srt",under:root,cap:1)==nil)
precondition(SubtitleView.parseSRT(data:bytes)![0].text=="Exact subtitle")
print("PASS actual subtitle cache aggregate/count guards, full-cache memory cue path, legacy byte preservation")
'''
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text(main+'\n'+parser)
 (t/'BoundedDiskWriter.swift').write_text(_sub_read(r/'Sources/gor/GorCore/Diag.swift').split('// BEGIN relocated BoundedDiskWriter.swift (195w 2a, behavior unchanged)\n',1)[1].split('// END relocated BoundedDiskWriter.swift',1)[0])
 (t/'BoundedSubtitleDownload.swift').write_text(_sub_read(r/'Sources/gor/Subtitles/SubtitlePreferences.swift').split('// BEGIN relocated BoundedSubtitleDownload.swift (195w 2a, behavior unchanged)\n',1)[1].split('// END relocated BoundedSubtitleDownload.swift',1)[0])
 subprocess.run([swift,str(t/'BoundedSubtitleDownload.swift'),str(_sec_file(r,'DepthCacheBudget.swift')),str(t/'BoundedDiskWriter.swift'),str(t/'main.swift'),'-o',str(t/'test')],check=True)
 subprocess.run([str(t/'test'),f'http://127.0.0.1:{server.server_port}',str(t/'cache')],check=True)
server.shutdown()
assert 'downloadTask(' not in src and 'lookup_\\(UUID()' not in src
assert src.count('BoundedSubtitleDownload.fetch(')==5
part=src[src.index('private func downloadAndLoad'):src.index('var canExportSrcSubtitle')]
assert part.index('self.loadCues(cues)')<part.index('BoundedDiskWriter.save(')
assert 'self.loadedSrcSubtitle = (moviePath: path, srtData: bytes)' in part
print('PASS both provider download routes have no disk staging; optional cache occurs after cue/export state; native UI integration parse-only')
