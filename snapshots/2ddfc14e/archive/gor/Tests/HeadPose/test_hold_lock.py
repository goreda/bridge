#!/usr/bin/env python3
"""197i: output-side hold lock (tools/head_pose/pose_filter.py HoldLock),
measured on the committed synthetic tilt-and-hold clip
(synth_tilt_hold_clip.py, LABELLED SYNTHETIC - same standing caveat as the
191a clip: re-measure on a real Mac pose trace when one is committed).

Metrics per (seed x noise sigma x fps): hold-phase jitter (locked ~= 0, never
worse than the unlocked chain), added latency on a fast 0.5 rad tilt
(release must be instant), slow-pan (0.1 rad/s) transparency cost (bounded
by the band cap), and post-move steady-state offset (bounded). Mutants
prove the adaptive band and the movement gate are load-bearing. Swift
constant parity pinned by text.
"""
import pathlib
import statistics
import sys

root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tools" / "head_pose"))
import pose_filter as pf  # noqa: E402
import synth_tilt_hold_clip as th  # noqa: E402

fails = []


def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


def _euro():
    return pf.OneEuro(pf.STILL_CUTOFF_HZ,
                      (pf.TURN_CUTOFF_HZ - pf.STILL_CUTOFF_HZ) / pf.ANGLE_REF_SPEED)


def run(sigma, fps, seed, lock=None):
    euro = _euro()
    outs, base = [], []
    for (t, yaw, pitch, roll, x, y, z) in th.frames(fps=fps, sigma=sigma, seed=seed):
        sm = euro.filter(pitch, t)
        base.append((t, sm))
        outs.append((t, lock.filter(sm, t) if lock else sm))
    return outs, base


def metrics(outs, base):
    hold = statistics.pstdev([o for t, o in outs if 5.0 <= t <= 7.4])
    holdb = statistics.pstdev([o for t, o in base if 5.0 <= t <= 7.4])
    pan = max(abs(o - b) for (t, o), (_, b) in zip(outs, base) if 11.0 <= t <= 14.5)
    off = max(abs(o - b) for (t, o), (_, b) in zip(outs, base) if 15.5 <= t <= 17.0)

    def t10(data):
        for t, o in data:
            if t >= 3.0 and o >= 0.05:
                return t - 3.0
        return None
    lag = (t10(outs) or 0) - (t10(base) or 0)
    end = statistics.pstdev([o for t, o in outs if 15.0 <= t <= 17.0])
    endb = statistics.pstdev([o for t, o in base if 15.0 <= t <= 17.0])
    return dict(hold=hold, holdb=holdb, pan=pan, off=off, lag=lag, end=end, endb=endb)


SEEDS = (197, 5, 42, 7)
SIGMAS = (0.01, 0.02, 0.05)
FPSS = (30, 10)

rows = []
for seed in SEEDS:
    for sigma in SIGMAS:
        for fps in FPSS:
            lock = pf.HoldLock(pf.HOLD_ENTER_FLOOR_RAD, pf.HOLD_ENTER_K,
                               pf.HOLD_SETTLE_S, pf.HOLD_BAND_CAP_RAD)
            m = metrics(*run(sigma, fps, seed, lock))
            rows.append((seed, sigma, fps, m))
            print(f"seed{seed} sigma={sigma} fps={fps}: hold {m['hold']:.4f}/{m['holdb']:.4f} "
                  f"lag +{m['lag']:.3f}s pan {m['pan']:.4f} off {m['off']:.4f} "
                  f"end {m['end']:.4f}/{m['endb']:.4f}")

worst_hold = max(m['hold'] for _, _, _, m in rows)
worst_hold_vs_base = max(m['hold'] - m['holdb'] for _, _, _, m in rows)
worst_end_vs_base = max(m['end'] - m['endb'] for _, _, _, m in rows)
worst_lag = max(m['lag'] for _, _, _, m in rows)
worst_pan = max(m['pan'] for _, _, _, m in rows)
worst_off = max(m['off'] for _, _, _, m in rows)
quiet_hold = max(m['hold'] for _, s, _, m in rows if s <= 0.01)

