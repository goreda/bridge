"""iw3 golden harness (190t): DIBR stereo synthesis + pixel-loss coverage check.

Ported from the E2 pipeline (sbs_live.mp4: 60s, coverage mean 99.977% / min
99.704% over 1440 frames). This is the reference implementation for judging
any other SBS path: same warp, same hole fill, same coverage metric.

Algorithm per frame:
  depth -> normalize by EMA-smoothed per-shot range (reset at cuts)
        -> edge-aware upsample (guided filter on the RGB)
        -> per-eye horizontal shift (z-buffer ordered warp, far-to-near)
        -> background-side hole fill (iterative neighbor pull, lower depth)
        -> inpaint fallback for any residual holes
Coverage: fraction of source pixels recovered in either eye (tol 12/255).
"""
import cv2
import numpy as np

TOL = 12


class DepthNormalizer:
    """EMA-smoothed [lo,hi] depth range within a shot; reset at cuts."""

    def __init__(self, alpha=0.15):
        self.alpha = alpha
        self.reset()

    def reset(self):
        self.lo = None
        self.hi = None

    def normalize(self, depth):
        lo, hi = float(depth.min()), float(depth.max())
        if self.lo is None:
            self.lo, self.hi = lo, hi
        else:
            self.lo = (1 - self.alpha) * self.lo + self.alpha * lo
            self.hi = (1 - self.alpha) * self.hi + self.alpha * hi
        return np.clip((depth - self.lo) / max(self.hi - self.lo, 1e-6), 0, 1)


def warp_eye(src, depth_up, disp, eye, max_disp):
    """Z-buffer ordered warp (far first so near wins) + hole fill.

    src: [H,W,3] uint8; depth_up: [H,W] float in [0,1] (1=near);
    disp: [H,W] signed per-pixel disparity; eye 0=left, 1=right.
    """
    h, w = src.shape[:2]
    xs = np.arange(w, dtype=np.float32)[None, :].repeat(h, 0)
    sign = -1.0 if eye == 0 else 1.0
    tx = np.rint(xs + sign * disp * 0.5).astype(np.int32)
    valid = (tx >= 0) & (tx < w)
    txc = np.clip(tx, 0, w - 1)
    order = np.argsort(depth_up, axis=None)  # far first
    flat_img = np.zeros((h * w, 3), dtype=np.uint8)
    flat_dep = np.zeros(h * w, dtype=np.float32)
    written = np.zeros(h * w, dtype=bool)
    srcf = src.reshape(-1, 3)
    depf = depth_up.ravel()
    tgt = (np.arange(h)[:, None] * w + txc).ravel()
    vf = valid.ravel()
    o = order[vf[order]]
    flat_img[tgt[o]] = srcf[o]
    flat_dep[tgt[o]] = depf[o]
    written[tgt[o]] = True
    img = flat_img.reshape(h, w, 3)
    dep = flat_dep.reshape(h, w)
    holes = ~written.reshape(h, w)
    for _ in range(int(max_disp) // 2 + 4):
        if not holes.any():
            break
        left_img = np.roll(img, 1, axis=1); left_dep = np.roll(dep, 1, axis=1)
        right_img = np.roll(img, -1, axis=1); right_dep = np.roll(dep, -1, axis=1)
        can_l = holes & ~np.roll(holes, 1, axis=1)
        can_r = holes & ~np.roll(holes, -1, axis=1)
        take_l = can_l & (~can_r | (left_dep <= right_dep))  # background side wins
        take_r = can_r & ~take_l
        img = np.where(take_l[..., None], left_img, img)
        img = np.where(take_r[..., None], right_img, img)
        dep = np.where(take_l, left_dep, dep)
        dep = np.where(take_r, right_dep, dep)
        holes = holes & ~take_l & ~take_r
    if holes.any():
        img = cv2.inpaint(img, holes.astype(np.uint8) * 255, 3, cv2.INPAINT_NS)
    return img


def sbs_frame(rgb, depth, normalizer, max_disp=None, is_cut=False):
    """One frame -> (sbs uint8 [H,2W,3], coverage fraction).

    rgb [H,W,3] uint8; depth [h,w] float (any range; normalized internally).
    """
    h, w = rgb.shape[:2]
    max_disp = max_disp or w / 40.0  # 2.5% of width
    if is_cut:
        normalizer.reset()
    d_norm = normalizer.normalize(depth)
    up = cv2.resize(d_norm, (w, h), interpolation=cv2.INTER_LINEAR)
    up = cv2.ximgproc.guidedFilter(rgb, up.astype(np.float32), 8, 1e-4)
    up = np.clip(up, 0, 1)
    disp = max_disp * (up - 0.5)
    left = warp_eye(rgb, up, disp, 0, max_disp)
    right = warp_eye(rgb, up, disp, 1, max_disp)
    sbs = np.concatenate([left, right], axis=1)
    cov = coverage(rgb, left, right, disp)
    return sbs, cov


def coverage(rgb, left, right, disp):
    """Fraction of source pixels visible (within TOL) in at least one eye."""
    h, w = rgb.shape[:2]
    xs = np.arange(w, dtype=np.float32)[None, :].repeat(h, 0)
    txl = np.clip(np.rint(xs - disp * 0.5).astype(np.int32), 0, w - 1)
    txr = np.clip(np.rint(xs + disp * 0.5).astype(np.int32), 0, w - 1)
    rows = np.arange(h)[:, None]
    ml = (np.abs(left[rows, txl].astype(np.int16) - rgb.astype(np.int16)).max(2) <= TOL)
    mr = (np.abs(right[rows, txr].astype(np.int16) - rgb.astype(np.int16)).max(2) <= TOL)
    return float((ml | mr).mean())
