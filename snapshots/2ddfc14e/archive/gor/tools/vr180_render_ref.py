#!/usr/bin/env python3
"""Pixel-level reference for the VR180 stereo eye render (190t G on the 2D3D cache contract, tools/depth_analysis/CACHE-FORMAT.md).
Input: RGB frame [H,W,3], aligned METRIC depth [H,W] (metres along the optical axis; align.py output), theta_h (radians, per-shot median fov_x).
Output per eye: equirect-180 image [OH,OW,3], coverage mask (True = a source pixel landed here). Geometry is exactly
tools/vr180_ortho_ref.py (frame_to_equirect); this module is the vectorised, z-buffered form the Metal kernel must match.
Hole fill here is the simplest tier (row fill from the far side); iw3 tiers replace only fill, never geometry."""
import math
import numpy as np

def eye_geometry(w, h, theta_h, depth, eye, ow, oh, roll_deg=0.0):
    """Vectorised frame_to_equirect for every source pixel. Returns (iu, iv, valid) integer output coords.
    roll_deg (191a C3): head roll; the signed scalar eye offset rotates to
    (eye*cos, eye*sin). roll 0 is bit-identical."""
    f = (w / 2.0) / math.tan(theta_h / 2.0)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    rx, ry = (xs + 0.5 - w / 2.0) / f, (h / 2.0 - (ys + 0.5)) / f
    z = np.asarray(depth, dtype=np.float64)
    phi = math.radians(roll_deg)
    ex, ey = eye * math.cos(phi), eye * math.sin(phi)
    px, py, pz = rx * z - ex, ry * z - ey, z
    n = np.sqrt(px * px + py * py + pz * pz)
    lon, lat = np.arctan2(px, pz), np.arcsin(py / n)
    u, v = lon / math.pi + 0.5, 0.5 - lat / math.pi
    iu, iv = np.floor(u * ow).astype(np.int64), np.floor(v * oh).astype(np.int64)
    return iu, iv, (iu >= 0) & (iu < ow) & (iv >= 0) & (iv < oh) & (z > 0)

def render_eye(frame, depth, theta_h, eye, ow, oh):
    h, w = depth.shape
    iu, iv, ok = eye_geometry(w, h, theta_h, depth, eye, ow, oh)
    img = np.zeros((oh, ow, 3), frame.dtype); zbuf = np.full((oh, ow), np.inf); cov = np.zeros((oh, ow), bool)
    order = np.argsort(-depth[ok], kind='stable')            # far first, near overwrites: z-buffer without atomics
    sel = np.flatnonzero(ok.ravel())[order]
    flat_iu, flat_iv = iu.ravel()[sel], iv.ravel()[sel]
    img[flat_iv, flat_iu] = frame.reshape(-1, 3)[sel]; zbuf[flat_iv, flat_iu] = depth.ravel()[sel]; cov[flat_iv, flat_iu] = True
    return img, cov, zbuf

SHORT_RUN_K = 16    # F1 (190v s27): interior runs of at most this many pixels
                    # are blended between the two endpoint colours
VERT_HALF = 16      # vertical-average half-window for longer runs (33 rows)


def _round_half_up(num, den):
    """round(num / den), ties up, exact integer arithmetic. The Metal
    kernel reproduces this bit-exactly in uint32 (all values < 2^23), so
    the float32 kernel and this float64 reference can never drift."""
    return (2 * np.asarray(num, dtype=np.uint64) + den) // (2 * den)


def _vavg(img, cov, r, c):
    """Mean colour of the COVERED pixels of column c in rows
    [r-VERT_HALF, r+VERT_HALF] (clipped), round-half-up per channel; the
    endpoint colour itself when no covered pixel exists in the window."""
    h = img.shape[0]
    lo, hi = max(0, r - VERT_HALF), min(h - 1, r + VERT_HALF)
    col = img[lo:hi + 1, c].astype(np.uint64); m = cov[lo:hi + 1, c]
    n = int(m.sum())
    if n == 0:
        return img[r, c]
    return _round_half_up(col[m].sum(axis=0), n).astype(np.uint8)


