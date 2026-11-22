#!/usr/bin/env python3
"""Measured: one scan sample (software decode, -threads 2, nice 19, raw yuv444p16le frame, cropdetect) on a 3840x2160
10-bit HEVC clip, scaled to the scanner's budgets. The wt scan takes 12 samples and the file scan 40, both inside the
240 s deadline set in SourcePixelCrop.swift. Linux x86 numbers; his Mac decodes differently, so the margin is the point."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os, re, subprocess, sys, tempfile, time, pathlib
SP = (lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(pathlib.Path(__file__).resolve().parents[2])).read_text())
SW = (lambda _b: _b[_b.index('// BEGIN relocated '+'WTCropSamples.swift'+' '):_b.index('// END relocated '+'WTCropSamples.swift'+'\n')])((_threed_split().path(pathlib.Path(__file__).resolve().parents[2])).read_text())
budgets = re.search(r'let expires=started \+ \(stream \? (\d+):(\d+)\)', SP)
assert budgets, 'live scanner must mint both budgets before asynchronous admission'
stream_budget, local_budget = map(float, budgets.groups())
assert stream_budget == 90 and local_budget == 240
assert SP.index('let expires=started') < SP.index('DispatchQueue.global(qos:.utility).async { [weak self]')
budget = stream_budget
n_wt = int(re.search(r"static let sampleCount = (\d+)", SW).group(1))
tmp = tempfile.mkdtemp(); src = os.path.join(tmp, "uhd.mp4")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=3840x2160:r=24:d=4", "-threads", "1", "-c:v", "libx264", "-preset", "ultrafast", "-g", "24",
                "-pix_fmt", "yuv420p", src], check=True)
times = []
for t in (0.5, 1.5, 2.5, 3.5):
    t0 = time.time()
    r = subprocess.run(["nice", "-n", "19", "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-hwaccel", "none", "-threads", "2", "-ss", str(t), "-i", src, "-map", "0:v:0", "-an", "-sn", "-dn",
                        "-vf", "cropdetect=limit=18:round=2:reset=0:skip=0", "-frames:v", "1", "-pix_fmt", "yuv444p16le", "-f", "rawvideo", "pipe:1"], capture_output=True)
    times.append(time.time() - t0)
    assert r.returncode == 0 and len(r.stdout) == 3840 * 2160 * 6, "sample failed"
per = max(times)
print("per-sample max %.2f s (all: %s); wt %d samples = %.0f s, file 40 samples = %.0f s, stream budget %.0f s, local budget %.0f s" % (per, ", ".join("%.2f" % x for x in times), n_wt, per * n_wt, per * 40, stream_budget, local_budget))
ok = per * n_wt < stream_budget / 4 and per * 40 < local_budget
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
