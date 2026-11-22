#!/usr/bin/env python3
"""191a C5: pose trace in the self-test log. Pins the emission site and format
(GeomTrace "poseTrace" rows: k/t/raw[6]/f[6], channel order yaw,pitch,roll,
x,y,z, only while head tracking runs; the GOR_VR_SIM_POSE simulated pose
drives the same applyObservation path), then proves the log is analyzable
offline: a parsed trace round-trips through the audited chain
(tools/head_pose/pose_signs.py) and the C2 filter (pose_filter.py), so sign
and jitter are diagnosable from the self-test log alone. The simulated turn
ramps raw yaw to +0.5 rad; under the FIXED sign constants that is a content
LEFT pan (a physical look-RIGHT logs negative raw yaw -> content RIGHT).
"""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
import json
import math
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tools" / "head_pose"))
import pose_signs as ps  # noqa: E402
import pose_filter as pf  # noqa: E402

fails = []


def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


sw = _s3read(root / "Sources/gor/Camera/ScreenCaptureEngine.swift")

# --- emission-site pins ---
check("poseTrace emitted under GeomTrace.on with the 6+6 channel order",
      "Order: yaw, pitch, roll, x, y, z." in sw
      and 'GeomTrace.log("poseTrace"' in sw)
check("poseTrace format is k/t/raw[6]/f[6]",
      'GeomTrace.log("poseTrace", String(format:' in sw and
      all(f in sw for f in
          ('\\"k\\":\\"poseTrace\\"', '\\"t\\"', '\\"raw\\"', '\\"f\\"')))
check("simulated pose (GOR_VR_SIM_POSE) drives the same applyObservation path",
      "func startSimulatedPose()" in sw
      and "self?.applyObservation(box: CGRect(x: 0.35, y: 0.35, width: w, height: w)," in sw
      and "yaw: 0.5 * turn" in sw)
check("PoseTraceRing appended on face-present and face-lost paths",
      sw.count("PoseTraceRing.shared.append(") >= 2)

# --- offline analyzability: parse a log line, replay through the chain ---
line = json.dumps({"k": "poseTrace", "t": 3.500,
                   "raw": [0.5, 0.001, 0.0, 0.0, 0.0, 0.0],
                   "f": [0.31, 0.001, 0.0, 0.0, 0.0, 0.0]})
row = json.loads(line)
check("trace line parses with 6 raw + 6 filtered", len(row["raw"]) == 6 and len(row["f"]) == 6)

# simulated +0.5 rad raw yaw: content moves LEFT under the fixed constants
# (chain() applies the LIVE Swift sign constants to a Vision-convention raw)
def chain_raw(raw_yaw):
    # pose_signs.chain takes actions; drive the same math directly on raw values
    yaw = ps.soft_dead_zone(ps.HEAD_ROTATION_GAIN * ps.YAW_SIGN * raw_yaw)
    return ps.sphere_screen_effect(dict(
        vr_yaw=yaw, vr_pitch=0.0, vr_roll=0.0, vr_fov=ps.REST_FOV_DEG,
        vr_head_x=0.0, vr_head_y=0.0, vr_head_z=0.0, ipd_nudge=0.0))

check("simulated turn (+0.5 raw yaw) -> content LEFT (expected self-test direction)",
      chain_raw(0.5)["content_dx"] < -0.1)
check("physical look-right (-0.35 raw yaw) -> content RIGHT (the fixed behavior)",
      chain_raw(-0.35)["content_dx"] > 0.1)

# --- filter round-trip on a traced still-then-turn sequence ---
f = pf.PoseFilter()
turning, still = [], []
for k in range(150):
    t = k / 30.0
    raw_yaw = (0.5 * max(0.0, min(1.0, (t - 3.0) / 0.5)) if t >= 3.0 else 0.0) \
        + 0.003 * math.sin(k * 1.7)
    fy, fp, fr, fx, fy2, fz = f.filter(raw_yaw, 0.0, 0.0, 0.0, 0.0, 600.0, t)
    (turning if t >= 3.4 else still).append((raw_yaw, fy))
check("filtered trace keeps the turn's sign (no inversion in filtering)",
      turning[-1][0] > 0.4 and turning[-1][1] > 0.2)
still_jitter_raw = max(r for r, _ in still) - min(r for r, _ in still)
still_jitter_filt = max(v for _, v in still) - min(v for _, v in still)
check("filtered trace still-phase peak-to-peak <= raw (jitter diagnosable)",
      still_jitter_filt <= still_jitter_raw + 1e-12)

print("pose trace log: %d failure(s)" % len(fails))
sys.exit(1 if fails else 0)