def fill_rows(img, cov, zbuf, eye):
    """Row fill of disocclusions, F1 (190v s27; replaces the s5
    constant-far fill that streaked long runs into vertical bands).
    A hole run a+1..b-1 between covered pixels a and b, g = b-a-1:
      g <= SHORT_RUN_K: linear blend between the endpoint colours,
        out[a+k] = round_half_up(A*(g+1-k) + B*k, g+1), k = 1..g
      g  > SHORT_RUN_K: the vertical average of the FAR endpoint column
        (_vavg at the endpoint with the larger zbuf; larger Z = farther
        = background), so a long disocclusion band becomes the smoothed
        far texture instead of a single-texel streak.
    All quantisation is the integer-exact round-half-up of _round_half_up.
    Only inside the film span; covered pixels are never overwritten.
    Returns (filled_img, filled_mask) with filled_mask = cov | new fills.
    eye is unused (kept for signature stability)."""
    out = img.copy(); filled = cov.copy(); oh, ow = cov.shape
    for r in range(oh):
        cols = np.flatnonzero(cov[r])
        if cols.size < 2: continue
        for a, b in zip(cols[:-1], cols[1:]):
            g = int(b - a - 1)
            if g <= 0: continue
            if g <= SHORT_RUN_K:
                A = img[r, a].astype(np.uint64); B = img[r, b].astype(np.uint64)
                ks = np.arange(1, g + 1, dtype=np.uint64)
                num = A[None, :] * (g + 1 - ks)[:, None] + B[None, :] * ks[:, None]
                out[r, a + 1:b] = _round_half_up(num, g + 1).astype(np.uint8)
            else:
                src = a if zbuf[r, a] >= zbuf[r, b] else b       # larger Z = farther = background
                out[r, a + 1:b] = _vavg(img, cov, r, src)
            filled[r, a + 1:b] = True
    return out, filled


def fill_edge_runs(img, cov, fp):
    """s3d_fill r2 (190v item 4) with the F1 long-run rule: disocclusion
    strips that run to the frustum boundary have no covered pixel on the
    outer side, so the pair pass leaves them black. Fill each row's
    leading/trailing run INSIDE the source frustum (fp) with the sole
    adjacent endpoint (the far side in canonical disocclusion geometry):
    constant endpoint colour for runs of at most SHORT_RUN_K pixels, the
    endpoint column's vertical average (_vavg) for longer runs."""
    out = img.copy(); oh, ow = cov.shape
    for r in range(oh):
        cols = np.flatnonzero(cov[r]); fpx = np.flatnonzero(fp[r])
        if cols.size == 0 or fpx.size == 0: continue
        lo, hi = int(fpx[0]), int(fpx[-1])
        if cols[0] > lo:
            g = int(cols[0] - lo)
            out[r, lo:cols[0]] = _vavg(img, cov, r, int(cols[0])) if g > SHORT_RUN_K else img[r, cols[0]]
        if cols[-1] < hi:
            g = int(hi - cols[-1])
            out[r, cols[-1] + 1:hi + 1] = _vavg(img, cov, r, int(cols[-1])) if g > SHORT_RUN_K else img[r, cols[-1]]
    return out


def fill_run_lengths(cov, filled):
    """Lengths (px) of every maximal horizontal run of newly filled
    pixels (filled & ~cov) across all rows. The F1 metric pair reports
    the p95 of this array on a staged depth step."""
    lens = []
    newly = filled & ~cov
    for r in range(newly.shape[0]):
        idx = np.flatnonzero(newly[r])
        if idx.size == 0: continue
        brk = np.flatnonzero(np.diff(idx) > 1)
        starts = np.concatenate(([idx[0]], idx[brk + 1]))
        ends = np.concatenate((idx[brk], [idx[-1]]))
        lens.extend((ends - starts + 1).tolist())
    return np.asarray(lens, dtype=np.int64)


