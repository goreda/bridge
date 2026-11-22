#!/usr/bin/env python3
"""s35: depth failure-mode guards (CONTRACT-190v s35).

Deterministic-array pins for depth_guards: sky far clamp (MoGe-invalid
keyed + heuristic), fade flatten, static overlay flatten, weighted align
fit. No models here; the model-level measurements live in
tools/depth_analysis/failure_probes.py (s35 report).
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))
import depth_guards as dg  # noqa: E402

rng = np.random.default_rng(42)
H, W = 90, 160


def textured(h=H, w=W):
    return (np.kron(rng.random((h // 2, w // 2)), np.ones((2, 2))) * 200 + 20).astype(np.float32)


# 1. sky far clamp, MoGe-invalid keyed: VDA put sky AT scene depth (the
# real failure); MoGe says +inf there. Guard must pull sky to the far plane.
inv = np.full((H, W), 100.0, np.float32)          # whole scene at one depth
inv[50:] += rng.normal(0, 5, (40, W))             # textured ground jitter
luma = np.full((H, W), 200.0, np.float32)
luma[50:] = textured(40, W)
moge_finite = np.ones((H, W), bool)
moge_finite[:45] = False                          # MoGe: sky = +inf
out = dg.sky_far_clamp(inv, luma, moge_finite=moge_finite)
far = np.percentile(inv[inv > 0], 5)
assert np.all(out[:45] <= far * 1.01), out[:45].max()   # sky pinned far
assert np.array_equal(out[60:], inv[60:]), "ground untouched"
# no-op when MoGe is fully finite and no far+flat region exists
same = dg.sky_far_clamp(inv, luma, moge_finite=np.ones((H, W), bool))
assert np.array_equal(same, inv), "finite MoGe: no-op"
print("PASS sky_far_clamp (MoGe-invalid keyed)")

# 2. fade flatten: depth swims during a fade; guard freezes it to the
# per-pixel temporal median. Healthy frames stay byte-identical.
base = 100 + rng.normal(0, 3, (H, W)).astype(np.float32)
seq = [base.copy() for _ in range(4)]
seq += [base + rng.normal(0, 40, (H, W)).astype(np.float32) for _ in range(4)]  # garbage in the dark
lum = [np.full((H, W), 120.0, np.float32) for _ in range(4)]
lum += [np.full((H, W), m, np.float32) for m in (40.0, 20.0, 8.0, 3.0)]
out = dg.fade_flatten(seq, lum)
for i in range(4):
    assert np.array_equal(out[i], seq[i]), f"bright frame {i} changed"
med = np.median(np.stack(seq), axis=0)
dev_g = float(np.median(np.abs(out[-1] - med)))
dev_b = float(np.median(np.abs(seq[-1] - med)))
assert dev_g < dev_b * 0.1, (dev_b, dev_g)   # fully-faded frame ~at the median plane
swim_before = float(np.median([np.median(np.abs(seq[i] - seq[i - 1])) for i in range(5, 8)]))
swim_after = float(np.median([np.median(np.abs(out[i] - out[i - 1])) for i in range(5, 8)]))
assert swim_after < swim_before * 0.5, (swim_before, swim_after)
print("PASS fade_flatten (disparity stops swimming; bright frames untouched)")

# 3. static overlay flatten: panning scene + static logo/subtitle ->
# overlay pixels land on the screen plane and are maskable for the fit.
frames = []
scene = textured()
for t in range(12):
    f = np.roll(scene, t, 1).copy()
    f[10:20, 120:150] = 250.0                     # logo: static, bright
    f[70:76, 30:130] = 235.0                      # subtitle line
    frames.append(np.stack([f, f, f], -1).astype(np.uint8))
m = dg.static_overlay_mask(frames)
assert m[15, 135] and m[72, 80], "overlay pixels not detected"
assert not m[40, 40], "moving scene falsely masked"
frac = m.mean()
assert 0.01 < frac < 0.2, frac
z_seq = [np.full((H, W), 5.0, np.float32) for _ in range(12)]
z_out, m2 = dg.static_overlay_flatten(z_seq, frames, z_screen=3.0)
assert np.all(z_out[0][m2] == 3.0) and np.all(z_out[0][~m2] == 5.0)
# static scene: no mask (a still frame is not an overlay)
still = [frames[0].copy() for _ in range(12)]
assert not dg.static_overlay_mask(still).any(), "static scene falsely masked"
print("PASS static_overlay_flatten (screen-plane overlays, static-scene no-op)")

# 4. weighted fit: a broken (sky/noise) region can't drag the scale.
x = rng.random((H, W)).astype(np.float32) * 50
y = 2.0 * x + 7.0
y[:30] += rng.normal(0, 60, (30, W))              # broken top band
w = np.ones((H, W), np.float32); w[:30] = 0.05
s_u, b_u = dg.fit_scale_shift_weighted(x, y)
s_w, b_w = dg.fit_scale_shift_weighted(x, y, weights=w)
assert abs(s_w - 2.0) < abs(s_u - 2.0) and abs(s_w - 2.0) < 0.05, (s_u, s_w)
assert abs(b_w - 7.0) < 1.0, (b_u, b_w)
s0, b0 = dg.fit_scale_shift_weighted(x, y)        # weights=None == plain LSQ
assert (s0, b0) == (s_u, b_u)
print("PASS fit_scale_shift_weighted (broken region de-weighted)")

# 5. texture weights: flat < textured WITHIN a frame, but a whole-frame
# flat/low-texture image blends to uniform (s45: weighting would starve
# the align fit on night/noise frames)
tw = dg.texture_weights(np.pad(textured(), 0))
flat = np.full((H, W), 128.0, np.float32)
assert dg.texture_weights(flat).min() >= 0.99 and tw.mean() > 0.5
mixed = np.vstack([flat[:H // 2], textured(H // 2, W)])
twm = dg.texture_weights(mixed)
assert twm[H // 2:].mean() > twm[:H // 2].mean() + 0.2
print("PASS texture_weights")

print("PASS test_failure_guards")
