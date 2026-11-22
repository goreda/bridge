#!/usr/bin/env python3
"""SourceFormat.swift (pure Foundation, compiled and run here) vs tools/depth_analysis/colorprobe.py: refuse verdicts (HDR/DV/VFR), normalized size (rotation + SAR),
untagged-matrix size rule, display transform fills the normalized box, bit depth from codec config. Run: SWIFTC=... python3 Tests/SourceFormat/source_format_test.py"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, subprocess, sys, tempfile, itertools
from pathlib import Path
root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'tools/depth_analysis'))
import colorprobe as C
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

swiftc = os.environ.get('SWIFTC', 'swiftc'); tmp = Path(tempfile.mkdtemp()); exe = tmp / 'sf'
r = subprocess.run([swiftc, '-O', str(_sec_file(root,'SourceFormat.swift')), str(root / 'Tests/SourceFormat/main.swift'), '-o', str(exe)], capture_output=True, text=True)
if r.returncode: print(r.stderr); sys.exit(1)
cases = []
for (w, h), rot, sar, bd, tr, mx, (avg, mxf), dv in itertools.product([(96, 64), (97, 63), (1920, 1080), (720, 576), (1280, 534)], [0, 90, 180, 270], [1.0, 2.0, 0.75],
        [8, 10], ['bt709', 'smpte2084', 'arib-std-b67', 'smpte428', 'unknown'], ['bt709', 'unknown', 'smpte170m', 'bt2020nc'], [(24.0, 24.0), (29.97, 30.0), (24.0, 30.0), (25.0, 60.0)], [0, 1]):
    cases.append((w, h, rot, sar, bd, tr, mx, avg, mxf, dv))
lines = ['%d %d %d %r %d %s unknown %s %r %r %d' % c for c in cases]
out = subprocess.run([str(exe)], input='\n'.join(lines) + '\n', capture_output=True, text=True, check=True).stdout.splitlines()
assert len(out) == len(cases)
for (w, h, rot, sar, bd, tr, mx, avg, mxf, dv), o in zip(cases, out):
    p = dict(width=w, height=h, rotation=rot, sar=sar, sar_str='x', bit_depth=bd, pix_fmt='p', color_transfer=tr, color_primaries='unknown', color_space=mx, color_range='tv',
             dolby_vision=bool(dv), codec_tag_string='dvh1', profile='p', vfr=abs(mxf - avg) / avg > C.VFR_REL_TOL, r_fps=mxf, avg_fps=avg)
    t = o.split(); want = C.verdicts(p); ws = [s for _, s, _ in want]
    nw, nh = C.normalized_size(p)
    assert (int(t[1]), int(t[2])) == (nw, nh), (o, nw, nh)
    assert t[3] == C.matrix_for(p), (o, C.matrix_for(p))
    assert int(t[0]) == len(C.refuse_reasons(p)), (o, C.refuse_reasons(p))
    assert int(t[4]) == int(p['vfr']), o

    st = t[5].split(',')
    for dim, i in (('bit_depth', 0), ('hdr_transfer', 1), ('dolby_vision', 2), ('sar', 3), ('rotation', 4), ('vfr', 5)):
        ref = [s for d, s, _ in want if d == dim][0]; assert st[i] == ref, (dim, st[i], ref, o)
print('verdicts ok', len(cases), 'cases')
# the s34 fixture pins from the contract: 96x64 rot90 -> 64x96, sar 2:1 -> 128x64
pin = subprocess.run([str(exe)], input='96 64 90 1.0 8 bt709 unknown bt709 24.0 24.0 0\n64 64 0 2.0 8 bt709 unknown bt709 24.0 24.0 0\n', capture_output=True, text=True).stdout.split('\n')
assert pin[0].split()[1:3] == ['64', '96'] and pin[1].split()[1:3] == ['128', '64'], pin
# preferredTransform patterns of real files -> rotation; the display transform maps all four storage corners onto the normalized box
pts = {0: (1, 0, 0, 1, 0, 0), 90: (0, 1, -1, 0, 64, 0), 180: (-1, 0, 0, -1, 96, 64), 270: (0, -1, 1, 0, 0, 96)}
tl = []
for rot, p in pts.items():
    for sar in (1.0, 2.0): tl.append('T %s %r 96 64' % (' '.join(str(x) for x in p), sar))
out = subprocess.run([str(exe)], input='\n'.join(tl) + '\n', capture_output=True, text=True, check=True).stdout.splitlines()
k = 0
for rot in pts:
    for sar in (1.0, 2.0):
        t = out[k].split(); k += 1; assert int(t[1]) == rot, (rot, t)
        a, b, c, d, tx, ty = [float(x) for x in t[2:]]
        nw, nh = C.normalized_size(dict(width=96, height=64, sar=sar, rotation=rot))
        xs = [a * x + c * y + tx for x in (0, 96) for y in (0, 64)]; ys = [b * x + d * y + ty for x in (0, 96) for y in (0, 64)]
        assert abs(min(xs)) < 1e-9 and abs(min(ys)) < 1e-9 and abs(max(xs) - nw) < 1e-9 and abs(max(ys) - nh) < 1e-9, (rot, sar, xs, ys, nw, nh)
print('display transform ok (rotation x sar fill the normalized box)')
bd = subprocess.run([str(exe)], input='B - -\nB ' + '00' * 17 + '02 -\nB ' + '00' * 17 + '00 -\nB - 016e00\nB - 01\n', capture_output=True, text=True, check=True).stdout.split('\n')
assert [x.split()[1] for x in bd[:5]] == ['8', '10', '8', '10', '8'], bd
print('bit depth ok')
wl = ['W %d %d' % (v, f) for f in (0, 1) for v in range(256)]
wo = subprocess.run([str(exe)], input='\n'.join(wl) + '\n', capture_output=True, text=True, check=True).stdout.splitlines()
for line, w in zip(wo, wl):
    _, v, f = w.split(); v = int(v); got = int(line.split()[1]); assert got & 63 == 0
    want = v << 2 if f == '0' else round(v * 1023 / 255)
    assert abs((got >> 6) - want) <= 1, (w, got >> 6, want)
    if f == '0': assert (got >> 6) == want
assert [int(wo[i].split()[1]) >> 6 for i in (0, 255, 256, 511)] == [0, 1020, 0, 1023], 'endpoints'
print('widen ok (video exact, full within 1 code, full 255 -> 1023)')
# 195k grid witnesses: Swift gridCFR and colorprobe.sample_grid_cfr must agree.
quantized = [round(i*1001/24)-round((i-1)*1001/24) for i in range(1,120)] # actual ordered PTS
#                       # measured on stream-copied 24000/1001 (195k evidence, reproduced)
mixed = ([41.667, 33.333] * 60)                             # true 24/30 mixed cadence
dropped = [41.708] * 50 + [83.417] + [41.708] * 48          # one 2-tick gap: consistent
drift = [41.708 + (i % 7) * 3.0 for i in range(100)]        # wandering cadence: refuse
short = [41.708] * 10                                       # < 30 samples: abstain (metadata path)
for name, deltas, want in (("quantized", quantized, True), ("mixed", mixed, False),
                            ("dropped", dropped, False), ("drift", drift, False), ("cumulative-drift", [42.0]*84+[41.0]*35, False),
                            ("late-VFR", [41.708]*300+[33.333]*60, False),
                            ("duplicate-PTS", [41.708]*50+[0]+[41.708]*50, False)):
    assert C.sample_grid_cfr(deltas) == want, name
    line = '1920 1080 0 1.0 8 bt709 unknown bt709 23.976 24.39 0 1.0 ' + ','.join('%r' % d for d in deltas)
    o = subprocess.run([str(exe)], input=line + '\n', capture_output=True, text=True, check=True).stdout.strip()
    assert o.split()[4] == ('0' if want else '1'), (name, o)
assert C.sample_grid_cfr(short) is None
line = '1920 1080 0 1.0 8 bt709 unknown bt709 23.976 24.39 0 1.0 ' + ','.join('%r' % d for d in short)
o = subprocess.run([str(exe)], input=line + '\n', capture_output=True, text=True, check=True).stdout.strip()
assert o.split()[4] == '1', ('short-falls-back-to-metadata', o)   # 23.976 vs 24.39 metadata still refuses
print('grid witnesses OK')
# Real no-transcode container witness through the production Python probe.
import shutil
if shutil.which('ffmpeg') and shutil.which('ffprobe'):
    with tempfile.TemporaryDirectory() as folder:
        d=Path(folder)
        def ff(*args):subprocess.run(['ffmpeg','-v','error',*map(str,args)],check=True)
        ff('-f','lavfi','-i','testsrc2=size=160x90:rate=24000/1001:duration=5','-c:v','libx264','-y',d/'cfr.mp4')
        ff('-i',d/'cfr.mp4','-map','0:v:0','-c','copy','-an','-y',d/'cfr.mkv')
        ff('-i',d/'cfr.mkv','-map','0:v:0','-c','copy','-an','-y',d/'remux.mp4')
        deltas=C.sample_deltas(str(d/'remux.mp4'))
        assert len(deltas)==119 and set(round(x) for x in deltas)=={41,42}
        assert C.sample_grid_cfr(deltas) is True
        assert not C.probe(str(d/'remux.mp4'))['vfr']
        print('PASS actual MP4->MKV->MP4 CFR timestamp quantization, full-timeline probe')
