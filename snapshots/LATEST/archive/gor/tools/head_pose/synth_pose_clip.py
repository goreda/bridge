"""191a C2: deterministic synthetic still/lean-in pose clip for measuring the
filter constants. LABELLED SYNTHETIC - a stand-in until a real Mac pose trace
(PoseTraceRing jsonl) is committed; noise levels follow the existing Swift
synthetic study (angle sigma 0.02 rad) plus a plausible face-box Z noise
(sigma 8 mm at 600 mm). 30 fps, 60 s: still 0-20 s, lean-in 20-30 s
(Z 600->400 mm, pitch +0.1 rad), still 30-60 s.
"""
import math
import random

FPS = 30
SEED = 191
ANGLE_SIGMA_RAD = 0.02
Z_SIGMA_MM = 8.0


def frames(seed=SEED):
    rnd = random.Random(seed)
    out = []
    for k in range(60 * FPS):
        t = k / FPS
        if t < 20.0:
            u = 0.0
        elif t < 30.0:
            u = (t - 20.0) / 10.0
            u = u * u * (3 - 2 * u)     # smooth lean
        else:
            u = 1.0
        yaw = 0.03 * math.sin(t * 0.4) + rnd.gauss(0, ANGLE_SIGMA_RAD)
        pitch = 0.1 * u + rnd.gauss(0, ANGLE_SIGMA_RAD)
        roll = 0.02 * math.sin(t * 0.23) + rnd.gauss(0, ANGLE_SIGMA_RAD)
        x = rnd.gauss(0, 0.01)
        y = rnd.gauss(0, 0.01)
        z = 600.0 - 200.0 * u + rnd.gauss(0, Z_SIGMA_MM)
        out.append((t, yaw, pitch, roll, x, y, z))
    return out


def true_z(t):
    if t < 20.0:
        return 600.0
    if t < 30.0:
        u = (t - 20.0) / 10.0
        u = u * u * (3 - 2 * u)
        return 600.0 - 200.0 * u
    return 400.0
