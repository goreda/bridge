"""Depth box -> source-size upsample operators (contract s24).

The native prepare stores depth at the letterbox box (e.g. 266x150 for a
640x360 source); the renderer needs depth at the source picture size.

Canonical operator (delivery lane ca3e50cb / DepthUpsample.swift):
inverse-plane bilinear, half-pixel centres, edge clamp
(cv2.INTER_LINEAR / torch align_corners=False semantics), invalid tap
(Z <= 0) counts as v = 0 (far), back-conversion v <= 0 -> Z = 0.
`upsample` is the numpy reference; `upsample_cv2` cross-checks it
against cv2.INTER_LINEAR on the inverse plane.

Candidates judged in s24: z_bilinear, inverse_bicubic, guided (joint
bilateral upsample with the full-res source luma as guide).
"""
import cv2
import numpy as np

FAR = 0.0


def inv_of(z):
    return np.where(z > 0, 256.0 / np.maximum(z, 1e-30), 0.0)


def z_of(v):
    return np.where(v > 0, 256.0 / np.maximum(v, 1e-30), 0.0)


def compatible(dw, dh, sw, sh):
    """DepthUpsampleKernel.compatible: same aspect within 2%, never
    larger than the source."""
    if min(dw, dh, sw, sh) <= 0 or dw > sw or dh > sh:
        return False
    return abs(dw / dh - sw / sh) / (sw / sh) <= 0.02


def _axis(n_in, n_out):
    f = (np.arange(n_out) + 0.5) * n_in / n_out - 0.5
    i0 = np.floor(f).astype(np.int64)
    return (np.clip(i0, 0, n_in - 1), np.clip(i0 + 1, 0, n_in - 1),
            f - i0)


def upsample(z, ow, oh):
    """Canonical: inverse-plane bilinear (numpy reference of the Metal
    kernel; float64 accumulation)."""
    v = inv_of(z)
    ih, iw = v.shape
    x0, x1, ax = _axis(iw, ow)
    y0, y1, ay = _axis(ih, oh)
    r0 = v[y0][:, x0] * (1 - ax) + v[y0][:, x1] * ax
    r1 = v[y1][:, x0] * (1 - ax) + v[y1][:, x1] * ax
    vv = r0 * (1 - ay)[:, None] + r1 * ay[:, None]
    return z_of(vv)


def upsample_cv2(z, ow, oh, interpolation=cv2.INTER_LINEAR):
    """cv2 on the inverse plane (INTER_LINEAR = half-pixel bilinear;
    INTER_CUBIC = the bicubic candidate)."""
    vv = cv2.resize(inv_of(z).astype(np.float32), (ow, oh),
                    interpolation=interpolation).astype(np.float64)
    return z_of(vv)


def upsample_z_bilinear(z, ow, oh):
    """Candidate: bilinear on Z directly (perspective-wrong at edges)."""
    ih, iw = z.shape
    x0, x1, ax = _axis(iw, ow)
    y0, y1, ay = _axis(ih, oh)
    r0 = z[y0][:, x0] * (1 - ax) + z[y0][:, x1] * ax
    r1 = z[y1][:, x0] * (1 - ax) + z[y1][:, x1] * ax
    return r0 * (1 - ay)[:, None] + r1 * ay[:, None]


def upsample_guided(z, ow, oh, guide_luma, radius=2, sigma_r=12.0):
    """Candidate: joint bilateral upsample on the inverse plane; the
    full-res source luma guides the range kernel. Taps come from the
    (2*radius+1)^2 nearest box pixels around the mapped position;
    weights = bilinear spatial weight x exp(-dg^2 / 2 sigma_r^2) with
    dg = guide at the output pixel - guide at the tap centre.
    Normalised; all-zero weight falls back to the canonical bilinear."""
    v = inv_of(z)
    ih, iw = v.shape
    g = guide_luma.astype(np.float64)
    base = upsample(z, ow, oh)
    gy = np.linspace(0, g.shape[0] - 1, oh).round().astype(np.int64)
    gx = np.linspace(0, g.shape[1] - 1, ow).round().astype(np.int64)
    go = g[np.ix_(gy, gx)]
    fx = (np.arange(ow) + 0.5) * iw / ow - 0.5
    fy = (np.arange(oh) + 0.5) * ih / oh - 0.5
    acc = np.zeros((oh, ow)); wsum = np.zeros((oh, ow))
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            tx = np.clip(np.floor(fx).astype(np.int64) + dx, 0, iw - 1)
            ty = np.clip(np.floor(fy).astype(np.int64) + dy, 0, ih - 1)
            ws = np.maximum(0.0, 1.0 - np.abs(fx - tx)[None, :]) * \
                np.maximum(0.0, 1.0 - np.abs(fy - ty))[:, None]
            # tap centre mapped to output-pixel coordinates
            cx = np.clip(((tx + 0.5) * ow / iw - 0.5).round()
                         .astype(np.int64), 0, ow - 1)
            cy = np.clip(((ty + 0.5) * oh / ih - 0.5).round()
                         .astype(np.int64), 0, oh - 1)
            dg = go - go[cy][:, cx]
            w = ws * np.exp(-(dg * dg) / (2 * sigma_r * sigma_r))
            acc += v[ty][:, tx] * w
            wsum += w
    vv = np.where(wsum > 1e-12, acc / np.maximum(wsum, 1e-12), inv_of(base))
    return z_of(vv)


def downsample_to_box(z, bw, bh):
    """Inverse-plane area downsample: emulates the box-grid depth the
    letterboxed stream produces (for goldens and the s24 comparison)."""
    vv = cv2.resize(inv_of(z).astype(np.float32), (bw, bh),
                    interpolation=cv2.INTER_AREA).astype(np.float64)
    return z_of(vv)
