"""Per-shot scale/shift alignment between VDA-S relative depth and MoGe-2
metric depth (190t analysis lane C).

VDA-S output is relative (disparity-like, unknown affine); MoGe-2 gives
metric depth + intrinsics. Alignment maps VDA values into MoGe's metric frame
per shot: vda_aligned = vda * scale + shift, fitted by least squares per frame
and EMA-smoothed within a shot. State resets at shot cuts (shots are inputs).

Pure numpy; no model code here.
"""
import numpy as np


def fit_scale_shift(target, reference, mask=None):
    """Least-squares scale/shift mapping target -> reference (disparity space).

    Solves min ||scale * target + shift - reference||^2. Returns (scale, shift).
    """
    t = target.astype(np.float64).ravel()
    r = reference.astype(np.float64).ravel()
    if mask is not None:
        m = mask.ravel()
        t, r = t[m], r[m]
    A = np.stack([t, np.ones_like(t)], axis=1)
    (scale, shift), *_ = np.linalg.lstsq(A, r, rcond=None)
    return float(scale), float(shift)


class ShotAligner:
    """EMA-tracked (scale, shift) within one shot; reset() at every cut."""

    def __init__(self, ema=0.9):
        self.ema = ema
        self.reset()

    def reset(self):
        self.scale = None
        self.shift = None
        self.skipped = 0

    def update(self, vda_frame, moge_frame, mask=None, weights=None):
        """Fit this frame, smooth into the running estimate, return aligned.

        Non-finite inputs are excluded from the fit (MoGe-2 emits +inf
        metric depth at sky; one unmasked inf poisons the running EMA and
        blacked out whole shots - 190v anim regression). A frame whose fit
        is still non-finite (too few valid pairs) is skipped, keeping the
        previous estimate. weights (same shape as the frames, (0,1]) make
        the fit weighted least squares via
        depth_guards.fit_scale_shift_weighted - the EMA MUST see the same
        weights as the residual fit or guarded renders diverge from the
        Swift port (E-G a1cb3fb5)."""
        finite = np.isfinite(vda_frame) & np.isfinite(moge_frame)
        if mask is not None:
            finite &= mask
        if finite.sum() >= 16:
            if weights is not None:
                from depth_guards import fit_scale_shift_weighted
                s, b = fit_scale_shift_weighted(vda_frame, moge_frame,
                                                finite, weights)
            else:
                s, b = fit_scale_shift(vda_frame, moge_frame, finite)
            if np.isfinite(s) and np.isfinite(b):
                if self.scale is None:
                    self.scale, self.shift = s, b
                else:
                    self.scale = self.ema * self.scale + (1 - self.ema) * s
                    self.shift = self.ema * self.shift + (1 - self.ema) * b
                return vda_frame * self.scale + self.shift
        self.skipped += 1
        scale = self.scale if self.scale is not None else 1.0
        shift = self.shift if self.shift is not None else 0.0
        return vda_frame * scale + shift


def align_shot(vda_seq, moge_seq, ema=0.9):
    """Align a whole shot (two [T,H,W] sequences). Returns aligned [T,H,W]."""
    assert vda_seq.shape == moge_seq.shape
    al = ShotAligner(ema=ema)
    out = [al.update(v, m) for v, m in zip(vda_seq, moge_seq)]
    return np.stack(out)


def apply_align_track(vda_seq, kf_track, default=(1.0, 0.0)):
    """Causal eased application of per-keyframe EMA (scale, shift) (s30).

    Re-aligning VDA to MoGe per keyframe and SWITCHING at the keyframe
    pops rendered disparity past the comfort band on real content (p95
    2.64 deg live / 1.73 deg CG at the 75 deg screen; budgets 2 deg
    crossed / 1 deg divergence). Instead the per-keyframe EMA value is
    eased in linearly over the frames AFTER its keyframe: frame f in
    [k_i, k_{i+1}) lerps from k_(i-1)'s EMA to k_i's EMA (hold at the
    first keyframe and after the last). Continuous (no boundary step),
    causal (no future keyframes), and deterministic given the shot's
    keyframe fits - a mid-shot seek reconstructs the same params from
    the stored track alone. Tracks are per shot; cuts reset the EMA.

    vda_seq [T,H,W]; kf_track [(k, scale, shift)] in EMA order (None
    scale/shift -> default). Returns z [T,H,W] float64 (metres).
    """
    T = vda_seq.shape[0]
    out = np.empty(vda_seq.shape, dtype=np.float64)
    track = [(int(k), s if s is not None else default[0],
              b if b is not None else default[1]) for k, s, b in kf_track]
    if not track:
        return vda_seq.astype(np.float64) * default[0] + default[1]
    for i, (k0, s0, b0) in enumerate(track):
        k1 = track[i + 1][0] if i + 1 < len(track) else T
        hi = min(k1, T)
        if k0 >= T:
            break
        seg = vda_seq[k0:hi].astype(np.float64)
        if i == 0:
            t = np.zeros(hi - k0)
            sp, bp = s0, b0
        else:
            kp, sp, bp = track[i - 1]
            t = np.minimum(1.0, (np.arange(k0, hi) - k0) / float(k0 - kp))
        out[k0:hi] = seg * (sp + (s0 - sp) * t)[:, None, None] \
                     + (bp + (b0 - bp) * t)[:, None, None]
    return out
