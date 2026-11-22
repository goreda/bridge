"""s37: stereo-source handling (CONTRACT-190v s37).

Sources that are ALREADY 3D must never go through 2D->3D depth. Three
detection layers, in increasing cost:
  1. container/spatial metadata (Matroska StereoMode / frame-packing SEI /
     Spherical Video V2 stereo / MV-HEVC profile) - authoritative.
  2. filename hints - WEAK signal only (sbs/ou/vr180 tokens): never
     confirms, only raises suspicion for the pixel test.
  3. pixel-level L/R confirm: split the frame by the suspected layout,
     block-match for disparity; a true stereo pair correlates strongly at
     a nonzero horizontal shift, a 2D split-screen does not. False-
     positive rate measured on 2D films in test_stereo_probe.py.

Passthrough: split eyes -> repack into any s36 flat mode directly;
vr180 output = place the baked-stereo screen into the headset canvas
(depth already baked, the screen sits at the convergence plane); vr180
equirect sources repack to vr180 or project down to flat. Baked-in
disparity gets a WARN-ONLY comfort check (measure_disparity); we never
alter someone else's stereo master. Misdetect: menu override (E-G notes
in s37).
"""
import json
import os
import re
import subprocess

import numpy as np

LAYOUTS = ("sbs", "half_sbs", "ou", "half_ou", "vr180", "mvhevc")

# Matroska/ffprobe "Stereo 3D" side-data type -> (layout, default_eye_swap)
STEREOMODE_MAP = {
    "side by side": ("sbs", False),
    "side by side (quincunx)": ("sbs", False),
    "top and bottom": ("ou", False),
    "left_right": ("sbs", False),
    "right_left": ("sbs", True),
    "top_bottom": ("ou", False),
    "bottom_top": ("ou", True),
}
SPHERICAL_STEREO = {"left-right": ("vr180", False), "right-left": ("vr180", True)}

HINT_RE = [(r"(?<![a-z])(h[-_.]?sbs|half[-_.]?sbs)(?![a-z])", "half_sbs"),
           (r"(?<![a-z])(f[-_.]?sbs|full[-_.]?sbs|sbs|lr[-_.]?3d)(?![a-z])", "sbs"),
           (r"(?<![a-z])(h[-_.]?ou|half[-_.]?ou|half[-_.]?tb)(?![a-z])", "half_ou"),
           (r"(?<![a-z])(ou|over[-_.]?under|tb|top[-_.]?bottom)(?![a-z])", "ou"),
           (r"(?<![a-z])(vr180|180[-_.]?3d|3d[-_.]?180)(?![a-z])", "vr180")]


def _ffprobe(path):
    pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                         "-show_streams", "-of", "json", path],
                        capture_output=True, text=True)
    st = json.loads(pr.stdout)["streams"][0]
    return st


def metadata_verdict(path, stream=None):
    """Layer 1+2: (layout, eye_swap, source) or (None, False, None).
    source: 'metadata' (authoritative) or 'filename' (weak hint)."""
    st = stream if stream is not None else _ffprobe(path)
    for sd in st.get("side_data_list", []):
        sdt = str(sd.get("side_data_type", ""))
        if sdt == "Stereo 3D":
            # ffprobe json: {"side_data_type": "Stereo 3D", "type": "side by side", "inverted": 0}
            kind = sd.get("type", "")
            inv = bool(sd.get("inverted", 0))
            if kind in STEREOMODE_MAP:
                lay, sw = STEREOMODE_MAP[kind]
                return (lay, sw != inv, "metadata")
        if "pherical" in sdt:   # Spherical Video V2 / spherical_video_v2
            sm = sd.get("stereo_mode")
            if sm in SPHERICAL_STEREO:
                lay, sw = SPHERICAL_STEREO[sm]
                return (lay, sw, "metadata")
    profile = (st.get("profile") or "").lower()
    tag = (st.get("codec_tag_string") or "").lower()
    if "multiview" in profile or tag.startswith("mv-"):
        return ("mvhevc", False, "metadata")
    name = os.path.basename(path).lower()
    for rx, lay in HINT_RE:
        if re.search(rx, name):
            return (lay, False, "filename")
    return (None, False, None)


