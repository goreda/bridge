#!/usr/bin/env python3
"""191r audio-time typography cost regression.

The measured owner session had 90 listeners and audio-only fan-outs on the
main thread. The fix must make the audio-only path quantized and coalesced,
and must publish its measured fan-out cost. This test first replays the
owner-shaped cadence against a model of the required decision rule, then pins
the production call and runtime measurement. It intentionally fails before
the Swift fix lands.
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os, re, sys

ROOT = Path(os.environ.get('GOR_ROOT', Path(__file__).resolve().parents[2]))
vb = (ROOT / 'Sources/gor/UI/VariationBroadcaster.swift').read_text()
throttle = (lambda _b: _b[_b.index('// BEGIN relocated '+'VRMirrorThrottle.swift'+' '):_b.index('// END relocated '+'VRMirrorThrottle.swift'+'\n')])((_threed_split().path(ROOT)).read_text())
fails = []

def check(name, ok):
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok:
        fails.append(name)

steps_match = re.search(r'CacheQuantizationSteps[^\n]*(?:\n[^\n]*)?:\s*Double\s*=\s*\{[^}]*?:\s*(\d+)\s*\}()', (ROOT / 'Sources/gor/UI/PhotonFont.swift').read_text(), re.S)
gap_match = re.search(r'static\s+let\s+minGap:\s*TimeInterval\s*=\s*([0-9.]+)', throttle)
steps = int(steps_match.group(1)) if steps_match else 128
gap = float(gap_match.group(1)) if gap_match else 0.016
check('model: font quantization steps and audio coalescing gap are present', steps_match is not None and gap_match is not None)

def model(stream, steps=steps, gap=gap):
    last_bucket = None
    last_fanout = -10**9
    out = []
    for t, smooth, mouse_moved in stream:
        bucket = round(smooth * steps)
        if mouse_moved:
            last_bucket = bucket
            last_fanout = t
            out.append(t)
        elif bucket != last_bucket and t - last_fanout >= gap:
            last_bucket = bucket
            last_fanout = t
            out.append(t)
    return out

# Owner-shaped burst: the raw envelope changes every 16 ms. A same-bucket
# run must not fan out; bucket changes are coalesced to the measured gap.
stream = []
for i in range(125):
    stream.append((i / 60.0, (i % 40) / (steps * 40), False))
fanouts = model(stream)
check('model: a changing audio envelope is coalesced to at most 10 fan-outs/s', len(fanouts) / (stream[-1][0] + 1 / 60.0) <= 10.0)
same_bucket = model([(i / 60.0, 0.421 + 0.00001 * (i % 2), False) for i in range(60)])
check('model: no audio-only fan-out without a font-quantization bucket change', len(same_bucket) <= 1)
mouse = model([(0.0, 0.421, False), (0.050, 0.421, True), (0.060, 0.421, False)])
check('model: pointer movement stays immediate and absorbs the latest audio bucket', mouse == [0.0, 0.050])

check('production: pure quantized/coalesced audio fan-out gate exists',
      'struct AudioFanoutCoalescer' in throttle and
      'quantizedBucket' in throttle and
      'bucket != lastBucket' in throttle and
      'now - lastFanout' in throttle)
check('production: audio-only updates call the coalescer before notifyListeners',
      re.search(r'audioFanoutCoalescer\.allow\(now:\s*now,\s*smoothAudio:\s*self\.smoothAudio', vb) is not None)
check('production: mouse fan-outs absorb the current audio bucket to avoid a duplicate audio pass',
      re.search(r'audioFanoutCoalescer\.noteFanout\(now:\s*now,\s*smoothAudio:\s*self\.smoothAudio\)', vb) is not None)
check('production: listener fan-out main-thread cost is measured in milliseconds',
      'fanoutBegan' in vb and 'fanout_ms' in vb and re.search(r'diagnosticFanout.*MS', vb) is not None)
check('production: raw 60 Hz audio threshold no longer gates the fan-out',
      'lastNotifiedSmoothAudio' not in vb)

print('audio fanout coalescer: %d failure(s)' % len(fails))
sys.exit(1 if fails else 0)
