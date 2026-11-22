"""Python reference render: one prepared shot -> SBS, op-for-op with the
Metal Stereo3DKernel (Sources/gor/gor/ThreeD.swift Stereo3DKernel.swift section) and its Params
derivation (Stereo3DRenderer.render). The Swift renderer is parity-checked
on the Mac against the golden hashes this module produces.

Pipeline per frame:
  depth mp4 (10-bit luma) -> v = w10/1023*1024 -> Z = 256/v metres (w10==0
  -> masked, skipped) -> per-eye forward warp with z-buffer (far first,
  near overwrites) -> far-side row hole fill -> pack left|right.

Stereo math (from Stereo3DRenderer.render):
  f    = (W/2) / tan(thetaH/2)           thetaH = shot median hfov, radians
  eye  = sign * ipd/2                    sign order: swapEyes ? [+1,-1] : [-1,+1]
  conv = atan2(sign*ipd/2, convergence)  when convergence_m > 0, else 0
  LEFT half of the SBS carries the FIRST sign in that order.
  s3d_map per source pixel (x,y), depth z:
    rx = (x+0.5 - W/2)/f; ry = (H/2 - (y+0.5))/f
    px = rx*z - eye; py = ry*z; pz = z
    lon = atan2(px,pz) + conv; lat = asin(py/|p|)
    out = (floor((lon/pi+0.5)*OW), floor((0.5-lat/pi)*OH))
  valid iff z > 0 and in bounds. Z-buffer: nearest wins. Fill: per output
  row, gaps between two covered pixels take the FAR endpoint's colour;
  leading/trailing runs stay black.

Surround (s3d_surround, E-G ef1581d2): canvas pixels OUTSIDE the film
footprint (direction with conv removed and eye offset ignored does not
land inside the source frustum) are filled from the source: 5x5 mean at
the edge-clamped projected position, tap step max(1, max(W,H)/64) px.
Inside-footprint pixels are never touched. surround="soft" (default)
applies this; "off" leaves them black.
"""
import hashlib
import json
import math
import os
import subprocess

import numpy as np


