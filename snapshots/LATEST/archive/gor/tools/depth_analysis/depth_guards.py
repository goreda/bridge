"""s35: depth failure-mode guards (CONTRACT-190v s35).

Pure-numpy guards applied between the aligned depth and the quantiser/
render, plus a weighted align fit. Each guard is a no-op outside its
failure mode (never lowers Tier 1 quality on healthy content) and has a
pin in Tests/DepthAnalysis/test_failure_guards.py.

Guards:
  sky_far_clamp        - sky/infinite regions: VDA sky depth is noisy and
                         MoGe-2 emits +inf there; clamp sky to the far
                         plane so clouds don't hover nearer than mountains.
  fade_flatten         - fades to black: depth goes meaningless as luma
                         collapses; blend toward the per-pixel temporal
                         median so disparity stays stable instead of
                         swimming through the fade.
  static_overlay_flatten - burned-in subtitles/logos/black bars: pixels
                         static in screen space while the scene moves get
                         flattened to the screen (convergence) plane and
                         excluded from the align fit.
  fit_scale_shift_weighted / ShotAligner weights - confidence-weighted
                         LSQ: flat/sky/noise pixels carry little weight so
                         a broken region can't drag the whole shot's scale.
"""
import numpy as np


# ---------- shared helpers ----------

def _local_std(x, w=5):
    """Cheap local std via box means (w x w)."""
    from scipy.ndimage import uniform_filter
    x = x.astype(np.float32)
    m = uniform_filter(x, w)
    m2 = uniform_filter(x * x, w)
    return np.sqrt(np.maximum(m2 - m * m, 0.0))


