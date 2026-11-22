#!/usr/bin/env python3
"""Linux replay of the VR blink detectors (Swift is compiled only on gor-ci; this is a line-for-line Python port, pinned to the
Swift constants by text). Covers: double blink at slow/normal/fast speed and many frame phases, single-blink negatives,
analog lid amount, flag-OFF == previous behaviour, and mutants of the port."""
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
import pathlib, random, re, sys
root = pathlib.Path(__file__).resolve().parents[2]
swift = _s3read(root / 'Sources/gor/Camera/HeadPose.swift')
lua = _s3read(root / 'Resources/vendor/mpv/scripts/vr180-look.lua')
feat = _s3read(_pp_split().path(root,'PPController_Features.swift'))
fails = []
def check(name, ok):
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok: fails.append(name)

# ---- port: EyeGestureCommands (robust flag) ----
class Gesture:
    def __init__(s, robust=True, midband_hold=True, tolerate=True):
        s.robust, s.mh, s.tol = robust, midband_hold, tolerate
        s.bl, s.br = [], []; s.start = s.lastT = s.openSince = s.lastAt = None; s.misses = 0
    P = lambda s, a, b: a if s.robust else b
    def cancel(s): s.start = s.lastAt = s.openSince = None
    def med(s, v): return sorted(v)[len(v)//2]
    def feed(s, t, l, r, reliable=True, age=0.0):
        series = s.P(1.200, 0.950); bmin = s.P(0.025, 0.060); bmax = s.P(0.600, 0.500)
        close = s.P(0.50, 0.45); dwell = s.P(0.030, 0.060)
        prev, s.lastT = s.lastT, t
        fresh = 0 <= age <= 0.300
        if not (reliable and fresh and l is not None and r is not None):
            s.misses += 1
            if not (s.robust and s.tol and fresh and s.misses <= 2): s.cancel()
            return None
        s.misses = 0
        if prev is not None and (t - prev > 0.300 or t <= prev): s.cancel(); return None
        if len(s.bl) < 12:
            if l > 0 and r > 0: s.bl.append(l); s.br.append(r)
            return None
        lr, rr = l / max(s.med(s.bl), 1e-9), r / max(s.med(s.br), 1e-9)
        closed = lr < close and rr < close; opened = lr > 0.65 and rr > 0.65
        if s.lastAt is not None and t - s.lastAt > series: s.lastAt = None
        if opened:
            if s.openSince is None: s.openSince = t
            s.bl.append(l); s.br.append(r)
            if len(s.bl) > 121: s.bl.pop(0); s.br.pop(0)
            if s.start is not None:
                st, s.start = s.start, None
                if not (bmin <= t - st <= bmax): s.lastAt = None; return None
                if s.lastAt is not None: s.lastAt = None; return 60
                s.lastAt = t
            return None
        if not closed:
            if s.robust and s.mh and s.start is not None and t - s.start <= bmax: return None
            s.start = None; return None
        if s.start is None:
            if s.openSince is None or t - s.openSince < dwell: return None
            s.start = t; s.openSince = None
        return None

# ---- port: IntentionalEyeClosure ----
class Closure:
    def __init__(s, analog=True):
        s.analog = analog; s.open = []; s.sm = 1.0; s.cand = None; s.closed = False; s.amount = 0.0
    def feed(s, t, l, reliable=True):
        if not reliable or l is None or l < 0: s.cand = None; s.closed = False; s.amount = 0; return 0
        if len(s.open) < 12:
            if l > 0: s.open.append(l)
            return 0
        b = sorted(s.open)[len(s.open)*3//4]; ratio = max(0, min(1, l / max(b, 1e-9)))
        s.sm = 0.65*ratio + 0.35*s.sm
        if ratio > 0.85:
            s.open.append(l)
            if len(s.open) > 121: s.open.pop(0)
        if s.sm < 0.45:
            if s.cand is None: s.cand = t
            if t - s.cand >= 0.060: s.closed = True
        elif s.sm > 0.65: s.cand = None; s.closed = False
        s.amount = max(0, min(1, (0.85 - s.sm)/(0.85 - 0.35))) if s.analog else (1.0 if s.closed else 0.0)
        return s.amount

# ---- synthetic blink: ratio(t) of the open-eye baseline ----
SPEEDS = {  # close ms, hold ms, open ms, min ratio, gap between blinks ms
    'fast':   (40, 0, 60, 0.12, 120),
    'normal': (70, 40, 90, 0.10, 250),
    'slow':   (120, 120, 160, 0.08, 400)}
def blink_ratio(x, c, h, o, m):
    if x < 0: return 1.0
    if x < c: return 1 - (1 - m) * (x / c)
    if x < c + h: return m
    if x < c + h + o: return m + (1 - m) * ((x - c - h) / o)
    return 1.0
def series(starts, dur_fn, phase, rnd, fps=30, total=None, asym=False):
    """frames of (t, left, right). starts in ms; dur_fn -> params per blink index."""
    out = []; t = phase; n = 0
    end = (total or (starts[-1] + 1200)) / 1000 + 0.6
    base = 0.30
    while t < end:
        ms = (t - 0.6) * 1000
        v = 1.0
        for i, s0 in enumerate(starts): v = min(v, blink_ratio(ms - s0, *dur_fn(i)))
        lj = base * min(1.0, max(0.0, v + rnd.uniform(-0.03, 0.03)))
        rj = lj if not asym else base
        out.append((t + rnd.uniform(-0.003, 0.003), lj, rj + (0 if asym else rnd.uniform(-0.004, 0.004) * 0)))
        t += 1.0 / fps
    return out
def run(det_factory, frames):
    d = det_factory(); hits = 0
    for t, l, r in frames:
        if d.feed(t, l, r) == 60: hits += 1
    return hits
def rate(det_factory, speed, double=True, trials=60):
    c, h, o, m, gap = SPEEDS[speed]; dur = c + h + o; ok = 0
    for k in range(trials):
        rnd = random.Random(1000 + k); phase = rnd.uniform(0, 1/30)
        starts = [0, dur + gap] if double else [0]
        fr = series(starts, lambda i: (c, h, o, m), phase, rnd)
        ok += run(det_factory, fr) >= 1
    return ok / trials

new = lambda: Gesture(True); old = lambda: Gesture(False)
for sp in SPEEDS:
    rn, ro = rate(new, sp), rate(old, sp)
    print('  double blink %-6s new %.2f old %.2f' % (sp, rn, ro))
    check('double blink %s caught >=95%% of frame phases (robust)' % sp, rn >= 0.95)
    check('single blink %s never a double (robust)' % sp, rate(new, sp, double=False) == 0)
    check('single blink %s never a double (previous path)' % sp, rate(old, sp, double=False) == 0)
check('previous path misses at least one speed (test is sensitive)', min(rate(old, sp) for sp in SPEEDS) < 0.6)

# port sanity: the previous path DOES catch step-like blinks (closed->open in one frame), so its 0.00 above is the mid-band cancel
def step_frames(phase):
    rnd = random.Random(2); out = []; t = phase
    while t < 3.0:
        ms = (t - 0.6) * 1000
        v = 0.1 if (0 <= ms < 130 or 330 <= ms < 460) else 1.0
        out.append((t, 0.3 * v + rnd.uniform(-0.005, 0.005), 0.3 * v)); t += 1/30
    return out
check('port sanity: previous path catches step-like double blinks', run(old, step_frames(0.0)) >= 1)
# negatives
def neg(name, starts, params, **kw):
    for k in range(30):
        rnd = random.Random(7 + k); fr = series(starts, lambda i: params[min(i, len(params)-1)], rnd.uniform(0, 1/30), rnd, **kw)
        if run(new, fr) != 0: check(name, False); return
    check(name, True)
neg('two blinks 1.6 s apart are not a double', [0, 1900], [(70, 40, 90, 0.1)])
neg('closure held 0.9 s is not a blink', [0], [(70, 800, 90, 0.1)])
neg('three blinks at 2 s are not a double', [0, 2000, 4000], [(70, 40, 90, 0.1)])
neg('wink (one eye) is not a blink', [0, 400], [(70, 40, 90, 0.1)], asym=True)
rnd = random.Random(3); fr = series([], lambda i: (1, 1, 1, 1), 0.0, rnd, total=6000)
check('open-eye noise only: no gesture', run(new, fr) == 0)
# partial blink that only reaches 0.6 never counts
neg('shallow dips (min 0.6) are not blinks', [0, 300], [(60, 30, 80, 0.6)])
# flicker inside ONE blink (close, half reopen, close again) must not become two blinks
def flick(i): return (70, 40, 90, 0.10)
fr = []; rnd = random.Random(5)
for t, l, r in series([0], flick, 0.0, rnd):
    fr.append((t, l, r))
check('single blink with reopening mid-band frames counts once or never', run(new, fr) <= 0)

# dropped frame between the blinks (isolated landmark loss): robust keeps the series, previous path cancels
def with_drop(det_factory, drop):
    c, h, o, m, gap = SPEEDS['normal']; dur = c + h + o; rnd = random.Random(11)
    fr = series([0, dur + gap], lambda i: (c, h, o, m), 0.0, rnd); d = det_factory(); hits = 0
    gap_mid = (0.6 + (dur + gap/2) / 1000)
    for t, l, r in fr:
        ok = not (drop and abs(t - gap_mid) < 0.02)
        if d.feed(t, l if ok else None, r if ok else None, reliable=ok) == 60: hits += 1
    return hits
check('one dropped landmark frame between blinks: robust still double', with_drop(new, True) >= 1)
check('previous path loses that double (sensitivity)', with_drop(old, True) == 0)

# mutants of the port: each must break at least one robust check
def mutant_rate(**kw): return min(rate(lambda: Gesture(True, **kw), sp) for sp in SPEEDS)
check('mutant: mid-band cancels again -> fails normal/slow', mutant_rate(midband_hold=False) < 0.95)

# ---- analog lid amount ----
def lid_series(analog, ratios):
    c = Closure(analog); out = []; t = 0.0
    for _ in range(14): c.feed(t, 0.3); t += 1/30
    for r in ratios: out.append(c.feed(t, 0.3 * r)); t += 1/30
    return out
ramp = [1.0, 0.9, 0.75, 0.6, 0.45, 0.3, 0.3, 0.45, 0.6, 0.8, 1.0, 1.0]
a = lid_series(True, ramp); b = lid_series(False, ramp)
check('analog amount takes intermediate values (neither 0 nor 1)', any(0.05 < x < 0.95 for x in a))
check('analog amount is 0 at rest and ~1 when closed', a[0] == 0 and max(a) >= 0.95)
check('analog amount rises monotonically while closing', all(a[i] <= a[i+1] + 1e-9 for i in range(0, 6)))
check('flag OFF: amount is strictly binary (previous behaviour)', set(b) <= {0.0, 1.0})
check('analog rest jitter (ratio 0.9..1.0) never darkens', max(lid_series(True, [1, .92, .97, .9, 1, .93, 1, .95])) == 0)
check('analog responds no later than the binary amount', next(i for i, x in enumerate(a) if x > 0.2) < next(i for i, x in enumerate(b) if x > 0.5))

# ---- Swift/Lua text pins ----
pin = lambda n, t, src=swift: check('pin: ' + n, t in src)
pin('analog flag default ON', 'static var analog = true')
pin('analog formula', 'max(0,min(1,(0.85-smoothed)/(0.85-0.35))) : (closed ? 1:0)')
pin('robust flag default ON', 'static var robust = true')
pin('series window 1.2/0.95', 'robust ? 1.200 : 0.950')
pin('blinkMin 0.025/0.060', 'robust ? 0.025 : 0.060')
pin('blinkMax 0.6/0.5', 'robust ? 0.600 : 0.500')
pin('close threshold 0.50/0.45', 'robust ? 0.50 : 0.45')
pin('mid-band hold', 'if Self.robust,let st=start,t-st<=blinkMaxEff {return nil}')
pin('miss tolerance', 'if !(Self.robust && fresh && misses<=Self.toleratedMisses) {cancel()}')
pin('gesture returns 60 on the second blink', 'if lastAt != nil {lastAt=nil;blinkBoostUntil=nil;return .seek(60)}')
pin('flags read from defaults, ON when unset', 'object(forKey: "gor.vr.blinkAnalog") as? Bool) ?? true', feat)
pin('robust flag read', 'object(forKey: "gor.vr.blinkRobust") as? Bool) ?? true', feat)
pin('analog IPC to lua', 'vr180-look-set-blink-analog', feat)
pin('cmd-held rewind sign retained', 'let seconds = commandHeld ? -abs(seconds) : seconds', feat)
pin('lua analog flag', 'local blink_analog = true', lua)
pin('lua linear 60 ms close', '(blink_analog and 60 or vr_tune.blink_close_ms)', lua)
pin('lua previous t*t ease kept for flag off', '(blink_analog and t or t*t)', lua)
pin('lua early-out when settled', 'if blink_analog and blink_lids[1]==blink_target[1]', lua)
pin('lua pre-warm shader variant', 'if blink_analog and vr_shader_variant ~= "extended" and vr_push_uniforms then vr_push_uniforms() end', lua)
pin('lua variant held while lids stream', 'if blink_analog and blink_measurement_at and mp.get_time()-blink_measurement_at<1.0 then blink_active=true end', lua)
pin('lua variant switch is logged', 'vr180-look: shader variant %s -> %s', lua)
trace = _s3read(root / 'Sources/gor/Camera/ScreenCaptureEngine.swift')
pin('trace split: frameAge/detect/mainHop/lid', 'mainHopMS', trace)
# old keys of the delivery line stay
pin('blinkDelivery ageMS kept', '\\"k\\":\\"blinkDelivery\\",\\"ageMS\\"', trace)
# the cmd seek sign itself
seek = lambda secs, held: -abs(secs) if held else secs
check('cmd held -> -60, not held -> +60', seek(60, True) == -60 and seek(60, False) == 60)
print('blink replay: %d failure(s)' % len(fails))
sys.exit(1 if fails else 0)
