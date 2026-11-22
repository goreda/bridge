#!/usr/bin/env python3
"""Crop scan on a partially downloaded stream (the magnet/wt case), measured with real ffmpeg.

A letterboxed 60 s clip is served over HTTP like the wt server serves a torrent: only the first 35% of the file
exists, a range request past it fails. The scan loop is the scanner's own ffmpeg command (software decode, cropdetect,
-ss seek, one raw frame). Old behaviour: 40 positions over the whole duration. New behaviour: positions from
WTCropSamples.positions over the downloaded ranges (Python mirror of the Swift function, checked against its source
text). Also checks the menu path: reDetectCrop resets the file lock and calls detect(), and detect() passes the wt
positions to the scanner."""
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
import http.server, os, pathlib, re, subprocess, sys, tempfile, threading
ROOT = pathlib.Path(__file__).resolve().parents[2]
SW = (lambda _b: _b[_b.index('// BEGIN relocated '+'WTCropSamples.swift'+' '):_b.index('// END relocated '+'WTCropSamples.swift'+'\n')])((_threed_split().path(ROOT)).read_text())
PC = (_pp_split().path(ROOT,'PPController.swift')).read_text() + '\n' + (ROOT / 'Sources/gor/Picture/CropDetector.swift').read_text()   # the detector moved out of PPController (Viewport/CropDetector.swift); the detect() pins follow it there
SP = (lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(ROOT)).read_text())
fails = []
def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok: fails.append(name)

# -- static: wiring --------------------------------------------------------------------------------------------------
check("detect() passes WTCropSamples positions to the scanner", "positions:{ WTCropSamples.positions(path:filePath,mainIPCPath:self.mainIPCPath,manual:manualPriority,widenLevel:widenLevel) }" in PC)
check("scanner uses override positions when given", "let overridePositions: [Double]? = samplePositions?()" in SP and "if let op = overridePositions { positions = op }" in SP and "else if d > 0 { positions = (0..<40).map" in SP)
check("menu Detect path: reDetectCrop resets lock then detect()", re.search(r"func reDetectCrop\(\).*?cropDetector\.resetLastFile\(\)\s*cropDetector\.detect\(", PC, re.S) is not None)
check("positions are computed inside the scan queue, not on the main thread in detect()", SP.index("DispatchQueue.global(qos:.utility).async") < SP.index("samplePositions?()"))
check("a partial-stream scan needs >=3 decoded samples (or all it has) before it may crop", "let needSamples: Int = samplePositions == nil ? 1 : min(3, positions.count)" in SP and "guard sampled >= needSamples, let b = all" in SP)
check("scan success is logged with samples, bounds and whether positions were overridden", "[cropdetect] scan done: sampled=" in SP and "override=" in SP)
check("scan failure is logged with sample count", "scan produced no samples" in SP)

# -- python mirror of WTCropSamples.positions ------------------------------------------------------------------------
TAIL, MINR, N = (float(re.search(r"static let %s = ([0-9.]+)" % k, SW).group(1)) for k in ("tailMargin", "minRange", "sampleCount"))
N = int(N)
def positions(ranges, count=N):
    use = sorted((max(0, a), b - TAIL) for a, b in ranges if b - a >= MINR and b - TAIL > max(0, a))
    total = sum(b - a for a, b in use)
    if total <= 0: return []
    out = []
    for i in range(count):
        u = total * (i + .5) / count
        for a, b in use:
            if u <= b - a: out.append(a + u); break
            u -= b - a
    return out

# -- real ffmpeg against a partial http source -----------------------------------------------------------------------
tmp = tempfile.mkdtemp()
src = os.path.join(tmp, "full.mp4")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=640x360:r=24:d=60", "-vf", "drawbox=x=0:y=0:w=640:h=45:color=black:t=fill,drawbox=x=0:y=315:w=640:h=45:color=black:t=fill",
               "-c:v", "libx264", "-g", "24", "-pix_fmt", "yuv420p", "-movflags", "+faststart", src], check=True)
data = open(src, "rb").read(); have = int(len(data) * 0.35)
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        start = 0; rng = self.headers.get("Range")
        if rng: start = int(re.match(r"bytes=(\d+)", rng).group(1))
        if start >= have:
            self.send_response(503); self.send_header("Content-Length", "0"); self.end_headers(); return
        body = data[start:have]
        self.send_response(206 if rng else 200)
        self.send_header("Accept-Ranges", "bytes"); self.send_header("Content-Length", str(len(body)))
        self.send_header("Content-Range", "bytes %d-%d/%d" % (start, have - 1, len(data)))
        self.end_headers()
        try: self.wfile.write(body)
        except Exception: pass
    do_HEAD = do_GET
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H); threading.Thread(target=srv.serve_forever, daemon=True).start()
url = "http://127.0.0.1:%d/v.mp4" % srv.server_port

def sample(t):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-hwaccel", "none", "-rw_timeout", "3000000", "-threads", "2", "-ss", str(t), "-i", url, "-map", "0:v:0", "-an", "-sn", "-dn",
                        "-vf", "cropdetect=limit=18:round=2:reset=0:skip=0", "-frames:v", "1", "-pix_fmt", "yuv444p16le", "-f", "rawvideo", "pipe:1"], capture_output=True, timeout=30)
    return r.returncode == 0 and len(r.stdout) == 640 * 360 * 6
old = [min(60 - .001, 60 * (i + .5) / 40) for i in range(40)]
old_ok = sum(sample(t) for t in old[::4])          # every 4th of the 40 positions keeps the test fast
# the player's seekable range for the same stream: what it read through the server = the downloaded part
dl_seconds = 60 * 0.35 - 2
new = positions([(0.0, dl_seconds)])
new_ok = sum(sample(t) for t in new)
print("old positions: %d/%d samples ok (10 probed of 40); new positions: %d/%d ok, span %.1f-%.1f s" % (old_ok, 10, new_ok, len(new), min(new), max(new)))
check("old whole-file positions mostly fail on a partial stream", old_ok <= 5)
check("new downloaded-range positions all decode", new_ok == len(new) and len(new) == N)
check("every new position lies inside the downloaded range with tail margin", all(0 <= t <= dl_seconds - TAIL for t in new))
check("no usable range gives no positions (falls back to time-pos or whole-file)", positions([]) == [] and positions([(5.0, 6.0)]) == [])
check("two ranges are both sampled", len({int(t // 100) for t in positions([(0, 40), (200, 260)])}) == 2)
def played_fallback(now):
    out = []
    for back in (4.0, 2.0, 0.5):
        t = max(0, now - back)
        if not any(abs(x - t) < .25 for x in out): out.append(t)
    return out
check("Swift fallback constants match the mirror", "[4.0, 2.0, 0.5]" in SW and "abs($0 - t) < 0.25" in SW and "return playedFallback(now: now)" in SW)
check("fallback: mid-stream gives 3 played seconds, all before now", len(played_fallback(100)) == 3 and max(played_fallback(100)) < 100)
check("fallback: at the very start collapses to distinct seconds only", played_fallback(0.2) == [0])
fb = played_fallback(dl_seconds)
fb_ok = sum(sample(t) for t in fb)
check("fallback positions decode on the partial server (%d/%d)" % (fb_ok, len(fb)), fb_ok == len(fb))
srv.shutdown()
print("PASS" if not fails else "FAIL"); sys.exit(1 if fails else 0)
