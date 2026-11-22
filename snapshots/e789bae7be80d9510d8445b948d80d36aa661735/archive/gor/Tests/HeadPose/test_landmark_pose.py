#!/usr/bin/env python3
"""191a C1: landmark pose reference (tools/head_pose/landmark_pose.py) validated
on a synthetic 3D head: known (yaw, pitch, roll) rotations, orthographic
projection, then the estimator must recover each channel with the audited sign
conventions (Apple: yaw+ CCW-from-above = user turns LEFT; pitch+ = nod down;
roll+ = CCW in image; tilt to the USER'S left = roll negative) and magnitudes
within tolerance. Mutants: swapped eye labels, missing nose, degenerate eye
line. Pins the Swift anatomical-naming comment the estimator depends on.
"""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
import math
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tools" / "head_pose"))
import landmark_pose as lp  # noqa: E402

fails = []


def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


# synthetic head in USER-LOCAL axes: +x = user's right, +y = up, +z toward
# the camera. Anatomical LEFT eye at x = -0.5. Eyes (iod 1) 6-point hexagons,
# nose tip cluster at (0, -0.55, 0.45) matching NOSE_DEPTH_RATIO 0.45.
EYE_L = [(-0.5 + 0.05 * math.cos(t), 0.05 * math.sin(t), 0.0)
         for t in [i * math.pi / 3 for i in range(6)]]
EYE_R = [(0.5 + 0.05 * math.cos(t), 0.05 * math.sin(t), 0.0)
         for t in [i * math.pi / 3 for i in range(6)]]
NOSE = [(0.0, -0.55 + 0.02 * math.cos(t), 0.45 + 0.02 * math.sin(t))
        for t in [i * math.pi / 3 for i in range(6)]]


def rot(p, yaw, pitch, roll):
    """Face-local rotation with PHYSICAL signs: yaw+ = user looks RIGHT (nose
    swings to local +x); pitch+ = nod DOWN (nose drops); roll+ = user tilts
    head to THEIR LEFT (top of head swings to local -x)."""
    x, y, z = p
    cy, sy = math.cos(yaw), math.sin(yaw)      # about +y (up)
    x, z = x * cy + z * sy, -x * sy + z * cy
    cp, sp = math.cos(pitch), math.sin(pitch)  # about +x: pitch+ drops the nose
    y, z = y * cp - z * sp, y * sp + z * cp
    cr, sr = math.cos(roll), math.sin(roll)    # about z (toward camera)
    x, y = x * cr - y * sr, x * sr + y * cr
    return (x, y, z)


def project(pts, yaw, pitch, roll, scale=1.0, tx=0.0, ty=0.0):
    """Orthographic into the UNMIRRORED camera image (x right, y up,
    bottom-left origin): a facing person's right side appears at image left,
    so image x = -local x."""
    return [(-r[0] * scale + tx, r[1] * scale + ty) for r in
            (rot(p, yaw, pitch, roll) for p in pts)]


REF_CENTER = (0.0, 0.0)
CAL = lp.calibrate(project(EYE_L, 0, 0, 0), project(EYE_R, 0, 0, 0),
                   project(NOSE, 0, 0, 0), REF_CENTER)


def est(yaw=0.0, pitch=0.0, roll=0.0, scale=1.0, tx=0.0, ty=0.0, nose=True):
    return lp.estimate(project(EYE_L, yaw, pitch, roll, scale, tx, ty),
                       project(EYE_R, yaw, pitch, roll, scale, tx, ty),
                       project(NOSE, yaw, pitch, roll, scale, tx, ty) if nose else None,
                       CAL[0], CAL[1], REF_CENTER)


# neutral sanity
e = est()
check("neutral: all channels ~0", abs(e["roll"]) < 1e-9 and abs(e["yaw"]) < 1e-9
      and abs(e["pitch"]) < 1e-9 and abs(e["x"]) < 1e-9 and abs(e["y"]) < 1e-9
      and abs(e["z"]) < 1e-9)

# roll: exact under pure roll; user tilts LEFT (rot roll+) = image CW = negative
e = est(roll=math.radians(15))
check("roll: user tilts left -> exactly -15 deg (audited Apple convention)",
      abs(e["roll"] - math.radians(-15)) < 1e-9)
e = est(roll=math.radians(-45))
check("roll: user tilts right -> exactly +45 deg",
      abs(e["roll"] - math.radians(45)) < 1e-9)

# yaw: user looks right (rot yaw+) = CW seen from above = NEGATIVE (Apple)
e = est(yaw=math.radians(20))
check("yaw: user looks right -> negative, magnitude within 3 deg",
      e["yaw"] < 0 and abs(abs(e["yaw"]) - math.radians(20)) < math.radians(3))
e = est(yaw=math.radians(-20))
check("yaw: user looks left -> positive, magnitude within 3 deg",
      e["yaw"] > 0 and abs(e["yaw"] - math.radians(20)) < math.radians(3))

# pitch: nod down = positive (Apple)
e = est(pitch=math.radians(15))
check("pitch: nod down -> positive, magnitude within 3 deg",
      e["pitch"] > 0 and abs(e["pitch"] - math.radians(15)) < math.radians(3))
e = est(pitch=math.radians(-15))
check("pitch: look up -> negative", e["pitch"] < 0)

# z and translation
e = est(scale=1.2)
check("z: 20% bigger face -> z +0.2 (box-offset semantics)", abs(e["z"] - 0.2) < 1e-9)
e = est(tx=0.3, ty=-0.2)
check("x/y: translation recovered", abs(e["x"] - 0.3) < 1e-9 and abs(e["y"] + 0.2) < 1e-9)

# composed pose (look right + nod down + tilt left): signs stay right
e = est(yaw=math.radians(15), pitch=math.radians(10), roll=math.radians(8))
check("composed: yaw<0, pitch>0, roll<0 all hold",
      e["yaw"] < 0 and e["pitch"] > 0 and e["roll"] < 0)

# mutants
e_n = est(nose=False)
check("mutant: no nose -> yaw/pitch None (unavailable, not garbage), rest fine",
      e_n["yaw"] is None and e_n["pitch"] is None and abs(e_n["roll"]) < 1e-9)
swapped = lp.estimate(project(EYE_R, 0, 0, math.radians(15)),
                      project(EYE_L, 0, 0, math.radians(15)),
                      project(NOSE, 0, 0, math.radians(15)), *CAL, REF_CENTER)
check("mutant: swapped eye labels -> roll flips away from truth (caught)",
      abs(swapped["roll"] - math.radians(-15)) > math.radians(5))
check("mutant: degenerate eye line -> None",
      lp.estimate([(0, 0)], [(0, 0)], None, *CAL, REF_CENTER) is None
      or lp.estimate([(0.1, 0), (0.1, 0)], [(0.1, 0)], None, *CAL, REF_CENTER) is None)

# Swift dependency pin: the estimator requires anatomical eye naming
sw = _s3read(root / "Sources/gor/Camera/ScreenCaptureEngine.swift")
check("swift pin: 'Named leftEye/rightEye stay anatomical'",
      "Named leftEye/rightEye stay anatomical" in sw)

print("landmark pose: %d failure(s)" % len(fails))
sys.exit(1 if fails else 0)