def flat_fraction(img, mask):
    """Fraction of horizontally adjacent pixel pairs with both pixels in
    mask holding exactly equal RGB. A constant fill scores ~1; the F1
    short-run blend breaks it. 0 when no adjacent pair exists."""
    both = mask[:, :-1] & mask[:, 1:]
    n = int(both.sum())
    if n == 0: return 0.0
    eq = (img[:, :-1] == img[:, 1:]).all(axis=2)
    return float((eq & both).sum()) / n


def vstep_mean(img, mask):
    """Mean absolute vertical step (per-channel mean of |img[r]-img[r+1]|
    over vertically adjacent pairs both in mask), 0..255. The band
    metric: the s5 constant fill repaints every row with that row's own
    far texel (noisy), the F1 vertical average is smooth by
    construction. 0 when no adjacent pair exists."""
    both = mask[:-1, :] & mask[1:, :]
    n = int(both.sum())
    if n == 0: return 0.0
    d = np.abs(img[:-1].astype(np.int16) - img[1:].astype(np.int16)).mean(axis=2)
    return float(d[both].mean())


def surround_soft(frame, theta_h, conv, ow, oh, out):
    """Soft surround r4 (Stereo3DKernel s3d_surround, 190v item 4, s28):
    normalised pre-blur of the footprint content (32x 3x3, outside =
    missing), nearest-footprint extension (first filled 8-neighbour in
    fixed scan order), boundary-level correction ((true - preblur) at
    the nearest footprint pixel, fading over 24 px; restores thin
    edge-feature levels), then a distance-dependent multi-radius
    integral box blur (R=16 at the boundary growing to R=96 at 40 px)
    whose far trend is SIDE-LOCAL (rectangular windows, radial
    half-width 64) rather than the r3 global-average square. Blur
    windows read true film content inside the footprint. Deterministic
    float64, single uint8 truncation. `out` modified in place and
    returned."""
    import numpy as _np
    h, w = frame.shape[:2]; f = (w / 2.0) / math.tan(theta_h / 2.0)
    inside = _np.zeros((oh, ow), bool)
    for oy in range(oh):
        for ox in range(ow):
            lon = ((ox + 0.5) / ow - 0.5) * math.pi - conv; lat = (0.5 - (oy + 0.5) / oh) * math.pi
            dx, dy, dz = math.sin(lon) * math.cos(lat), math.sin(lat), math.cos(lon) * math.cos(lat)
            dzc = max(dz, 1e-4); sx = f * dx / dzc + w * 0.5; sy = h * 0.5 - f * dy / dzc
            inside[oy, ox] = dz > 0 and 0 <= sx < w and 0 <= sy < h
    if inside.all(): return out
    work = out.astype(_np.float64)
    # pre-blur (normalised, footprint only)
    srcb = work.copy()
    for _ in range(32):
        acc = _np.where(inside[..., None], srcb, 0.0); cnt = inside.astype(_np.float64)
        for j in range(-1, 2):
            for i in range(-1, 2):
                if j == 0 and i == 0: continue
                acc += _np.where(inside[..., None], _np.roll(_np.roll(srcb, -j, 0), -i, 1), 0.0)
                cnt += _np.roll(_np.roll(inside.astype(_np.float64), -j, 0), -i, 1)
        srcb = _np.where(inside[..., None], acc / _np.maximum(cnt, 1)[..., None], 0.0)
    work = _np.where(inside[..., None], srcb, 0.0)
    # nearest-footprint extension: each outside pixel copies the value
    # of its first filled 8-neighbour in a FIXED scan order (radial
    # Voronoi fill - no directional streak replication)
    filled = inside.copy()
    while True:
        todo = ~filled
        if not todo.any(): break
        progressed = False
        for j in range(-1, 2):
            for i in range(-1, 2):
                if j == 0 and i == 0: continue
                nb = _np.zeros((oh, ow), bool)
                ys = slice(max(0, j), oh + min(0, j)); xs = slice(max(0, i), ow + min(0, i))
                yd = slice(max(0, -j), oh + min(0, -j)); xd = slice(max(0, -i), ow + min(0, -i))
                nb[yd, xd] = filled[ys, xs]
                take = todo & nb & ~filled
                if not take.any(): continue
                vals = _np.roll(_np.roll(work, -j, 0), -i, 1)
                work[take] = vals[take]; filled |= take; progressed = True
        if not progressed: break
    # r4 (s28): boundary-level correction + side-local far trend.
    # Nearest-inside index + L1 distance via slice-shift BFS (mirrors
    # reference_render._surround_soft_vec exactly; Metal: jump-flood or
    # the same BFS in tiles).
    dist = _np.full((oh, ow), 1e9)
    iy = _np.zeros((oh, ow), _np.int64); ix = _np.zeros((oh, ow), _np.int64)
    dist[inside] = 0.0
    yy = _np.arange(oh)[:, None].repeat(ow, 1); xx = _np.arange(ow)[None, :].repeat(oh, 0)
    iy[inside] = yy[inside]; ix[inside] = xx[inside]
    for _ in range(121):
        changed = False
        for j, i in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ys = slice(max(0, j), oh + min(0, j)); xs = slice(max(0, i), ow + min(0, i))
            yd = slice(max(0, -j), oh + min(0, -j)); xd = slice(max(0, -i), ow + min(0, -i))
            rd = dist[ys, xs] + 1.0; dst = dist[yd, xd]
            take = rd < dst
            if not take.any(): continue
            dst[take] = rd[take]
            iy[yd, xd][take] = iy[ys, xs][take]
            ix[yd, xd][take] = ix[ys, xs][take]
            changed = True
        if not changed: break
    # add back (true - preblur32) colour of the nearest footprint pixel,
    # fading over 24 px; restores thin edge-feature levels (live top
    # glow band) without hard Voronoi colour zones
    delta = (out.astype(_np.float64) - srcb)[iy, ix]
    wcorr = _np.clip(1.0 - dist / 24.0, 0.0, 1.0)[..., None]
    work = work + _np.where(inside[..., None], 0.0, delta * wcorr)
    # blur windows read TRUE film content inside the footprint (the
    # windows' interior samples only affect surround output pixels)
    work = _np.where(inside[..., None], out.astype(_np.float64), work)
    # r3/r4: distance-dependent multi-radius box blur, one integral image
    R1, R2, R3 = 16, 96, 256
    D2, D3 = 40.0, 120.0
    ii = _np.pad(work, ((R3 + 1, R3 + 1), (R3 + 1, R3 + 1), (0, 0)), mode='edge')
    cs = ii.cumsum(0).cumsum(1)
    y0 = _np.arange(oh)[:, None]; x0 = _np.arange(ow)[None, :]
    def _boxrect(rx, ry):
        ya, yb = y0 + (R3 - ry), y0 + (R3 - ry) + 2 * ry + 1
        xa, xb = x0 + (R3 - rx), x0 + (R3 - rx) + 2 * rx + 1
        return (cs[ya, xa] + cs[yb, xb] - cs[ya, xb] - cs[yb, xa]) / float((2 * rx + 1) * (2 * ry + 1))
    b1, b2 = _boxrect(R1, R1), _boxrect(R2, R2)
    # r4: side-local far trend (wide-short above/below, tall-narrow
    # left/right) instead of the R=256 square (~global average)
    RT = 64
    bw = _boxrect(R3, RT); bt = _boxrect(RT, R3)
    cyy, cxx = _np.where(inside)
    cy, cx = float(cyy.mean()), float(cxx.mean())
    vert = _np.abs(y0 - cy) >= _np.abs(x0 - cx)
    b3 = _np.where(vert[..., None], bw, bt)
    t1 = _np.clip((dist - 1.0) / (D2 - 1.0), 0.0, 1.0)[..., None]
    t2 = _np.clip((dist - D2) / (D3 - D2), 0.0, 1.0)[..., None]
    outv = b1 + (b2 - b1) * t1
    outv = outv + (b3 - outv) * t2
    out[~inside] = outv[~inside].astype(_np.uint8)
    return out
