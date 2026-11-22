#!/usr/bin/env python3
"""191a C2: One Euro + Z hysteresis (tools/head_pose/pose_filter.py), measured on
the committed synthetic still/lean-in clip (synth_pose_clip.py, seed 191,
LABELLED SYNTHETIC - re-measure on a real Mac pose trace when one exists).

Metrics: still-phase jitter (std of filtered output while the head is still),
lean-in lag (seconds to 90% of the true Z move), still-phase fov-channel
reversals (hysteresis must make them zero), and the angle-channel lag budget.
Mutants prove each mechanism is load-bearing. Swift constant parity pinned by text.
"""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
import pathlib
import statistics
import sys

root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tools" / "head_pose"))
import pose_filter as pf  # noqa: E402
import synth_pose_clip as sc  # noqa: E402

fails = []


def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


def _raises(fn):
    try:
        fn()
        return False
    except ValueError:
        return True


def run(hyst=True, euro_z=True, angles=True):
    f = pf.PoseFilter()
    if not hyst:
        f._z_hyst = _PassThrough()
    if not euro_z:
        f._z_euro = _IdentityEuro()
    zs, yaws, ts = [], [], []
    for (t, yaw, pitch, roll, x, y, z) in sc.frames():
        fy, fp, fr, fx, fy2, fz = f.filter(yaw, pitch, roll, x, y, z, t)
        ts.append(t)
        zs.append(fz)
        yaws.append(fy)
    return ts, zs, yaws


class _PassThrough:
    def filter(self, z, t):
        return z


class _IdentityEuro:
    def filter(self, z, t):
        return z


ts, zs, yaws = run()
still_z = [z for t, z in zip(ts, zs) if 2.0 <= t <= 18.0]
still_yaw = [v for t, v in zip(ts, yaws) if 2.0 <= t <= 18.0]
jitter_z = statistics.pstdev(still_z)

# reversals of the Z (fov) channel while still
rev = sum(1 for a, b, c in zip(still_z, still_z[1:], still_z[2:])
          if (b - a) * (c - b) < 0)

# lean-in lag measured against the TRUE signal's own 90% time (the smoothstep
# tail is slow; only the filter's added delay counts)
def t90(series_t, series_z):
    return next(t for t, z in zip(series_t, series_z)
                if t >= 20.0 and z <= 600.0 - 0.9 * 200.0)
true_t90 = next(t for t in ts if t >= 20.0 and sc.true_z(t) <= 600.0 - 0.9 * 200.0)
lag = t90(ts, zs) - true_t90

# jitter of the yaw channel around the known true drift 0.03*sin(0.4t):
# the drift is signal, not noise - the filter is SUPPOSED to pass it
import math
yaw_resid = [v - 0.03 * math.sin(t * 0.4) for t, v in zip(ts, yaws) if 2.0 <= t <= 18.0]
jitter_yaw = statistics.pstdev(yaw_resid)

# final still value settles at the true 400 mm
final = statistics.mean(z for t, z in zip(ts, zs) if t >= 35.0)

print(f"measured: still z jitter {jitter_z:.3f} mm (raw sigma {sc.Z_SIGMA_MM}), "
      f"still yaw jitter {jitter_yaw:.4f} rad (raw sigma {sc.ANGLE_SIGMA_RAD}), "
      f"lean 90% lag {lag:.2f} s, still Z reversals {rev}, final Z {final:.1f} mm")

check("still Z jitter reduced >= 3x vs raw noise", jitter_z <= sc.Z_SIGMA_MM / 3.0)
check("still yaw jitter reduced >= 2.5x vs raw noise", jitter_yaw <= sc.ANGLE_SIGMA_RAD / 2.5)
check("hysteresis: zero still-phase Z reversals", rev == 0)
check("lean-in added lag <= 2.0 s past the true 90% time", lag is not None and lag <= 2.0)
check("settles at true 400 mm (+- 2 mm)", abs(final - 400.0) <= 2.0)

# mutants
_, zs_nohyst, _ = run(hyst=False)
still_nh = [z for t, z in zip(ts, zs_nohyst) if 2.0 <= t <= 18.0]
rev_nh = sum(1 for a, b, c in zip(still_nh, still_nh[1:], still_nh[2:])
             if (b - a) * (c - b) < 0)
check("mutant: no hysteresis -> still-phase reversals return (caught, %d)" % rev_nh, rev_nh > 10)
_, zs_raw, _ = run(hyst=False, euro_z=False)
still_raw = [z for t, z in zip(ts, zs_raw) if 2.0 <= t <= 18.0]
check("mutant: no Z filtering at all -> raw jitter (caught)",
      statistics.pstdev(still_raw) > 2 * jitter_z)
try:
    pf.ZHysteresis(enter_mm=-1.0)
    bad = True
except ValueError:
    bad = False
check("mutant: non-positive enter rejected", not bad)
check("mutant: settle_frames < 1 rejected",
      _raises(lambda: pf.ZHysteresis(settle_frames=0)))

# One Euro mirror pins vs the Swift source (constants must stay in lockstep)
sw = _s3read(root / "Sources/gor/Camera/ScreenCaptureEngine.swift")
for frag in ("private static let stillCutoffHz = 0.35",
             "private static let turnCutoffHz = 2.0",
             "private static let speedFilterCutoffHz = 0.3",
             "private static let angleRefSpeed = 1.0",
             "private static let boxRefSpeed = 0.25"):
    check("swift pin: " + frag, frag in sw)
check("python constants mirror swift", pf.STILL_CUTOFF_HZ == 0.35
      and pf.TURN_CUTOFF_HZ == 2.0 and pf.SPEED_FILTER_CUTOFF_HZ == 0.3
      and pf.ANGLE_REF_SPEED == 1.0 and pf.BOX_REF_SPEED == 0.25)

print("pose filter: %d failure(s)" % len(fails))
sys.exit(1 if fails else 0)
