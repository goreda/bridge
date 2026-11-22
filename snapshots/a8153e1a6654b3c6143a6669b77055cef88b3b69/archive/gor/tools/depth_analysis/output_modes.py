"""s36: output modes (CONTRACT-190v s36).

The real output set behind the Mac 3D menu. One eye renderer with three
projections + five packers; comfort/surround/overlay rules per mode and
the frame-packing metadata the player needs. Golden pins per mode:
Tests/DepthAnalysis/test_output_modes.py + golden/mode_fixture/.

Modes:
  full_sbs     flat display default. Per-eye PERSPECTIVE render of the
               75 deg virtual screen at the source size, packed L|R.
               Per-eye resolution preserved.
  half_sbs     same eyes squeezed 2:1 horizontally ([h, w] total). Player
               stretches back (SAR 2:1). Horizontal sampling per eye IS
               halved - smaller file/decode load, not "no resolution
               loss"; the angular geometry is identical after stretch.
  over_under   eyes stacked L over R ([2h, w]): for displays/players that
               want above-below. Full per-eye resolution.
  anaglyph     Dubois red/cyan combine of the perspective eyes ([h, w]):
               any display, red-cyan glasses; Dubois matrices cut retinal
               rivalry vs naive red/cyan. Same geometry; crosstalk is a
               display property, not a depth change.
  vr180        headset default. Per-eye EQUIRECT hemisphere (180x180 deg,
               square eye side eye_n_for), packed L|R + spherical
               metadata. Only mode with surround (the canvas outside the
               film footprint); comfort/surround per s25/s28.
  eye-swap     (swap=True on any packer) exchanges L and R: cross-eye
               free-viewing and wrong-cable fixes. Render-side, not a
               re-encode.

Comfort: the depth content of each eye is identical across modes, so the
s25 policy (shot median convergence + baseline shrink + near clamp)
applies unchanged; half_sbs halves PIXEL disparity but the player stretch
restores the same ANGULAR disparity. Overlays (subtitles) sit at the
convergence plane in every mode; in vr180 the delivery lane places them
in angular UI space (s27), in packed flat modes at zero disparity.
"""
import math

import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

DUBOIS_L = np.array([[0.437, 0.449, 0.164],
                     [-0.062, -0.062, -0.024],
                     [-0.048, -0.050, -0.017]])
DUBOIS_R = np.array([[-0.011, -0.032, -0.007],
                     [0.377, 0.761, 0.009],
                     [-0.026, -0.093, 1.234]])

MODES = ("full_sbs", "half_sbs", "over_under", "anaglyph", "vr180")

# Frame-packing metadata the player needs (mpv stereo-mode names +
# container hints). macOS/mpv mapping notes live in contract s36.
MODE_METADATA = {
    "full_sbs": {"stereo_mode": "sbsl", "layout": "side-by-side, left first",
                 "sar": "1:1", "per_eye": "full source size",
                 "container": "StereoMode=0 (block) or player flag; no SEI required"},
    "half_sbs": {"stereo_mode": "sbsl", "layout": "side-by-side, left first",
                 "sar": "2:1 (player stretches horizontally)",
                 "per_eye": "half horizontal sampling",
                 "container": "same as full_sbs; container/display aspect carries the stretch"},
    "over_under": {"stereo_mode": "abl", "layout": "above-below, left on top",
                   "sar": "1:1", "per_eye": "full source size",
                   "container": "same tagging family as sbs"},
    "anaglyph": {"stereo_mode": "mono", "layout": "single frame, Dubois red/cyan",
                 "sar": "1:1", "per_eye": "combined",
                 "container": "none: plays as ordinary 2D"},
    "vr180": {"stereo_mode": "sbsl + spherical", "layout": "side-by-side equirect 180x180/eye",
              "sar": "1:1", "per_eye": "square, eye_n_for(source height)",
              "container": "Spherical Video V2 (stereo-mode=left-right, "
                           "projection=equirect, bounds 180x180)"},
}


def eye_n_for(source_height):
    """Square VR180 eye side (mirrors ThreeDRenderCoordinator.eyeN)."""
    return max(256, min(4096, source_height - source_height % 2))