def _box_std(x, w=5):
    """Local std via integral image; no scipy dependency."""
    x = x.astype(np.float32)
    p = np.pad(x, ((1, 0), (1, 0)))
    c = p.cumsum(0).cumsum(1)
    c2 = (p * p).cumsum(0).cumsum(1)

    def win(cs):
        h, wdt = x.shape
        out = np.empty_like(x)
        for j in range(h):
            y0, y1 = max(0, j - w // 2), min(h, j + w // 2 + 1)
            for i in range(wdt):
                x0, x1 = max(0, i - w // 2), min(wdt, i + w // 2 + 1)
                n = (y1 - y0) * (x1 - x0)
                out[j, i] = (cs[y1, x1] - cs[y0, x1] - cs[y1, x0] + cs[y0, x0]) / n
        return out

    m = win(c)
    m2 = win(c2)
    return np.sqrt(np.maximum(m2 - m * m, 0.0))


def local_std(x, w=5):
    try:
        return _local_std(x, w)
    except Exception:
        return _box_std(x, w)


# ---------- 1. sky ----------

def sky_mask(inv, luma, top_frac=0.5, tex_thresh=3.0, far_q=5.0):
    """Sky candidate mask: top rows, low texture, inverse depth at the far
    end. inv = inverse depth (larger = nearer); luma float [H,W]."""
    h = inv.shape[0]
    valid = np.isfinite(inv) & (inv > 0)
    if valid.sum() < 16:
        return np.zeros(inv.shape, bool)
    far = np.percentile(inv[valid], far_q)
    rows = np.zeros(inv.shape, bool)
    rows[: int(h * top_frac)] = True
    tex = local_std(luma)
    return valid & rows & (inv <= far * 1.5) & (tex <= tex_thresh)


def sky_far_clamp(inv, luma, top_frac=0.5, far_q=5.0, moge_finite=None):
    """Clamp sky candidate pixels to the far plane (the far_q percentile of
    valid inverse depth). No-op when no sky-like region exists.

    moge_finite: optional [H,W] bool of the nearest MoGe keyframe's finite
    mask (resized). MoGe-2 emits +inf at true sky/infinity, which is the
    reliable sky signal: VDA relative depth often puts sky AT scene depth
    (s35 sky probe: sky inv == median inv), so an inv-only mask misses
    exactly the broken case. With moge_finite, candidates are non-finite
    MoGe pixels in the top region with low texture; without it, the
    inv+texture heuristic applies."""
    out = inv.copy()
    valid = np.isfinite(inv) & (inv > 0)
    if valid.sum() < 16:
        return out
    if moge_finite is not None:
        h = inv.shape[0]
        rows = np.zeros(inv.shape, bool)
        rows[: int(h * top_frac)] = True
        tex = local_std(luma)
        m = (~moge_finite) & rows & (tex <= 3.0)
        # MoGe-invalid pixels often quantise to inv<=0 already; include them
        m |= (~moge_finite) & rows & (tex <= 3.0) & ~valid
        if m.sum() >= 64:
            out[m] = np.percentile(inv[valid], far_q)
        return out
    m = sky_mask(inv, luma, top_frac, far_q=far_q)
    if m.sum() >= 64:
        out[m] = np.percentile(inv[valid], far_q)
    return out


# ---------- 2. fade to black ----------

def fade_amounts(luma_seq, dark=6.0):
    """Per-frame fade amount in [0,1]: 0 = full brightness, 1 = black.
    a = 1 - mean_luma / running_max; only counts once the frame is at
    least half faded so normal dim scenes are untouched."""
    m = np.array([float(np.mean(f)) for f in luma_seq])
    peak = np.maximum.accumulate(np.maximum(m, 1e-6))
    a = 1.0 - m / peak
    return np.where(a >= 0.5, a, 0.0)


def fade_flatten(inv_seq, luma_seq, dark=6.0):
    """Blend each frame's inverse depth toward its per-pixel temporal
    median by the fade amount: disparity stops swimming as the picture
    fades out. Frames above half brightness are byte-identical."""
    a = fade_amounts(luma_seq, dark)
    if not a.any():
        return [f.copy() for f in inv_seq]
    med = np.median(np.stack(inv_seq), axis=0)
    return [np.where(a[i] > 0, (1 - a[i]) * inv_seq[i] + a[i] * med,
                     inv_seq[i].copy())
            for i in range(len(inv_seq))]


# ---------- 3. burned-in overlays ----------

def static_overlay_mask(frames_rgb, scene_motion_thresh=4.0,
                        static_thresh=2.0, min_frac=0.001, max_frac=0.35):
    """Pixels static in screen space while the scene moves: per-pixel
    temporal luma std below static_thresh, in shots whose mean frame-to-
    frame change exceeds scene_motion_thresh. Excludes near-black bars
    only when they're attached to the frame edge (letterbox) - they get
    flattened too. Returns [H,W] bool."""
    lum = np.stack([f.astype(np.float32).mean(-1) for f in frames_rgb])
    motion = float(np.mean(np.abs(np.diff(lum, axis=0))))
    if motion < scene_motion_thresh:
        return np.zeros(lum.shape[1:], bool)
    pstd = lum.std(axis=0)
    m = pstd < static_thresh
    frac = float(m.mean())
    if frac < min_frac or frac > max_frac:
        return np.zeros(lum.shape[1:], bool)
    return m


def static_overlay_flatten(z_seq, frames_rgb, z_screen):
    """Set burned-in overlay pixels to the screen (convergence) depth so
    subtitles/logos sit ON the screen instead of at a scene depth that
    conflicts with their zero motion. Returns (z_out list, mask at z
    resolution)."""
    m = static_overlay_mask(frames_rgb)
    h, w = z_seq[0].shape
    if m.shape != (h, w):
        import cv2
        m = cv2.resize(m.astype(np.uint8), (w, h),
                       interpolation=cv2.INTER_NEAREST).astype(bool)
    if not m.any() or z_screen is None:
        return [z.copy() for z in z_seq], m
    return [np.where(m, z_screen, z) for z in z_seq], m


# ---------- 4. confidence-weighted align fit ----------

def fit_scale_shift_weighted(target, reference, mask=None, weights=None):
    """Weighted least-squares scale/shift (disparity space). Same contract
    as align.fit_scale_shift; weights=None degenerates to it exactly."""
    t = target.astype(np.float64).ravel()
    r = reference.astype(np.float64).ravel()
    if mask is not None:
        m = mask.ravel()
        t, r = t[m], r[m]
        if weights is not None:
            w = weights.ravel()[m]
    elif weights is not None:
        w = weights.ravel()
    if weights is None:
        A = np.stack([t, np.ones_like(t)], axis=1)
        (scale, shift), *_ = np.linalg.lstsq(A, r, rcond=None)
        return float(scale), float(shift)
    sw = np.sqrt(np.clip(w, 1e-6, None))
    A = np.stack([t * sw, sw], axis=1)
    (scale, shift), *_ = np.linalg.lstsq(A, r * sw, rcond=None)
    return float(scale), float(shift)


def texture_weights(luma, lo=1.0, hi=8.0):
    """Fit weights in (0,1] from local luma texture: flat sky/noise pixels
    get ~lo/hi weight, textured pixels 1. Whole-frame low texture (night /
    heavy noise: mean tex << hi) starves the weighted align fit - the few
    textured pixels are mostly sensor noise - so the weights blend toward
    uniform by the frame's mean texture (s45 quality bar: dark e2 clip
    jitter p95 0.0819 -> 0.0776, live/cg unchanged at a = 1)."""
    tex = local_std(luma)
    w = np.clip(tex / hi, lo / hi, 1.0)
    a = min(1.0, float(tex.mean()) / hi)
    return (1.0 + a * (w - 1.0)).astype(np.float32)