def split_eyes(frame, layout):
    """frame [H,W,3] -> (L, R) at full per-eye size for the layout."""
    h, w = frame.shape[:2]
    if layout in ("sbs", "vr180"):
        return frame[:, : w // 2], frame[:, w // 2:]
    if layout == "half_sbs":
        L = frame[:, : w // 2]
        R = frame[:, w // 2:]
        import cv2
        up = lambda im: cv2.resize(im, (w, h), interpolation=cv2.INTER_CUBIC)
        return up(L), up(R)
    if layout == "ou":
        return frame[: h // 2], frame[h // 2:]
    if layout == "half_ou":
        import cv2
        up = lambda im: cv2.resize(im, (w, h // 2 * 2 // 2), interpolation=cv2.INTER_CUBIC)
        L = up(frame[: h // 2])
        R = up(frame[h // 2:])
        return L, R
    raise ValueError(layout)


def best_shift_ncc(L, R, max_shift=None):
    """L/R similarity: max over horizontal shifts of the normalized
    cross-correlation between HIGH-PASSED grey halves (Laplacian-of-
    Gaussian style: grey minus a wide blur). High-passing is the FP
    discriminator: adjacent halves of a smooth 2D frame correlate
    strongly in raw grey but their edge content differs, while true
    stereo keeps matching edges at the disparity shift. Returns
    (best_hp_ncc, best_shift_px, grey_ncc_at_0)."""
    import cv2

    def grey(im):
        return cv2.cvtColor(im, cv2.COLOR_RGB2GRAY).astype(np.float32)

    def ncc(a, b):
        if a.size == 0:
            return -1.0
        aa, bb = a.ravel(), b.ravel()
        return float(((aa - aa.mean()) * (bb - bb.mean())).mean()
                     / (aa.std() * bb.std() + 1e-6))

    def hp(g):
        return g - cv2.GaussianBlur(g, (0, 0), 3.0)

    gl, gr = grey(L), grey(R)
    hl, hr = hp(gl), hp(gr)
    ww = hl.shape[1]
    ms = max_shift or ww // 5
    best, bd = -1.0, 0
    for d in range(-ms, ms + 1):
        x, y = (hl[:, d:], hr[:, : ww - d]) if d >= 0 else (hl[:, : d], hr[:, -d:])
        if x.shape[1] < ww // 3:
            continue
        v = ncc(x, y)
        if v > best:
            best, bd = v, d
    return best, bd, ncc(gl, gr)


def confirm_stereo(L, R, hp_thresh=0.4):
    """Layer 3 pixel confirm. True stereo: strong high-pass NCC at the
    disparity shift. Duplicated-half fake SBS (L == R): also confirms
    (harmless - it has no depth to lose; the asymmetry that matters is
    never feeding real stereo into 2D->3D). 2D split-screen / adjacent
    halves of one 2D frame: high-pass content is independent -> score
    near 0 (measured: stereo fixture 0.95 vs <= 0.04 on live/anim/dark
    2D films, both SBS and OU splits). Returns
    (is_stereo, hp_ncc, shift_px, grey_ncc0)."""
    hp_ncc, d, grey0 = best_shift_ncc(L, R)
    return hp_ncc >= hp_thresh, hp_ncc, d, grey0


def measure_disparity(L, R, assume_hfov_deg=90.0, block=32, ncc_min=0.5):
    """WARN-ONLY comfort check of baked-in disparity: per-block shift-NCC
    (high-passed grey, 32 px blocks, +-W/8 search) -> angular stats under
    an assumed per-eye hfov (the bake's fov is unknowable; 90 deg is the
    consumer-stereo norm). Block NCC is far more robust than StereoBM on
    weak-texture bakes (StereoBM scattered p99 10x past ground truth on
    the synthetic fixture; block NCC lands within a third). Returns px +
    degree percentiles, the budget-exceeding fraction and block coverage,
    or None when too few blocks lock (unmeasurable - the warning says
    so, it never blocks the passthrough)."""
    import cv2
    w0 = L.shape[1]
    scale = 1.0
    if w0 < 256:
        scale = 256.0 / w0
        L = cv2.resize(L, (256, int(L.shape[0] * scale)), interpolation=cv2.INTER_CUBIC)
        R = cv2.resize(R, (256, int(R.shape[0] * scale)), interpolation=cv2.INTER_CUBIC)
    gl = cv2.cvtColor(L, cv2.COLOR_RGB2GRAY).astype(np.float32)
    gr = cv2.cvtColor(R, cv2.COLOR_RGB2GRAY).astype(np.float32)
    gl -= cv2.GaussianBlur(gl, (0, 0), 3.0)
    gr -= cv2.GaussianBlur(gr, (0, 0), 3.0)
    h, w = gl.shape
    span = w // 8

    def ncc(a, b):
        aa, bb = a.ravel(), b.ravel()
        return float(((aa - aa.mean()) * (bb - bb.mean())).mean()
                     / (aa.std() * bb.std() + 1e-6))

    vals, total = [], 0
    for y in range(0, h - block + 1, block // 2):
        for x in range(0, w - block + 1, block // 2):
            total += 1
            bl = gl[y:y + block, x:x + block]
            if bl.std() < 1e-3:
                continue
            best, bd = -1.0, 0
            for d in range(-span, span + 1):
                xs, xe = x + d, x + d + block
                if xs < 0 or xe > w:
                    continue
                v = ncc(bl, gr[y:y + block, xs:xe])
                if v > best:
                    best, bd = v, d
            if best >= ncc_min:
                vals.append(bd / scale)
    if len(vals) < max(8, total * 0.05):
        return None
    signed = np.asarray(vals, np.float64)
    med = np.median(signed)  # MAD rejection: isolated block mislocks on
    mad = np.median(np.abs(signed - med)) + 1.0  # smooth gradients scatter
    signed = signed[np.abs(signed - med) <= 4 * mad]  # to +-10 px; real
    v = np.abs(signed)  # near regions survive (they are consistent)
    deg_per_px = assume_hfov_deg / w0
    p50, p95, p99 = np.percentile(v, [50, 95, 99])
    return {"px_p50": float(p50), "px_p99": float(p99),
            "deg_p50": float(p50 * deg_per_px), "deg_p95": float(p95 * deg_per_px),
            "deg_p99": float(p99 * deg_per_px),
            "over_budget_frac": float((v * deg_per_px > 2.0).mean()),
            "coverage": float(len(vals) / total),
            "assume_hfov_deg": assume_hfov_deg}


# ---------- passthrough ----------

def place_on_vr180(L, R, n, theta_h, surround_rgb=None):
    """Place baked-stereo perspective eyes onto the vr180 canvas as a flat
    screen at the convergence plane: canvas pixel -> direction -> screen
    texture sample; outside the screen: surround colour or black."""
    import cv2
    h, w = L.shape[:2]
    f_out = (w / 2.0) / np.tan(theta_h / 2.0)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    lon = (xs + 0.5) / n * np.pi - np.pi / 2
    lat = np.pi / 2 - (ys + 0.5) / n * np.pi
    fx = np.tan(lon) * f_out + w / 2.0
    fy = h / 2.0 - np.tan(lat) * f_out
    out = []
    for eye in (L, R):
        img = np.zeros((n, n, 3), np.uint8)
        inside = (fx >= 0) & (fx < w) & (fy >= 0) & (fy < h)
        img[inside] = cv2.remap(eye, fx.astype(np.float32), fy.astype(np.float32),
                                cv2.INTER_LINEAR)[inside]
        if surround_rgb is not None:
            img[~inside] = surround_rgb
        out.append(img)
    return np.concatenate(out, axis=1)


def vr180_to_perspective(frame, out_w, out_h, hfov_deg=75.0):
    """VR180 equirect packed frame [n,2n,3] -> flat perspective eyes at
    out_w x out_h (crop of the forward hfov). Returns (L, R)."""
    import cv2
    n = frame.shape[0]
    eyes = (frame[:, :n], frame[:, n:])
    f = (out_w / 2.0) / np.tan(np.radians(hfov_deg) / 2.0)
    ys, xs = np.mgrid[0:out_h, 0:out_w].astype(np.float64)
    lon = np.arctan((xs + 0.5 - out_w / 2) / f)
    lat = np.arctan((out_h / 2 - ys - 0.5) / f)
    mx = ((lon + np.pi / 2) / np.pi * n - 0.5).astype(np.float32)
    my = ((np.pi / 2 - lat) / np.pi * n - 0.5).astype(np.float32)
    return tuple(cv2.remap(e, mx, my, cv2.INTER_LINEAR) for e in eyes)


def passthrough(frame, src_layout, out_mode, swap=False, theta_h=None,
                surround_rgb=None):
    """One packed source frame -> packed s36 output frame. Baked disparity
    is preserved bit-for-bit on flat repacks; vr180 placement renders the
    stereo screen at the convergence plane."""
    import output_modes as om
    L, R = split_eyes(frame, src_layout)
    if swap:
        L, R = R, L
    h, w = L.shape[:2]
    if theta_h is None:
        theta_h = np.radians(75.0)
    if out_mode == "vr180":
        if src_layout == "vr180":
            out = np.concatenate([L, R], 1)
            return out
        n = om.eye_n_for(h)
        return place_on_vr180(L, R, n, theta_h, surround_rgb)
    if src_layout == "vr180":
        L, R = vr180_to_perspective(frame if not swap else
                                    np.concatenate([R, L], 1), w, h)
        if swap:
            L, R = R, L
    if out_mode == "full_sbs":
        return om.pack_full_sbs(L, R)
    if out_mode == "half_sbs":
        return om.pack_half_sbs(L, R)
    if out_mode == "over_under":
        return om.pack_over_under(L, R)
    if out_mode == "anaglyph":
        return om.anaglyph_dubois(L, R)
    raise ValueError(out_mode)