def render_eye(rgb, z, theta_h, sign=-1.0, ipd=0.063, convergence_m=None,
               depth_scale=1.0, projection="perspective", out_w=None,
               out_h=None, screen_deg=75.0, roll_deg=0.0):
    """One eye image. z metres (0 = masked). sign -1 = LEFT eye (same
    order as render_frame_sbs). projection:
      perspective - gnomonic, fov = screen_deg across out_w (flat modes)
      equirect180 - VR180 hemisphere (lon/lat +-90 deg), square canvas
      equirect360 - legacy full-sphere canvas (== render_frame_sbs map)
    Z-buffer nearest-wins + far-side row hole fill (same rules as
    render_frame_sbs; surround is a PACKER concern, vr180 only).
    Convergence (s44): PARALLEL shift, not toe-in. Perspective: u
    shifts by tan(conv) = eye/convergence_m, v untouched, so depth ==
    convergence_m lands on the same column in both eyes and vertical
    parallax is exactly 0 everywhere (toe-in's rotation gave up to
    ~1.2 px vertical parallax on the CG golden, worst at the frame
    corners, and let near-side rays cross qz<=0). Equirect: lon shifts
    by conv, matching Stereo3DKernel mode 0 and reference_render."""
    h, w = z.shape
    ipd = ipd * depth_scale
    out_w = out_w or w
    out_h = out_h or h
    f_src = (w / 2.0) / math.tan(theta_h / 2.0)
    f_out = (out_w / 2.0) / math.tan(math.radians(screen_deg) / 2.0)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    rx, ry = (xs + 0.5 - w / 2.0) / f_src, (h / 2.0 - (ys + 0.5)) / f_src
    eye = sign * ipd / 2.0
    phi = math.radians(roll_deg)
    ex, ey = eye * math.cos(phi), eye * math.sin(phi)
    px, py, pz = rx * z - ex, ry * z - ey, z.astype(np.float64)
    if convergence_m and convergence_m > 0:
        nc = math.sqrt(ex * ex + ey * ey + convergence_m ** 2)
        conv_lon = math.atan2(ex, convergence_m)     # = old conv when ey == 0
        conv_lat = math.asin(ey / nc)                # 0 when ey == 0
        ushift = (ex / convergence_m, ey / convergence_m)   # tan-form
    else:
        conv_lon = conv_lat = 0.0
        ushift = (0.0, 0.0)
    n = np.sqrt(px * px + py * py + pz * pz)
    with np.errstate(invalid="ignore", divide="ignore"):
        if projection == "perspective":
            u = np.where(pz > 0, px / np.maximum(pz, 1e-9) + ushift[0], 0.0)
            v = np.where(pz > 0, py / np.maximum(pz, 1e-9) + ushift[1], 0.0)
            iu = np.floor(u * f_out + out_w / 2.0).astype(np.int64)
            iv = np.floor(out_h / 2.0 - v * f_out).astype(np.int64)
            ok = (z > 0) & (pz > 0)
        else:
            lat = np.arcsin(np.clip(np.divide(py, n, where=n > 0), -1, 1))
            lat = np.where(n > 0, lat, 0.0) + conv_lat
            lon = np.arctan2(px, pz) + conv_lon
            if projection == "equirect180":
                iu = np.floor((lon / math.pi + 0.5) * out_w).astype(np.int64)
                iv = np.floor((0.5 - lat / math.pi) * out_h).astype(np.int64)
            elif projection == "equirect360":
                iu = np.floor((lon / (2 * math.pi) + 0.5) * out_w).astype(np.int64)
                iv = np.floor((0.5 - lat / math.pi) * out_h).astype(np.int64)
            else:
                raise ValueError(f"projection {projection}")
            ok = (z > 0) & (n > 0)
    ok = ok & (iu >= 0) & (iu < out_w) & (iv >= 0) & (iv < out_h)
    img = np.zeros((out_h, out_w, 3), np.uint8)
    zbuf = np.full((out_h, out_w), np.inf)
    cov = np.zeros((out_h, out_w), bool)
    sel = np.flatnonzero(ok.ravel())
    order = np.argsort(-z.ravel()[sel], kind="stable")     # far first
    sel = sel[order]
    img[iv.ravel()[sel], iu.ravel()[sel]] = rgb.reshape(-1, 3)[sel]
    zbuf[iv.ravel()[sel], iu.ravel()[sel]] = z.ravel()[sel]
    cov[iv.ravel()[sel], iu.ravel()[sel]] = True
    # s44: F1 fill from the shared reference (vr180_render_ref.fill_rows /
    # fill_edge_runs), the same integer-exact rule the Metal kernel mirrors.
    import vr180_render_ref as vref
    img, filled = vref.fill_rows(img, cov, zbuf, sign)
    if projection == "perspective":
        f_s = (w / 2.0) / math.tan(theta_h / 2.0)
        oy, ox = np.mgrid[0:out_h, 0:out_w].astype(np.float64)
        uu = (ox + 0.5 - out_w / 2.0) / f_out - ushift[0]
        vv = (out_h / 2.0 - (oy + 0.5)) / f_out - ushift[1]
        sx, sy = f_s * uu + w / 2.0, h / 2.0 - f_s * vv
        fp = (sx >= 0) & (sx < w) & (sy >= 0) & (sy < h)
    else:
        import reference_render as rr
        fp = rr.footprint_mask(rgb, theta_h, conv_lon, out_w, out_h,
                               conv_lat=conv_lat)
    img = vref.fill_edge_runs(img, cov, fp)
    return img


