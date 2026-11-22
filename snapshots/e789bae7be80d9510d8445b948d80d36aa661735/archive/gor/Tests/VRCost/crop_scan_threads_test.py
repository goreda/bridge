#!/usr/bin/env python3
"""The crop scanner's ffmpeg args (same filter/pix_fmt/seek as SourcePixelCrop.swift) with '-threads 2' under `nice -n 19`
must decode the same frames as the default thread count: raw yuv444p16le output hashes identical at 5 seek positions,
and the exact bright-pixel bounds match. Uses a synthetic 1920x1080 10-bit HEVC clip with 140 px black bars.
Also checks the Swift source carries -threads 2, nice -n 19 and the extended 240 s budget."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import hashlib, pathlib, subprocess, sys, tempfile, os
import numpy as np
root = pathlib.Path(__file__).resolve().parents[2]
clip = os.path.join(tempfile.mkdtemp(), "c.mkv")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
    "testsrc2=s=1920x1080:r=24:d=3,format=yuv420p10le,drawbox=x=0:y=0:w=1920:h=140:color=black:t=fill,drawbox=x=0:y=940:w=1920:h=140:color=black:t=fill",
    "-c:v", "libx265", "-x265-params", "log-level=error:frame-threads=2", "-pix_fmt", "yuv420p10le", clip], check=True)
def decode(t, threads, nice):
    a = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-noautorotate", "-hwaccel", "none"]
    if threads: a += ["-threads", str(threads)]
    a += ["-ss", str(t), "-i", clip, "-map", "0:v:0", "-an", "-sn", "-dn", "-vf", "cropdetect=limit=18:round=2:reset=0:skip=0",
          "-frames:v", "1", "-pix_fmt", "yuv444p16le", "-f", "rawvideo", "pipe:1"]
    if nice: a = ["nice", "-n", "19"] + a
    return subprocess.run(a, check=True, capture_output=True).stdout
def bounds(raw):
    y = np.frombuffer(raw, dtype="<u2")[:1920 * 1080].reshape(1080, 1920)
    ys, xs = np.nonzero(y > (16 + 2) * 256)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
same = True
for t in (0.2, 0.7, 1.3, 2.0, 2.7):
    a, b = decode(t, 0, False), decode(t, 2, True)
    h = hashlib.sha256(a).hexdigest()[:12] == hashlib.sha256(b).hexdigest()[:12] and bounds(a) == bounds(b)
    print("t=%.1f identical=%s bounds=%s" % (t, h, bounds(b))); same &= h
sw = (lambda _b: _b[_b.index('// BEGIN relocated '+"SourcePixelCrop.swift"+' '):_b.index('// END relocated '+"SourcePixelCrop.swift"+'\n')])((_threed_split().path(root)).read_text())
st = '"-threads","2"' in sw and '"-n","19"' in sw and "systemUptime+240" in sw
print("static structure ok:", st); print("PASS" if same and st else "FAIL"); sys.exit(0 if same and st else 1)
