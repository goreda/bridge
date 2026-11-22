#!/usr/bin/env python3
"""Heat (owner sample 15:10, paused stage): the 10 Hz subtitleColorTimer took a CGWindowListCreateImage capture every tick
even while paused (ScreenCaptureEngine.swift:458/507, 222 timer samples, 151 blocked in the capture). While paused it must
sample on subtitle geometry change or once per second; playing is unchanged. Swift compiles only on Mac/CI: this pins the
text and runs a Python model of the governor over a 10 s stage per state (captures per stage = the thermal acceptance)."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
import pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]
gov = _s3read(root/'Sources/gor/GorSubtitles/SubtitleSampleGovernor.swift')
eng = _s3read(root/'Sources/gor/Camera/ScreenCaptureEngine.swift')
ppc = _s3read(_pp_split().path(root,'PPController.swift'))
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
check('governor: playing always samples', 'guard paused else { return true }' in gov)
check('governor: paused wakes on signature change or interval', 'sig != lastSignature || now - lastSampleAt >= Self.pausedInterval' in gov)
check('governor: pause/resume edge resets', 'if paused != oldValue { lastSignature = nil; lastSampleAt = -.infinity }' in gov)
check('engine: only the subtitle tick is gated, panel sampling untouched', '!subtitleOnly || SubtitleSampleGovernor.shared.shouldSample(' in eng and 'withTimeInterval: 2.0' in eng)
check('engine: timer cadence unchanged (0.1 s)', 'Timer(timeInterval: 0.1, repeats: true)' in eng)
check('engine: signature is the registered subtitle frames', 'signature: { sampledElements.map { $0.frameProvider() } }' in eng)
check('pause edge feeds governor from the single mpv pause observation', 'subtitleView.playbackPaused = p; SubtitleSampleGovernor.shared.paused = p' in ppc)
check('governor: thermal playing spacing present (95 C report 2026-11-15)', 'HeatTelemetry.thermalPressure' in gov and 'Self.thermalPlayingInterval' in gov)
check('governor: thermal wake on subtitle geometry change', 'sig != lastSignature || now - lastThermalSampleAt >= Self.thermalPlayingInterval' in gov)
class G:
    def __init__(s, interval=1.0): s.paused=False; s.sig=None; s.last=float('-inf'); s.i=interval
    def set_paused(s, p):
        if p != s.paused: s.sig=None; s.last=float('-inf')
        s.paused = p
    def should(s, sig, now):
        if not s.paused: return True
        if sig != s.sig or now - s.last >= s.i:
            s.sig=sig; s.last=now; return True
        return False
def stage(paused, sigs, secs=10, gov=True):
    g = G(); g.set_paused(paused); n = 0; hits = []
    for k in range(int(secs*10)):
        t = k*0.1; sig = sigs(t)
        if (g.should(sig, t) if gov else True): n += 1; hits.append(round(t,1))
    return n, hits
static = lambda t: ('sub',)
play_n, _ = stage(False, static)
check('model: playing still samples every tick (100/10 s)', play_n == 100)
pn, _ = stage(True, static)
check('model: paused static subtitle <= 10 captures/10 s (was 100)', pn <= 10 and pn < 100)
changed = lambda t: ('A',) if t < 3.05 else ('B',) if t < 6.05 else (None,)
cn, hits = stage(True, changed)
check('model: subtitle appear/change/hide while paused samples within one tick', 3.1 in hits and 6.1 in hits)
check('model: paused with moving subtitle samples every tick (no staleness)', stage(True, lambda t: (round(t,1),))[0] == 100)
check('model: seek/frame-step with static subtitle sampled within 1 s', max(b-a for a,b in zip(stage(True, static)[1], stage(True, static)[1][1:])) <= 1.0 + 1e-9)
g = G(); g.set_paused(True); g.should(('x',), 0.0); g.set_paused(False); g.set_paused(True)
check('model: resume then re-pause samples first tick', g.should(('x',), 0.1))
check('model: ungated mutant is caught', stage(True, static, gov=False)[0] == 100 != pn)
print('subtitle sample paused: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