# The lock's purpose: a still head produces a still image. At low noise the
# hold phase is fully locked (jitter ~0). At sigma .02+ the 10 fps noise
# wander (measured 0.024 rad) approaches half the capped band, so the lock
# may flicker - allowed, as long as it never ADDS jitter (checked below).
check("low-noise hold jitter < 0.0025 rad (locked; measured worst 0.0020)", quiet_hold < 0.0025)
check("hold jitter never worse than the unlocked chain (+0.001)", worst_hold_vs_base <= 0.001)
check("end jitter never worse than the unlocked chain (+0.001)", worst_end_vs_base <= 0.001)
# Release on first out-of-band sample: a fast tilt pays at most one extra
# sample (measured worst +0.100 s at 10 fps extreme noise).
check("fast-tilt added latency <= 0.15 s", worst_lag <= 0.15)
# Slow-pan transparency cost is the band at release, capped by design.
check("slow-pan eat <= cap + 0.005", worst_pan <= pf.HOLD_BAND_CAP_RAD + 0.005)
check("post-move offset <= cap + 0.005", worst_off <= pf.HOLD_BAND_CAP_RAD + 0.005)

# Mutant 1: fixed floor band (no adaptation) - at sigma .05 the floor band
# is inside the noise wander, so the lock flickers or never engages:
# strictly worse hold jitter than the adaptive band somewhere.
def fixed_band_lock():
    l = pf.HoldLock(pf.HOLD_ENTER_FLOOR_RAD, pf.HOLD_ENTER_K,
                    pf.HOLD_SETTLE_S, pf.HOLD_BAND_CAP_RAD)
    l.filter(0.0, 0.0)  # init
    l._mad = 0.0        # freeze the estimate at zero: band stays at floor
    orig = l.filter
    def frozen(x, t, _o=orig):
        band_before = None
        r = _o(x, t)
        l._mad = 0.0
        l.band = pf.HOLD_ENTER_FLOOR_RAD
        return r
    l.filter = frozen
    return l

mut_rows = []
for seed in SEEDS:
    for sigma in SIGMAS:
        for fps in FPSS:
            mut_rows.append(metrics(*run(sigma, fps, seed, fixed_band_lock())))
mut_worst_vs_base = max(m['hold'] - m['holdb'] for m in mut_rows)
check("mutant fixed-floor band adds jitter somewhere (adaptation load-bearing)",
      mut_worst_vs_base > worst_hold_vs_base)

# Mutant 2: no movement gate on the noise EMA - a slow pan inflates the
# band to the cap, so the pan eat stops tracking the noise level.
mut2_pan_low = []
_gate = pf.HOLD_MAD_GATE
pf.HOLD_MAD_GATE = 1e9
try:
    for seed in SEEDS:
        for fps in FPSS:
            m = metrics(*run(0.01, fps, seed,
                             pf.HoldLock(pf.HOLD_ENTER_FLOOR_RAD, pf.HOLD_ENTER_K,
                                         pf.HOLD_SETTLE_S, pf.HOLD_BAND_CAP_RAD)))
            mut2_pan_low.append(m['pan'])
finally:
    pf.HOLD_MAD_GATE = _gate
check("mutant ungated EMA eats ~cap on a low-noise pan (gate load-bearing)",
      min(mut2_pan_low) > 0.8 * pf.HOLD_BAND_CAP_RAD)

# Swift parity: the mirror in Sources/gor/Camera/HeadPose.swift must carry
# the same measured constants.
swift = (root / "Sources" / "gor" / "Camera" / "HeadPose.swift").read_text()
for token in ("holdEnterK = 8.1", "holdEnterFloorRad = 0.010",
              "holdEnterFloorBox = 0.005", "holdSettleSeconds = 0.50",
              "holdNoiseTauSeconds = 0.6", "holdBandCapRad = 0.05",
              "holdBandCapBox = 0.025", "holdMadGate = 3.0",
              "struct PoseHoldLock"):
    check(f"swift PoseHoldLock carries {token!r}", token in swift)

print()
if fails:
    print("FAILURES:", ", ".join(fails))
    sys.exit(1)
print(f"ALL PASS ({len(SEEDS) * len(SIGMAS) * len(FPSS)} measured configs + mutants + parity)")