def render_eyes(rgb, z, theta_h, swap=False, **kw):
    """(L, R) pair; swap=True returns them exchanged (cross-eye)."""
    s = [1.0, -1.0] if swap else [-1.0, 1.0]
    return (render_eye(rgb, z, theta_h, sign=s[0], **kw),
            render_eye(rgb, z, theta_h, sign=s[1], **kw))


def pack_full_sbs(L, R):
    return np.concatenate([L, R], axis=1)


def pack_half_sbs(L, R):
    h, w = L.shape[:2]
    sq = lambda im: cv2.resize(im, (w // 2, h), interpolation=cv2.INTER_AREA)
    return np.concatenate([sq(L), sq(R)], axis=1)


def pack_over_under(L, R):
    return np.concatenate([L, R], axis=0)


def anaglyph_dubois(L, R):
    """Dubois red/cyan least-squares combine on gamma-coded sRGB."""
    a = L.astype(np.float64) @ DUBOIS_L.T + R.astype(np.float64) @ DUBOIS_R.T
    return np.clip(a + 0.5, 0, 255).astype(np.uint8)


def render_mode(rgb, z, theta_h, mode, swap=False, ipd=0.063,
                convergence_m=None, depth_scale=1.0, screen_deg=75.0,
                surround="soft", roll_deg=0.0):
    """One frame -> packed output for `mode`. vr180 needs the surround
    pass from reference_render (canvas outside the film footprint)."""
    kw = dict(ipd=ipd, convergence_m=convergence_m, depth_scale=depth_scale,
              screen_deg=screen_deg, roll_deg=roll_deg)
    if mode == "vr180":
        n = eye_n_for(z.shape[0])
        L, R = render_eyes(rgb, z, theta_h, swap=swap, projection="equirect180",
                           out_w=n, out_h=n, **kw)
        if surround == "soft":
            import reference_render as rr
            phi = math.radians(roll_deg)
            for img, sign in ((L, -1.0 if not swap else 1.0),
                              (R, 1.0 if not swap else -1.0)):
                if convergence_m and convergence_m > 0:
                    ex = sign * ipd * depth_scale / 2.0 * math.cos(phi)
                    ey = sign * ipd * depth_scale / 2.0 * math.sin(phi)
                    nc = math.sqrt(ex * ex + ey * ey + convergence_m ** 2)
                    conv, conv_lat = math.atan2(ex, convergence_m), math.asin(ey / nc)
                else:
                    conv = conv_lat = 0.0
                rr._surround_soft_vec(rgb, theta_h, conv, n, n, img,
                                      conv_lat=conv_lat)
        return np.concatenate([L, R], axis=1)
    L, R = render_eyes(rgb, z, theta_h, swap=swap, projection="perspective", **kw)
    if mode == "full_sbs":
        return pack_full_sbs(L, R)
    if mode == "half_sbs":
        return pack_half_sbs(L, R)
    if mode == "over_under":
        return pack_over_under(L, R)
    if mode == "anaglyph":
        return anaglyph_dubois(L, R)
    raise ValueError(f"mode {mode}")


def canvas_size(mode, src_w, src_h):
    """(W, H) of the packed output frame."""
    if mode == "full_sbs":
        return (2 * src_w, src_h)
    if mode == "half_sbs":
        return (src_w, src_h)
    if mode == "over_under":
        return (src_w, 2 * src_h)
    if mode == "anaglyph":
        return (src_w, src_h)
    if mode == "vr180":
        n = eye_n_for(src_h)
        return (2 * n, n)
    raise ValueError(mode)
