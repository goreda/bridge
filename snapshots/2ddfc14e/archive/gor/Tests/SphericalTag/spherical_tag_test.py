"""s36 (1): Spherical Video V2 + stereo-mode tag for vr180 render files. The Python function below is the model of SphericalTag.patch (same box layout, same offset fix);
it is run on a REAL mp4 (ffmpeg, x264/x265 here; AVAssetWriter output is the same box tree) and read back with ffprobe. Linux only; the Swift port is not compiled."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, re, struct, subprocess, sys, tempfile, json, shutil
from pathlib import Path
r = Path(__file__).resolve().parents[2]
sw = (lambda _b: _b[_b.index('// BEGIN relocated '+'SphericalTag.swift'+' '):_b.index('// END relocated '+'SphericalTag.swift'+'\n')])((_threed_split().path(r)).read_text()); wr = (lambda _b: _b[_b.index('// BEGIN relocated '+'RenderShotWriter.swift'+' '):_b.index('// END relocated '+'RenderShotWriter.swift'+'\n')])((_threed_split().path(r)).read_text())
bad = 0
def check(n, ok):
    global bad
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: bad += 1
def box(t, body): return struct.pack('>I', 8 + len(body)) + t + body
def tags():
    st3d = box(b'st3d', struct.pack('>IB', 0, 2))                                   # left-right
    svhd = box(b'svhd', struct.pack('>I', 0) + b'gor\x00')
    prhd = box(b'prhd', struct.pack('>Iiii', 0, 0, 0, 0))
    equi = box(b'equi', struct.pack('>IIIII', 0, 0, 0, 0x40000000, 0x40000000))        # 180 x 180: left = right = 90 deg of 360
    return st3d + box(b'sv3d', svhd + box(b'proj', prhd + equi))
SAMPLE_ENTRIES = {b'hvc1', b'hev1', b'avc1', b'avc3'}
def children(d, a, b):
    i = a
    while i + 8 <= b:
        sz, t = struct.unpack('>I4s', d[i:i + 8]); h = 8
        if sz == 1: sz = struct.unpack('>Q', d[i + 8:i + 16])[0]; h = 16
        if sz == 0: sz = b - i
        if sz < h or i + sz > b: raise ValueError('bad box')
        yield t, i, i + sz, i + h
        i += sz
def patch(d: bytes) -> bytes:
    top = list(children(d, 0, len(d)))
    moov = next((x for x in top if x[0] == b'moov'), None); mdat = next((x for x in top if x[0] == b'mdat'), None)
    if not moov: raise ValueError('no moov')
    if b'st3d' in d[moov[1]:moov[2]]: return d                                         # already tagged
    path = []                                                                         # moov > trak > mdia > minf > stbl > stsd > entry
    cur = moov
    for name in (b'trak', b'mdia', b'minf', b'stbl', b'stsd'):
        nxt = next((c for c in children(d, cur[3] + (8 if cur[0] == b'stsd' else 0), cur[2]) if c[0] == name), None)
        if not nxt: raise ValueError('no ' + name.decode())
        path.append(nxt); cur = nxt
    stsd = cur
    entry = next((c for c in children(d, stsd[3] + 8, stsd[2]) if c[0] in SAMPLE_ENTRIES), None)
    if not entry: raise ValueError('no video sample entry')
    add = tags()
    out = bytearray(d[:entry[2]] + add + d[entry[2]:])
    for t, a, b, h in [moov] + path + [entry]:                                      # grow every ancestor (32-bit sizes only)
        sz = struct.unpack('>I', d[a:a + 4])[0]
        if sz in (0, 1): raise ValueError('64-bit box size')
        out[a:a + 4] = struct.pack('>I', sz + len(add))
    if mdat and moov[1] < mdat[1]:                                                    # moov before mdat: every chunk offset moves
        o = bytearray(out); stbl = path[-2]
        base = stbl[1]
        for t, a, b, h in children(bytes(o), stbl[3], stbl[2] + len(add)):
            if t == b'stco':
                n = struct.unpack('>I', o[h + 4:h + 8])[0]
                for k in range(n): p = h + 8 + 4 * k; o[p:p + 4] = struct.pack('>I', struct.unpack('>I', o[p:p + 4])[0] + len(add))
            if t == b'co64':
                n = struct.unpack('>I', o[h + 4:h + 8])[0]
                for k in range(n): p = h + 8 + 8 * k; o[p:p + 8] = struct.pack('>Q', struct.unpack('>Q', o[p:p + 8])[0] + len(add))
        out = o
    return bytes(out)
def ff(*a): return subprocess.run(a, capture_output=True, text=True)
if shutil.which('ffmpeg') and shutil.which('ffprobe'):
    with tempfile.TemporaryDirectory() as t:
        for codec, lib, fast in (('hevc', 'libx265', False), ('h264', 'libx264', False), ('h264-faststart', 'libx264', True)):
            src, dst = os.path.join(t, 's.mp4'), os.path.join(t, 'p.mp4')
            args = ['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=256x128:rate=24:duration=1', '-c:v', lib, '-pix_fmt', 'yuv420p'] + (['-tag:v', 'hvc1'] if codec == 'hevc' else []) + (['-movflags', '+faststart'] if fast else []) + [src]
            if ff(*args).returncode: check(f'{codec}: fixture encode', False); continue
            d = Path(src).read_bytes(); p = patch(d); Path(dst).write_bytes(p)
            j = json.loads(ff('ffprobe', '-v', 'error', '-show_streams', '-of', 'json', dst).stdout)['streams'][0]
            sd = {x.get('side_data_type'): x for x in j.get('side_data_list', [])}
            sm = sd.get('Spherical Mapping', {})   # ffmpeg reports the crop as pixels of the tile: 180 deg of 360 on a 256 px wide picture = 128 px each side (129/127 from its rounding)
            ok_tag = 'Stereo 3D' in sd and sd['Stereo 3D'].get('type') == 'side by side' and sm.get('projection') == 'tiled equirectangular' and abs(sm.get('bound_left', 0) - 128) <= 1 and abs(sm.get('bound_right', 0) - 128) <= 1 and sm.get('bound_top') == 0 and sm.get('bound_bottom') == 0
            if not ok_tag: print('  ffprobe side data:', json.dumps(j.get('side_data_list')))
            check(f'{codec}: ffprobe reads Stereo 3D side by side + equirectangular tile bounds = 180 degrees', ok_tag)
            dec = ff('ffmpeg', '-v', 'error', '-i', dst, '-f', 'null', '-'); check(f'{codec}: the patched file still decodes cleanly (offsets valid; moov {"first" if fast else "last"})', dec.returncode == 0 and dec.stderr.strip() == '')
            a = ff('ffmpeg', '-v', 'error', '-i', src, '-f', 'framemd5', '-'); b = ff('ffmpeg', '-v', 'error', '-i', dst, '-f', 'framemd5', '-')
            check(f'{codec}: every decoded frame is byte-identical to the untagged file', a.stdout == b.stdout and a.stdout.count('\n') > 20)
            check(f'{codec}: patching twice is a no-op', patch(p) == p)
else:
    check('ffmpeg/ffprobe available for the real-file check', False)
check('swift: same box layout (st3d left-right, sv3d svhd/proj/prhd/equi, bounds 0x40000000)', all(x in sw for x in ('"st3d"', '"sv3d"', '"svhd"', '"prhd"', '"equi"', '0x4000_0000')) and 'UInt8(2)' in sw)
check('swift: offset fix for moov-before-mdat (stco and co64)', '"stco"' in sw and '"co64"' in sw and 'moovOffset < mdatOffset' in sw)
check('swift: refuses 64-bit box sizes and an unknown layout (file left untouched on any doubt)', 'return false' in sw and 'size == 0 || size == 1' in sw)
check('writer hook: only vr180, only when gor.3d.sphericalTag is on (default OFF), after finishWriting completed, a failed patch keeps the untagged file', 'SphericalTag.apply(to: out, plan: plan)' in wr and 'gor.3d.sphericalTag' in sw and 'plan.output == .vr180' in sw and 'bool(forKey: SphericalTag.defaultsKey)' in sw and 'defaultsKey = "gor.3d.sphericalTag"' in sw)
check('no player-socket words in the new Swift', not re.search(r'\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', sw, 2))
print('spherical tag: ' + ('all pins hold' if not bad else f'{bad} FAIL')); sys.exit(1 if bad else 0)