def _read_source_frames(mp4, w, h, max_frames=None):
    # s34: pin the YCbCr->RGB matrix explicitly. The proxy passes the
    # source's tags through, so tagged proxies decode with their own matrix
    # (in_color_matrix=auto); untagged proxies get the size rule
    # (colorprobe.matrix_for) - bt470bg for SD, identical to swscale's
    # default, so existing goldens do not drift, and bt709 for HD where the
    # default would have been wrong (AVFoundation/mpv assume 709 there).
    import colorprobe
    p = colorprobe.probe(mp4)
    cmd = ["ffmpeg", "-v", "error", "-i", mp4,
           "-vf", colorprobe.rgb_decode_scale(p)]
    if max_frames is not None:
        cmd += ["-frames:v", str(max_frames)]
    out = subprocess.run(cmd + ["-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True)
    a = np.frombuffer(out.stdout, dtype=np.uint8)
    n = a.size // (w * h * 3)
    return a[:n * w * h * 3].reshape(n, h, w, 3)


# Virtual screen (CONTRACT-190v s4, RenderPrefsValue.thetaH in
# Sources/gor/gor/ThreeD.swift RenderPrefsReader.swift section): the film's angular width on the
# VR180 canvas comes from prefs.screen_deg, not the shot FoV. 0 = legacy
# shot FoV. Aspect-preserving (same f for x and y), vertical capped so the
# screen stays inside the canvas. Depth is NOT rescaled; depth_scale
# multiplies disparity via the eye offset (effectiveIPD = ipd_m *
# depth_scale).
DEFAULT_SCREEN_DEG = 75.0
MIN_SCREEN_DEG, MAX_SCREEN_DEG, MAX_VERTICAL_DEG = 20.0, 150.0, 150.0


def theta_h_for(screen_deg, shot_theta_h, aspect):
    """Port of RenderPrefsValue.thetaH(shotThetaH:aspect:). Angles in
    radians; screen_deg in degrees."""
    if screen_deg <= 0 or not aspect > 0:
        return shot_theta_h
    h = math.radians(min(max(screen_deg, MIN_SCREEN_DEG), MAX_SCREEN_DEG))
    h_cap = 2.0 * math.atan(math.tan(math.radians(MAX_VERTICAL_DEG) / 2.0)
                            * aspect)
    return min(h, h_cap)


def footprint_mask(rgb, theta_h, conv, out_w, out_h, conv_lat=0.0):
    """Canvas pixels whose inverse-mapped direction lands inside the
    source frustum (the film footprint). Same geometry as the old
    surround's outside test. conv_lat (191a C3): latitudinal convergence
    shift from head roll, 0 for an unrolled head."""
    h, w = rgb.shape[:2]
    f = (w / 2.0) / math.tan(theta_h / 2.0)
    oy, ox = np.mgrid[0:out_h, 0:out_w].astype(np.float64)
    lon = ((ox + 0.5) / out_w - 0.5) * math.pi - conv
    lat = (0.5 - (oy + 0.5) / out_h) * math.pi - conv_lat
    dx = np.sin(lon) * np.cos(lat)
    dy = np.sin(lat)
    dz = np.cos(lon) * np.cos(lat)
    dzc = np.maximum(dz, 1e-4)
    sx = f * dx / dzc + w * 0.5
    sy = h * 0.5 - f * dy / dzc
    return (dz > 0) & (sx >= 0) & (sx < w) & (sy >= 0) & (sy < h)


def _surround_soft_vec(rgb, theta_h, conv, out_w, out_h, img, conv_lat=0.0):
    """Soft surround (s3d_surround r2): diffusion fill of the canvas
    outside the film footprint. The old clamped 5x5-tap mean replicated
    the boundary row/column into the surround, producing vertical streak
    bands at the poles and cone smears at depth edges (Main 08:17 item
    4). Now: repeatedly set each unfilled outside pixel to the mean of
    its already-filled 3x3 neighbours (footprint pixels first, then
    freshly filled surround), which extends edge colour radially and
    smoothly. Deterministic: mean over neighbours in fixed scan order,
    uint8 truncation after each full pass."""
    inside = footprint_mask(rgb, theta_h, conv, out_w, out_h, conv_lat=conv_lat)
    if inside.all():
        return img
    filled = inside.copy()
    work = img.astype(np.float64)
    # 0) pre-blur the footprint content as the extension SOURCE, so the
    #    surround extends local colour, not source texture (high-frequency
    #    source detail carried outward was the residual radial streak).
    #    Normalised box: outside pixels count as missing, so no black
    #    bleed into the edge. The film pixels in img are never touched.
    srcb = work.copy()
    for _ in range(32):
        acc = np.where(inside[..., None], srcb, 0.0)
        cnt = inside.astype(np.float64)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                acc += np.where(inside[..., None],
                                np.roll(np.roll(srcb, -dy, 0), -dx, 1), 0.0)
                cnt += np.roll(np.roll(inside.astype(np.float64),
                                       -dy, 0), -dx, 1)
        srcb = np.where(inside[..., None], acc / np.maximum(cnt, 1)[..., None],
                        0.0)
    work = np.where(inside[..., None], srcb, 0.0)  # extension source
    # 1) nearest-footprint extension: each outside pixel copies the value
    #    of its first filled 8-neighbour in a FIXED scan order (radial
    #    Voronoi fill - no directional streak replication)
    while True:
        todo = ~filled
        if not todo.any():
            break
        progressed = False
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                nb = np.zeros((out_h, out_w), bool)
                ys = slice(max(0, dy), out_h + min(0, dy))
                xs = slice(max(0, dx), out_w + min(0, dx))
                yd = slice(max(0, -dy), out_h + min(0, -dy))
                xd = slice(max(0, -dx), out_w + min(0, -dx))
                nb[yd, xd] = filled[ys, xs]
                take = todo & nb & ~filled
                if not take.any():
                    continue
                vals = np.roll(np.roll(work, -dy, 0), -dx, 1)
                work[take] = vals[take]
                filled |= take
                progressed = True
        if not progressed:
            break  # disconnected hole: leave as-is
    # 1b) r4 (s28): boundary-level correction. The 32-pass pre-blur
    # attenuates THIN bright/dark edge features (a light band at the
    # film edge), and the extension then carried the attenuated colour
    # outward: the 1-8 px surround ring sat ~23 LSB off the true
    # boundary on the live shot's bright top band (ideal nearest-
    # boundary extension: 15 LSB - the glow is angularly thin). Add
    # back, per outside pixel, (true - blurred) colour of its NEAREST
    # footprint pixel: restores the boundary level while keeping r3's
    # smooth spatial blending (a sharp-source Voronoi instead splits
    # the ring into hard colour zones whose mean misses the strip -
    # measured 16.8 LSB on the CG sides). Fades over 24 px so the far
    # field is untouched. Film pixels in img are never touched.
    # Nearest-inside index + L1 distance via roll-based BFS (same
    # algorithm in tools/vr180_render_ref.surround_soft for the Metal
    # port - scipy edt would pick Euclidean-different pixels).
    dist = np.full((out_h, out_w), 1e9)
    iy = np.zeros((out_h, out_w), np.int64)
    ix = np.zeros((out_h, out_w), np.int64)
    dist[inside] = 0.0
    yy = np.arange(out_h)[:, None].repeat(out_w, 1)
    xx = np.arange(out_w)[None, :].repeat(out_h, 0)
    iy[inside] = yy[inside]
    ix[inside] = xx[inside]
    for _ in range(int(121)):
        changed = False
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ys = slice(max(0, dy), out_h + min(0, dy))
            xs = slice(max(0, dx), out_w + min(0, dx))
            yd = slice(max(0, -dy), out_h + min(0, -dy))
            xd = slice(max(0, -dx), out_w + min(0, -dx))
            rd = dist[ys, xs] + 1.0
            dst = dist[yd, xd]
            take = rd < dst
            if not take.any():
                continue
            dst[take] = rd[take]
            iy[yd, xd][take] = iy[ys, xs][take]
            ix[yd, xd][take] = ix[ys, xs][take]
            changed = True
        if not changed:
            break
    _delta = (img.astype(np.float64) - srcb)[iy, ix]
    _wcorr = np.clip(1.0 - dist / 24.0, 0.0, 1.0)[..., None]
    work = work + np.where(inside[..., None], 0.0, _delta * _wcorr)
    # After the extension, work's INSIDE values only feed the blur
    # windows below (output writes only ~inside pixels). Restore them
    # to the TRUE film content so the near ring's window mixes true
    # interior with the corrected extension - same populations the
    # strip/ring halo comparison measures.
    work = np.where(inside[..., None], img.astype(np.float64), work)
    # 2) distance-dependent multi-radius box blur of the extension via
    #    ONE integral image (r3): near the boundary a small box (R=6)
    #    keeps local colour, and the window grows with distance (R=24 at
    #    13 px, R=64 at 41 px) so far surround trends to the global
    #    average. r2 blended the raw Voronoi extension to a fixed R=24
    #    box over 16 px; the extension keeps the boundary row/column's
    #    colour constant along its run direction, which read as
    #    horizontal smear bands beside the footprint (Main 08:31). One
    #    pad covers the largest radius; smaller boxes read interior
    #    windows of the same cumsum. Deterministic float64; single uint8
    #    truncation at the end.
    R1, R2, R3 = 16, 96, 256
    D2, D3 = 40.0, 120.0  # R1->R2 blend over d 1..40, R2->R3 over d 40..120
    ii = np.pad(work, ((R3 + 1, R3 + 1), (R3 + 1, R3 + 1), (0, 0)), mode='edge')
    cs = ii.cumsum(0).cumsum(1)
    y0 = np.arange(out_h)[:, None]; x0 = np.arange(out_w)[None, :]
    def _boxrect(rx, ry):
        ya, yb = y0 + (R3 - ry), y0 + (R3 - ry) + 2 * ry + 1
        xa, xb = x0 + (R3 - rx), x0 + (R3 - rx) + 2 * rx + 1
        return (cs[ya, xa] + cs[yb, xb] - cs[ya, xb] - cs[yb, xa]) \
            / float((2 * rx + 1) * (2 * ry + 1))
    b1, b2 = _boxrect(R1, R1), _boxrect(R2, R2)
    # r4 (s28): the far trend is LOCAL/side-adaptive, not the global
    # average. The r3 R=256 square on a 360-720 canvas reads most of
    # the canvas, so far surround trended to the GLOBAL mean: a bright
    # top edge pulled toward the (darker) whole-frame average. Read two
    # anisotropic windows from the same integral image - wide-short for
    # pixels above/below the footprint, tall-narrow for left/right - so
    # the far trend stays on the same side's extended edge colour.
    RT = 64
    bw = _boxrect(R3, RT)
    bt = _boxrect(RT, R3)
    cyy, cxx = np.where(inside)
    cy, cx = float(cyy.mean()), float(cxx.mean())
    vert = np.abs(y0 - cy) >= np.abs(x0 - cx)
    b3 = np.where(vert[..., None], bw, bt)
    # distance-to-footprint for the blend: the BFS above already
    # computed it (L1, capped at 121 px; farther stays 1e9 -> t = 1)
    t1 = np.clip((dist - 1.0) / (D2 - 1.0), 0.0, 1.0)[..., None]
    t2 = np.clip((dist - D2) / (D3 - D2), 0.0, 1.0)[..., None]
    # lerp form: exact for constant fields (b + 0*t == b)
    outv = b1 + (b2 - b1) * t1
    outv = outv + (b3 - outv) * t2
    img[~inside] = outv[~inside].astype(np.uint8)  # single truncation
    return img


def render_frame_sbs(rgb, z, theta_h, ipd=0.063, convergence_m=None,
                     swap_eyes=False, out_w=None, out_h=None, depth_scale=1.0,
                     surround="soft", stats=None, roll_deg=0.0):
    """One frame -> SBS uint8 [out_h, 2*out_w, 3]. z in metres, 0 = masked.
    surround: "soft" (default, s3d_surround) or "off" (black outside the
    film footprint). stats: optional dict; when given it is filled with
    per-eye disocclusion instrumentation (s27): covered px, pair-fill px,
    edge-run-fill px, black-inside-footprint px. Instrumentation only -
    output bytes are identical whether or not stats is passed."""
    h, w = z.shape
    out_w = out_w or w
    out_h = out_h or h
    ipd = ipd * depth_scale  # RenderPrefsValue.effectiveIPD
    f = (w / 2.0) / math.tan(theta_h / 2.0)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    rx, ry = (xs + 0.5 - w / 2.0) / f, (h / 2.0 - (ys + 0.5)) / f
    eyes = []
    phi = math.radians(roll_deg)
    for sign in ([1.0, -1.0] if swap_eyes else [-1.0, 1.0]):
        eye = sign * ipd / 2.0
        ex, ey = eye * math.cos(phi), eye * math.sin(phi)   # 191a C3: rolled eye axis
        if convergence_m and convergence_m > 0:
            nc = math.sqrt(ex * ex + ey * ey + convergence_m ** 2)
            conv = math.atan2(ex, convergence_m)
            conv_lat = math.asin(ey / nc)
        else:
            conv = conv_lat = 0.0
        px, py, pz = rx * z - ex, ry * z - ey, z
        n = np.sqrt(px * px + py * py + pz * pz)
        with np.errstate(invalid="ignore", divide="ignore"):
            lat = np.arcsin(np.clip(np.divide(py, n, where=n > 0), -1, 1))
        lat = np.where(n > 0, lat, 0.0) + conv_lat
        lon = np.arctan2(px, pz) + conv
        iu = np.floor((lon / math.pi + 0.5) * out_w).astype(np.int64)
        iv = np.floor((0.5 - lat / math.pi) * out_h).astype(np.int64)
        ok = (z > 0) & (n > 0) & (iu >= 0) & (iu < out_w) & (iv >= 0) & (iv < out_h)
        img = np.zeros((out_h, out_w, 3), np.uint8)
        zbuf = np.full((out_h, out_w), np.inf)
        cov = np.zeros((out_h, out_w), bool)
        sel = np.flatnonzero(ok.ravel())
        order = np.argsort(-z.ravel()[sel], kind="stable")  # far first
        sel = sel[order]
        img[iv.ravel()[sel], iu.ravel()[sel]] = rgb.reshape(-1, 3)[sel]
        zbuf[iv.ravel()[sel], iu.ravel()[sel]] = z.ravel()[sel]
        cov[iv.ravel()[sel], iu.ravel()[sel]] = True
        # far-side row fill (matches s3d_fill): gaps between covered pixels
        pair_filled = 0
        for r in range(out_h):
            cols = np.flatnonzero(cov[r])
            for a, b in zip(cols[:-1], cols[1:]):
                if b - a > 1:
                    src = a if zbuf[r, a] >= zbuf[r, b] else b
                    img[r, a + 1:b] = img[r, src]
                    pair_filled += b - a - 1
        # edge-run fill (s3d_fill r2, 190v item 4): a disocclusion strip
        # can run from the last covered pixel to the FRUSTUM boundary -
        # no covered pixel on the outer side, so the pair pass leaves it
        # black (the vertical tear at the footprint edge on the CG
        # golden). Fill leading/trailing runs INSIDE the source frustum
        # with the sole adjacent endpoint, which is the far side in the
        # canonical disocclusion geometry (near surface shifts away from
        # the strip). Outside-frustum pixels stay black for the surround.
        fp = footprint_mask(rgb, theta_h, conv, out_w, out_h, conv_lat=conv_lat)
        edge_filled = 0
        for r in range(out_h):
            cols = np.flatnonzero(cov[r])
            if len(cols) == 0:
                continue
            fpx = np.flatnonzero(fp[r])
            if len(fpx) == 0:
                continue
            lo, hi = fpx[0], fpx[-1]
            if cols[0] > lo:
                img[r, lo:cols[0]] = img[r, cols[0]]
                edge_filled += cols[0] - lo
            if cols[-1] < hi:
                img[r, cols[-1] + 1:hi + 1] = img[r, cols[-1]]
                edge_filled += hi - cols[-1]
        if stats is not None:
            # black-inside-footprint: uncovered, unfilled pixels left in
            # the film footprint after both fill passes (must be 0)
            black = int((fp & ~cov & (img.sum(axis=2) == 0)).sum())
            stats.setdefault("eyes", []).append({
                "covered": int(cov.sum()),
                "pair_filled": pair_filled,
                "edge_filled": edge_filled,
                "footprint_px": int(fp.sum()),
                "footprint_black": black})
        if surround == "soft":
            _surround_soft_vec(rgb, theta_h, conv, out_w, out_h, img,
                               conv_lat=conv_lat)
        elif surround != "off":
            raise ValueError("surround must be 'soft' or 'off'")
        eyes.append(img)
    return np.concatenate(eyes, axis=1)


def eye_n_for(source_height):
    """Port of ThreeDRenderCoordinator.eyeN: square eye side for the
    rendered shot."""
    return max(256, min(4096, source_height - source_height % 2))


def render_shot_sbs(entry_dir, shot, ipd=0.063, convergence_m=None,
                    swap_eyes=True, out_w=None, out_h=None, max_frames=None,
                    screen_deg=DEFAULT_SCREEN_DEG, depth_scale=1.0,
                    surround="soft", z_near=None, stats_list=None):
    """One prepared shot -> (sbs uint8 [T,OH,2*OW,3], info dict).
    z_near: optional comfort near clamp (s25/s27): z -> max(z, z_near)
    for z > 0, matching the Mac kernel znear. stats_list: optional list;
    per-eye disocclusion instrumentation dicts are appended per frame."""
    from prepare_film import D_SCALE, read_depth_hevc
    meta = json.load(open(os.path.join(entry_dir, f"depth_shot_{shot:05d}.json")))
    w, h = meta["depth_width"], meta["depth_height"]
    inv, start_pts = read_depth_hevc(
        os.path.join(entry_dir, f"depth_shot_{shot:05d}.mp4"), size=(h, w),
        max_frames=max_frames)
    z = np.where(inv > 0, D_SCALE / np.maximum(inv, 1e-9), 0.0).astype(np.float64)
    sw, sh = meta["source_width"], meta["source_height"]
    if (w, h) != (sw, sh):
        # s24: letterbox box depth (same aspect, smaller) is upsampled
        # to the source size, canonical inverse-plane bilinear
        import depth_upsample as du
        assert du.compatible(w, h, sw, sh), ((w, h), (sw, sh))
        z = np.stack([du.upsample(zk, sw, sh) for zk in z])
    if z_near is not None:
        z = np.where(z > 0, np.maximum(z, z_near), 0.0)
    rgb = _read_source_frames(
        os.path.join(entry_dir, f"source_shot_{shot:05d}.mp4"),
        meta["source_width"], meta["source_height"], max_frames=max_frames)
    ft = json.load(open(os.path.join(entry_dir, "fov_track.json")))
    entry = ft["shots"][shot]
    shot_theta_h = math.radians(entry["hfov_deg"])
    aspect = meta["source_width"] / meta["source_height"]
    theta_h = theta_h_for(screen_deg, shot_theta_h, aspect)
    if out_w is None and out_h is None:
        out_w = out_h = eye_n_for(meta["source_height"])
    t = min(len(rgb), len(z))
    if max_frames is not None:
        t = min(t, max_frames)
    per = []
    for k in range(t):
        st = {} if stats_list is not None else None
        per.append(render_frame_sbs(rgb[k], z[k], theta_h, ipd,
                                    convergence_m, swap_eyes, out_w,
                                    out_h, depth_scale, surround, st))
        if stats_list is not None:
            stats_list.append(st)
    frames = np.stack(per)
    info = {"shot": shot, "frames": t,
            "theta_h_deg": math.degrees(theta_h),
            "shot_hfov_deg": entry["hfov_deg"], "screen_deg": screen_deg,
            "aspect": aspect, "ipd": ipd, "depth_scale": depth_scale,
            "convergence_m": convergence_m, "swap_eyes": swap_eyes,
            "surround": surround,
            "out_w": frames.shape[2] // 2, "out_h": frames.shape[1],
            "start_pts": start_pts}
    if z_near is not None:
        info["z_near"] = z_near  # conditional: committed manifests unchanged
    return frames, info


def golden_manifest(frames, info):
    """Per-frame + whole-sequence sha256 over raw uint8 SBS bytes - the Swift
    renderer on the Mac must reproduce these hashes from the same inputs."""
    per = [hashlib.sha256(frames[k].tobytes()).hexdigest() for k in range(len(frames))]
    whole = hashlib.sha256(frames.tobytes()).hexdigest()
    return dict(info, frame_sha256=per, sequence_sha256=whole)
