"""197i: deterministic synthetic tilt-and-hold pose clip for measuring the
output-side hold lock. LABELLED SYNTHETIC - same standing caveat as
synth_pose_clip.py: re-measure against a real recorded Mac pose trace
(PoseTraceRing jsonl) when one is committed. Noise levels follow the
existing Swift synthetic study (angle sigma 0.01/0.02/0.05 rad).

Script (per fps variant): 3 s still at neutral, fast tilt to pitch 0.5 rad
in 0.5 s (a real head turn, ~1 rad/s), hold 4 s, return in 0.5 s, hold 3 s,
slow pan at 0.1 rad/s for 3 s (the transparency case: deliberate movement
well under the hold band per sample), still 3 s. Ground truth exposed for
lag measurements.
"""
import math
import random

ANGLE_SIGMAS = (0.01, 0.02, 0.05)
XY_SIGMA = 0.01
Z_SIGMA_MM = 8.0


def true_pitch(t):
    if t < 3.0:
        return 0.0
    if t < 3.5:
        return 0.5 * (t - 3.0) / 0.5
    if t < 7.5:
        return 0.5
    if t < 8.0:
        return 0.5 - 0.5 * (t - 7.5) / 0.5
    if t < 11.0:
        return 0.0
    if t < 14.0:
        return 0.1 * (t - 11.0)
    return 0.3


def frames(fps=30, sigma=0.02, seed=197):
    rnd = random.Random(seed)
    n = int(17.0 * fps)
    out = []
    for k in range(n):
        t = k / fps
        p = true_pitch(t)
        yaw = 0.03 * math.sin(t * 0.4) + rnd.gauss(0, sigma)
        pitch = p + rnd.gauss(0, sigma)
        roll = 0.02 * math.sin(t * 0.23) + rnd.gauss(0, sigma)
        x = rnd.gauss(0, XY_SIGMA)
        y = rnd.gauss(0, XY_SIGMA)
        z = 600.0 + rnd.gauss(0, Z_SIGMA_MM)
        out.append((t, yaw, pitch, roll, x, y, z))
    return out
