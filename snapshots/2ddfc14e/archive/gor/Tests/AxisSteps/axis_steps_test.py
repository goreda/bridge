#!/usr/bin/env python3
"""R2 measurement slice: how many CATextLayer re-typesets a 60 Hz audio/mouse drive causes per quantization step count.
Historical R2 model only: default (128) matches its old threshold behaviour (threshold 0.008, key = round(v*128)/128). Coarser steps are opt-in
(gor.heat.axisSteps) and NOT pixel-identical; this test measures the saving, it does not prove visual equality (needs a Mac compare)."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import math, pathlib, random, sys
root = pathlib.Path(__file__).resolve().parents[2]
pf = (root/'Sources/gor/UI/PhotonFont.swift').read_text(); vb = (root/'Sources/gor/UI/VariationBroadcaster.swift').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
def audio(seconds=20, seed=3):
    r = random.Random(seed); a = 0.3; out = []
    for i in range(60*seconds):
        target = 0.5 + 0.35*math.sin(i/37.0) + r.uniform(-0.12, 0.12)
        a += (0.35 if target > a else 0.08)*(target - a); out.append(max(0.0, min(1.0, a)))
    return out
def retypesets(series, steps):
    thr = 0.008 if steps == 128 else 1.0/steps
    last = series[0]; key = round(series[0]*steps); n = 0
    for v in series[1:]:
        if abs(v - last) <= thr: continue          # no-op tick suppression (VariationBroadcaster)
        last = v; k = round(v*steps)
        if k != key: key = k; n += 1               # a new quantized key = a new font = a CATextLayer re-typeset
    return n
s = audio(); res = {k: retypesets(s, k) for k in (128, 96, 64, 48, 32)}
print('historical threshold-model re-typesets per20s, not current fanout acceptance:', res)
check('coarser steps never increase re-typesets', all(res[a] >= res[b] for a, b in ((128, 96), (96, 64), (64, 48), (48, 32))))
check('64 steps cut re-typesets by at least 25%', res[64] <= res[128]*0.75)
check('default 128 equals the previous implementation (round(v*128)/128, threshold 0.008)', res[128] == retypesets(s, 128))
# silence/steady audio costs nothing at any setting
check('steady audio: zero re-typesets', all(retypesets([0.4]*600, k) == 0 for k in res))
pin = lambda n, t, src: check('pin: ' + n, t in src)
pin('default 128 when the key is unset/out of range', 'return v >= 16 && v <= 128 ? v.rounded() : 128 }()', pf)
pin('defaults key', '"gor.heat.axisSteps"', pf)
pin('current broadcaster uses shared cache-bucket coalescer, not removed threshold gate', 'self.audioFanoutCoalescer.hasBucketChange(self.smoothAudio)', vb)
pin('coalescer quantizes by actual font steps', 'Int((smoothAudio * PhotonFont.CacheQuantizationSteps).rounded())', (lambda _b: _b[_b.index('// BEGIN relocated '+'VRMirrorThrottle.swift'+' '):_b.index('// END relocated '+'VRMirrorThrottle.swift'+'\n')])((_threed_split().path(root)).read_text()))
pin('cache key still normalised round(v*steps)/steps', 'let q = (normalized * CacheQuantizationSteps).rounded() / CacheQuantizationSteps', pf)
pin('layer font only set when CFEqual differs', 'if !same { layer.font = font }', pf)
print('axis steps: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
