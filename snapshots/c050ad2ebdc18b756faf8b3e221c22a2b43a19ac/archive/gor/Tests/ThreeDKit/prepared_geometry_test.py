#!/usr/bin/env python3
"""Actual pinned ToS metadata plus compiled prepare geometry and selftest consumer.
Linux Swift, not AVFoundation/CoreML/Metal acceptance. SELFTEST_SOURCE accepts a git ref.
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import hashlib, json, os, pathlib, shutil, subprocess, tempfile
R = pathlib.Path(__file__).resolve().parents[2]; S = R/'Sources/gor'
ref = os.environ.get('SELFTEST_SOURCE')
def _selftest_src():
    if ref:
        try: return subprocess.check_output(['git','show',ref+':archive/gor/Sources/gor/gor/ThreeD.swift'],cwd=R,text=True)
        except subprocess.CalledProcessError: return subprocess.check_output(['git','show',ref+':archive/gor/Sources/gor/ThreeDSelfTest.swift'],cwd=R,text=True)
    return _threed_split().path(R).read_text()
st = _selftest_src()
if '// BEGIN relocated ThreeDSelfTest.swift ' in st:
    st = st[st.index('// BEGIN relocated ThreeDSelfTest.swift '):st.index('// END relocated ThreeDSelfTest.swift\n')]
clip = R/'tools/depth_analysis/kit/x2_tos_reference/tos_input_320x180_48f.mp4'
assert len(clip.read_bytes()) == 63977
assert hashlib.sha256(clip.read_bytes()).hexdigest() == 'b7eaa61e065d9682e5d3bc2ceae3c79f46a799e792260419dffd38b10bc49956'
f = json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(clip)]))['streams'][0]
assert (f['width'],f['height'],f['sample_aspect_ratio'],int(f['nb_frames'])) == (320,180,'120:89',48)
print('PASS pinned fixture metadata: storage320x180 SAR120:89 48f, unchanged SHA')
sw = os.environ.get('SWIFTC') or shutil.which('swiftc'); assert sw, 'swiftc required'
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d); (p/'ThreeDSelfTest.swift').write_text(st)
 (p/'main.swift').write_text('''import Foundation
var facts = SourceFacts(); facts.width = 320; facts.height = 180; facts.sar = 120.0/89.0
let size = SourceFormat.normalizedSize(facts), box = VDAStream.letterbox(srcW:size.w,srcH:size.h)
precondition(size.w == 431 && size.h == 180 && box.nw == 266 && box.nh == 111)
let old = VDAStream.letterbox(srcW:320,srcH:180)
precondition(old.nw == 266 && old.nh == 150 && old.nh > box.nh + (box.nh & 1))
print("PASS actual prepare policy: normalized431x180, depth266x111 padded266x112; old266x150 rejected")
''')
 args=[sw,str(S/'SourceFormat.swift'),str(S/'VDAStreamRunner.swift'),str(p/'main.swift'),'-o',str(p/'proof')]
 subprocess.run(args,check=True); subprocess.run([str(p/'proof')],check=True)
 assert 'struct PreparedGeometry' in st, 'RED: selftest has no prepared sidecar geometry consumer'
 with (p/'main.swift').open('a') as out: out.write('''
let side: [String:Any] = ["source_width":431,"source_height":180,"depth_width":266,"depth_height":111]
let g = ThreeDSelfTest.PreparedGeometry(sidecar:side)!
precondition(g.source.w == 431 && g.source.h == 180 && g.depth.w == 266 && g.depth.h == 111)
for key in side.keys {var bad=side; bad.removeValue(forKey:key); precondition(ThreeDSelfTest.PreparedGeometry(sidecar:bad) == nil)
 bad=side; bad[key]=0; precondition(ThreeDSelfTest.PreparedGeometry(sidecar:bad) == nil)
 bad=side; bad[key] = -1; precondition(ThreeDSelfTest.PreparedGeometry(sidecar:bad) == nil)}
precondition(ThreeDSelfTest.PreparedGeometry(sidecar:["source_width":320,"source_height":180,"depth_width":266,"depth_height":150]) != nil)
print("PASS compiled selftest consumes sidecar source/depth and rejects missing/nonpositive dimensions (14 cases)")
''')
 subprocess.run(args[:-3]+[str(p/'ThreeDSelfTest.swift')]+args[-3:],check=True)
 subprocess.run([str(p/'proof')],check=True)
assert 'depthSize: geometry.depth, sourceSize: geometry.source' in st
assert 'srcW: geometry.source.w, srcH: geometry.source.h' in st
assert 'ShotSink.sidecarURL(entry, 0)' in st
assert 'depthSize: (VDAStream.letterbox(srcW: testW' not in st
print('PASS actual render call and plan use prepared geometry, not storage fixture dimensions')
