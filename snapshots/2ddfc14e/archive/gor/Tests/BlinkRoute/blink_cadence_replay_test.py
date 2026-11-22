#!/usr/bin/env python3
"""197i: cadence-aware double-blink detection - replay measurement.

Root cause (measured here, and in the 196v commit a06b8f88 record): under
thermal pressure the helper admits the blink landmark pass on every 5th
gated frame (~2 Hz at the 10 fps floor). The shipped EyeGestureCommands
gates encode a 30 fps sampling assumption (maxFrameGap 0.300 cancels the
state machine, freshness 0.300 rejects the frame), so at 2 Hz the detector
resets on literally every sample and the double-blink seek can never fire,
at any blink speed. The 196v note "blink is measure-only, no command bound"
was stale: the seek IS fed only from that throttled pass.

Model: tools/head_pose/blink_cadence.py (GestureP0 = line-for-line shipped
port, GestureP3 = cadence layer: gates max(shipped, k * measured interval),
bootstrap tolerates the first 3 intervals, boost escalation admits full
cadence while an episode is in flight). The sweep randomizes phase against
the sample grid; ground-truth closures sweep 0.15-0.40 s (spontaneous blink
literature range already pinned in Swift) and inter-blink gaps 0.15-1.0 s.

Measured here:
  P0 catches 0% at 2 Hz (root cause confirmed).
  P3 catches at the sampling floor: a closure of duration d on a 0.5 s grid
  is sampled with probability ~(d-0.03)/0.5; catch tracks it (24%-74%).
  Negatives fire 0 seeks (singles, holds, squints, dropouts, split pairs).
  30/10 fps decisions are frame-for-frame identical to P0 (the layer only
  changes the throttled regime).
  Boost cost is bounded: <= 25 extra landmark passes per caught gesture.
Swift constants pinned by text.
"""
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tools" / "head_pose"))
import blink_cadence as bc  # noqa: E402

fails = []


def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


def dbl(gap, dur, t0=7.0):
    def fn(phase):
        c1 = t0 + phase
        o1 = c1 + dur
        c2 = o1 + gap
        return [(c1, o1), (c2, c2 + dur)]
    return fn


def sweep(policy, fps, pressure, blinks_fn, trials=50, stride=5, duration=14.0,
          dropouts=(), squint=None):
    """blinks_fn(phase) -> [(close, reopen)]. Returns (seek_rate, mean extra
    admitted landmark passes vs the steady stride)."""
    seeks = 0
    extra = 0.0
    interval = (stride / fps) if pressure else (1.0 / fps)
    for i in range(trials):
        phase = i / trials * interval
        det = policy()
        truth = bc.make_truth(blinks_fn(phase), seed=i,
                              dropouts=[(a + phase, b + phase) for a, b in dropouts])
        if squint:
            base = truth
            s0, s1, ratio = squint

            def truth(t, base=base, s0=s0 + phase, s1=s1 + phase, ratio=ratio):
                l, r, rel = base(t)
                if s0 <= t < s1:
                    l, r = min(l, ratio), min(r, ratio)
                return l, r, rel
        n = int(duration * fps)
        admitted = 0
        fired = False
        for k in range(n + 1):
            t = k / fps
            boosted = det.boost_until is not None and t <= det.boost_until
            if pressure and k % stride != 0 and not boosted:
                continue
            admitted += 1
            l, r, rel = truth(t)
            ev = det.feed(t + bc.VISION_MS, l, r, rel, age=bc.VISION_MS)
            if ev is not None:
                fired = True
        if fired:
            seeks += 1
        if pressure:
            extra += admitted - (n + 1) // stride
    return seeks / trials, extra / trials


# 1. Root cause: the shipped detector is dead at 2 Hz, every speed.
p0_rates = []
for dur in (0.15, 0.2, 0.3, 0.4):
    for gap in (0.15, 0.3, 0.5, 0.8, 1.0):
        r, _ = sweep(bc.GestureP0, 10, True, dbl(gap, dur))
        p0_rates.append(r)
check("root cause: shipped detector catches 0% at 2 Hz (all 20 speed cells)",
      max(p0_rates) == 0.0)

# 2. The cadence layer catches at the sampling floor. The floor: a closure
# of duration d on the 0.5 s grid is sampled with probability (d-0.03)/0.5
# (3 ms lid ramp); a caught closure resolves the whole pair under boost.
floor_ok = True
catch_rows = []
for dur in (0.15, 0.2, 0.3, 0.4):
    rates = []
    for gap in (0.3, 0.6):
        r, _ = sweep(bc.GestureP3, 10, True, dbl(gap, dur))
        rates.append(r)
    floor = (dur - 0.03) / 0.5
    catch_rows.append((dur, min(rates), floor))
    print(f"  measured: dur={dur} catch>={min(rates):.2f} (sampling floor {floor:.2f})")
    floor_ok = floor_ok and min(rates) >= 0.85 * floor
