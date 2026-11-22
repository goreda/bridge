#!/usr/bin/env python3
"""Owner log 14:37: ThreeDRenderCoordinator.tick() re-hashed the film (2 x 1 MiB, SHA256Pure) every second on the MAIN thread (2059/2063 samples in cacheKey). CacheKeyMemo: one hash per file version,
off the main thread; the tick must not call PrepareSupport.cacheKey. Compiled with swiftc on Linux."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import hashlib, os, pathlib, shutil, subprocess, sys, tempfile
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

def _station_file(root,name,station):
    b=(_threed_split().path(root) if station=='ThreeD.swift' else root/'Sources/gor'/station).read_text();p=pathlib.Path(tempfile.mkdtemp())/name;p.write_text(b.split('// BEGIN station-move '+name+'\n',1)[1].split('// END station-move '+name+'\n',1)[0]);return p

root = pathlib.Path(__file__).resolve().parents[2]
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc')
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
co = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRenderCoordinator.swift'+' '):_b.index('// END relocated '+'ThreeDRenderCoordinator.swift'+'\n')])((_threed_split().path(root)).read_text())
check('tick does not call PrepareSupport.cacheKey (main thread); it uses CacheKeyMemo', 'PrepareSupport.cacheKey' not in co and 'CacheKeyMemo.key(path: f.path)' in co)
if not swiftc or not os.path.exists(swiftc): print('SKIPPED compile: no swiftc'); sys.exit(1 if fails else 0)
tmp = pathlib.Path(tempfile.mkdtemp())
f = tmp / 'film.bin'; f.write_bytes(os.urandom(3 * 1024 * 1024))
(tmp / 'main.swift').write_text('''import Foundation
let p = CommandLine.arguments[1]
let direct = PrepareSupport.cacheKey(path: p)!
let a = CacheKeyMemo.key(path: p, background: false)!
var same = true
for _ in 0..<200 { if CacheKeyMemo.key(path: p, background: false) != a { same = false } }
print(direct == a ? 1 : 0, same ? 1 : 0, CacheKeyMemo.hashRuns)
// background: first call returns nil and starts one hash, a later call has the value, still one more run only
let q = p + ".2"; try! FileManager.default.copyItem(atPath: p, toPath: q)
let first = CacheKeyMemo.key(path: q)
var got: String? = nil; for _ in 0..<400 { got = CacheKeyMemo.key(path: q); if got != nil { break }; usleep(50_000) }
print(first == nil ? 1 : 0, got == PrepareSupport.cacheKey(path: q) ? 1 : 0, CacheKeyMemo.hashRuns)
// file changes -> rehash
let h = FileHandle(forWritingAtPath: p)!; h.seekToEndOfFile(); h.write(Data([1, 2, 3])); h.closeFile()
let b = CacheKeyMemo.key(path: p, background: false)
print(b != a ? 1 : 0, CacheKeyMemo.hashRuns)
print(CacheKeyMemo.key(path: "/nonexistent/x", background: false) == nil ? 1 : 0)
''')
r = subprocess.run([swiftc, '-O', str(_station_file(root,'CacheKeyMemo.swift','ThreeD.swift')), str(_sec_file(root,'PrepareSupport.swift')), str(_sec_file(root,'ThreeDExperimentOptions.swift')), str(_sec_file(root,'CoreMLDepthRunner.swift')), str(_sec_file(root,'FovTrackBuilder.swift')), str(tmp / 'main.swift'), '-o', str(tmp / 's')], capture_output=True, text=True)
check('compiles', r.returncode == 0)
if r.returncode: print(r.stderr[-1500:]); sys.exit(1)
o = subprocess.run([str(tmp / 's'), str(f)], capture_output=True, text=True, check=True).stdout.strip().split('\n')
a = o[0].split(); check('memo == PrepareSupport.cacheKey, 200 repeat calls return the same, exactly 1 hash run', a[0] == '1' and a[1] == '1' and a[2] == '1')
b = o[1].split(); check('background miss returns nil first, value later == cacheKey, one more hash run (total 2)', b[0] == '1' and b[1] == '1' and b[2] == '2')
c = o[2].split(); check('file changed (size/mtime) -> new key, one more hash run (total 3)', c[0] == '1' and c[1] == '3')
check('unreadable file -> nil', o[3] == '1')
print('cache key memo: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)