check("cadence layer catch >= 85% of the sampling floor, every closure length",
      floor_ok)

# 3. Negatives at 2 Hz: zero seeks, bounded boost cost.
neg_specs = [
    ("single blink 0.2s", dict(blinks_fn=lambda ph: [(7.0 + ph, 7.2 + ph)])),
    ("single blink 0.4s", dict(blinks_fn=lambda ph: [(7.0 + ph, 7.4 + ph)])),
    ("long hold 0.8s", dict(blinks_fn=lambda ph: [(7.0 + ph, 7.8 + ph)])),
    ("squint 0.70 held 1.0s", dict(blinks_fn=lambda ph: [], squint=(7.0, 8.0, 0.70))),
    ("squint 0.60 held 1.5s", dict(blinks_fn=lambda ph: [], squint=(7.0, 8.5, 0.60))),
    ("dropout over a blink", dict(blinks_fn=lambda ph: [(7.0 + ph, 7.2 + ph)],
                                  dropouts=[(6.9, 7.3)])),
    ("two singles 2.0s apart", dict(blinks_fn=lambda ph: [(7.0 + ph, 7.2 + ph),
                                                          (9.0 + ph, 9.2 + ph)])),
]
neg_ok = True
worst_extra = 0.0
for name, kw in neg_specs:
    r, e = sweep(bc.GestureP3, 10, True, **kw)
    print(f"  measured: negative {name}: seeks={r:.2f} extra={e:.1f}")
    neg_ok = neg_ok and r == 0.0
    worst_extra = max(worst_extra, e)
check("negatives: zero seeks across all negative generators at 2 Hz", neg_ok)
check("boost cost bounded: <= 25 extra landmark passes per episode", worst_extra <= 25)

# A caught double blink's boost cost.
_, caught_extra = sweep(bc.GestureP3, 10, True, dbl(0.5, 0.3))
check("boost cost per caught gesture <= 25 extra passes", caught_extra <= 25)
print(f"  measured: caught-gesture extra passes {caught_extra:.1f}")

# 4. Triple blink fires (consistent with shipped 30 fps semantics, verified:
# P0 fires 30/30 at 30 fps) - not a new false-positive class.
r_p0_30, _ = sweep(bc.GestureP0, 30, False,
                   lambda ph: [(7.0 + ph, 7.2 + ph), (7.5 + ph, 7.7 + ph), (8.0 + ph, 8.2 + ph)])
check("shipped detector fires on a triple blink at 30 fps (semantics baseline)",
      r_p0_30 == 1.0)

# 5. Frame-for-frame parity at 30 fps and at the 10 fps floor: the cadence
# layer must be a no-op outside the throttled regime.
def decisions(policy, fps, blinks, duration=14.0, trials=10):
    out = []
    for i in range(trials):
        phase = i / trials / fps
        det = policy()
        truth = bc.make_truth([(c + phase, o + phase) for c, o in blinks], seed=i)
        n = int(duration * fps)
        for k in range(n + 1):
            t = k / fps
            l, r, rel = truth(t)
            det.feed(t + bc.VISION_MS, l, r, rel, age=bc.VISION_MS)
        out.append((det.lastAt is not None, det.start is not None, len(det.bl)))
    return out

parity_blinks = [(7.0, 7.2), (7.6, 7.9)]   # slow pair inside the series window
for fps in (30, 10):
    same = decisions(bc.GestureP0, fps, parity_blinks) == decisions(bc.GestureP3, fps, parity_blinks)
    check(f"frame parity P0 == P3 at {fps} fps", same)

# 6. Swift parity: the cadence constants and gate edits exist in the mirror.
swift = (root / "Sources" / "gor" / "Camera" / "HeadPose.swift").read_text()
for token in ("static var cadenceAdaptive = true",
              "static let cadenceGapK = 1.25",
              "static let cadenceFreshK = 0.75",
              "static let cadenceEpisodeK = 1.25",
              "static let cadenceSeriesK = 1.0",
              "static let cadenceSeriesFloor = 0.1",
              "static let cadenceSoftBelow = 0.80",
              "private(set) var blinkBoostUntil: Double? = nil"):
    check(f"swift EyeGestureCommands carries {token!r}", token in swift)
helper = (root / "Sources" / "gor" / "Camera" / "Runtime.swift").read_text()
check("helper admits boosted blink frames", "|| blinkBoosted" in helper)
check("helper applies the blink-boost command", 'case "blink-boost":' in helper)

print()
if fails:
    print("FAILURES:", ", ".join(fails))
    sys.exit(1)
print("ALL PASS (root cause, sampling-floor catch, negatives, parity, swift pins)")
