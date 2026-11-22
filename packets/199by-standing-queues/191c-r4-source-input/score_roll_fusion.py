#!/usr/bin/env python3
"""191c R4 roll-fusion measured pixel scorer (Task 3 of 3).

Binds to:
  * generator manifest schema "roll-markers/v1" (Task 1 output)
  * capture index schema "roll-capture-index/v1" (Task 2 output)
  * source under test: zuellue/gorav-native-ci @
    2ca10de8ab767d8a24d8c3f4b481e5d6984701e0,
    payload/gor/Resources/vendor/mpv/scripts/vr180-look.lua
    (flat preview sampling ~1822-1827, native optical-centre rotation
    ~1919-1928, native split screen-aligned). The runner binds the actual
    shader bytes; this scorer validates the index's hash-binding fields.
It does not re-verify runner state: effective_options, pose_message, sync,
option_receipt and shader_slot are carried, never validated.

Conventions (explicit; do not change silently):
  * Pixel coords: origin top-left, x right, y DOWN (image rows). All p_L/p_R
    are pixel centres in this frame.
  * Eye axis a = (cos th, sin th); a_perp = (-sin th, cos th);
    th_eff = roll_sign * angle_deg from the capture record (production
    rollSign path; crossed runs carry roll_sign = -1).
  * Vertical fusion error e_v = (p_R - p_L) . a_perp   [S10].
  * Preview acceptance: max|e_v| <= 1 px per fixture/angle, all 9 marker
    pairs matched, complete angle/mode set, zero-roll pixel-identical to
    the bound baseline.
  * Native (native_vr180) measurements are REPORTED SEPARATELY as a
    regression result; not gated on the preview 1 px bound, and not a new
    native all-path approval.

Exit codes: 0 PASS, 1 acceptance FAIL (complete evidence), 2 input/hash
ERROR, 3 INCOMPLETE (missing markers/captures/angles/baselines; cannot
pass). Never fabricates captures: scores only hash-bound capture records.
Deps: numpy, Pillow. Generated pixels only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys

import numpy as np
from PIL import Image

SCHEMA_MANIFEST = "roll-markers/v1"

REQUIRED_ANGLES_DEG = (-30.0, -15.0, -5.0, 0.0, 5.0, 15.0, 30.0)
CROSSED_ANGLES_DEG = (-15.0, 15.0)
CROSSED_MODES = {"sbs"}  # protocol 7: one crossed +/-15 run class (SBS preview)
PREVIEW_MODES = {"sbs", "half_sbs", "top_bottom", "mono"}
NATIVE_MODES = {"native_vr180"}

TOLERANCE_PX = 1.0
NCC_THRESHOLD = 0.55
IDENTITY_VERIFY_TOL = 80     # per-channel mean colour check at NCC peak
IDENTITY_SEGMENT_TOL = 48    # per-channel colour-segmentation fallback
DUPLICATE_DISTANCE_PX = 3.0
MIN_COLOUR_PIXELS = 20
MAX_COLOUR_PIXELS = 4000

EXIT_PASS, EXIT_ACCEPTANCE_FAIL, EXIT_INPUT_ERROR, EXIT_INCOMPLETE = 0, 1, 2, 3


class InputError(Exception):
    """Malformed manifest/capture index, or hash-binding violation."""


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def axis_vectors(theta_deg):
    th = math.radians(theta_deg)
    return (math.cos(th), math.sin(th)), (-math.sin(th), math.cos(th))


def vertical_error(p_r, p_l, theta_eff_deg):
    """e_v = (p_R - p_L) . a_perp, image coords (y down)."""
    _, ap = axis_vectors(theta_eff_deg)
    return (p_r[0] - p_l[0]) * ap[0] + (p_r[1] - p_l[1]) * ap[1]


def axial_separation(p_r, p_l, theta_eff_deg):
    a, _ = axis_vectors(theta_eff_deg)
    return (p_r[0] - p_l[0]) * a[0] + (p_r[1] - p_l[1]) * a[1]


def load_rgb(path):
    with Image.open(path) as im:
        return np.asarray(im.convert("RGB"), dtype=np.float64)


# ---------------- manifest binding (roll-markers/v1, Task 1) ----------------

def load_manifest(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            m = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        raise InputError(f"manifest unreadable: {e}")
    if m.get("schema") != SCHEMA_MANIFEST:
        raise InputError(
            f"manifest schema must be {SCHEMA_MANIFEST!r}, got {m.get('schema')!r}")
    fixtures = m.get("fixtures")
    if not isinstance(fixtures, list) or not fixtures:
        raise InputError("manifest has no fixtures array")
    base = os.path.dirname(os.path.abspath(path))
    out = {}
    for fx in fixtures:
        for key in ("id", "mode", "width", "height", "sha256", "markers", "eyes"):
            if key not in fx:
                raise InputError(f"fixture {fx.get('id')!r} missing field {key!r}")
        if fx["mode"] not in PREVIEW_MODES | NATIVE_MODES:
            raise InputError(f"fixture {fx['id']!r}: unknown mode {fx['mode']!r}")
        seen, markers = set(), []
        for mk in fx["markers"]:
            for key in ("id", "identity_rgb", "positions"):
                if key not in mk:
                    raise InputError(f"fixture {fx['id']!r} marker missing {key!r}")
            if mk["id"] in seen:
                raise InputError(
                    f"fixture {fx['id']!r}: duplicate marker id {mk['id']!r}")
            seen.add(mk["id"])
            positions = {}
            for eye, pos in mk["positions"].items():
                for key in ("template_path", "template_sha256", "source_pixel_xy"):
                    if key not in pos:
                        raise InputError(
                            f"{fx['id']}:{mk['id']}:{eye} missing {key!r}")
                tp = pos["template_path"]
                if not os.path.isabs(tp):
                    tp = os.path.join(base, tp)
                positions[eye] = {"template_path": tp,
                                  "template_sha256": pos["template_sha256"],
                                  "source_pixel_xy": list(pos["source_pixel_xy"]),
                                  "eye_uv": (list(pos["eye_uv"])
                                             if pos.get("eye_uv") else None)}
            markers.append({"id": mk["id"],
                            "identity_rgb": list(mk["identity_rgb"]),
                            "positions": positions})
        out[fx["id"]] = {"id": fx["id"], "mode": fx["mode"],
                         "width": int(fx["width"]), "height": int(fx["height"]),
                         "sha256": fx["sha256"],
                         "sample_aspect_ratio": list(fx.get("sample_aspect_ratio", [1, 1])),
                         "signed_disparity_fraction": fx.get("signed_disparity_fraction"),
                         "eyes": fx["eyes"], "markers": markers}
    return out


# ------------- capture index binding (roll-capture/v1, Task 2) ---------------

SCHEMA_CAPTURE_INDEX = "roll-capture/v1"
SOURCE_REPO = "zuellue/gorav-native-ci"
SOURCE_COMMIT = "2ca10de8ab767d8a24d8c3f4b481e5d6984701e0"
SOURCE_PATH = "payload/gor/Resources/vendor/mpv/scripts/vr180-look.lua"
MODE_MAP = {"sbs": "flat-sbs", "half_sbs": "flat-sbs",
            "top_bottom": "flat-tb", "mono": "flat-2d3d",
            "native_vr180": "vr180"}
RECORD_REQUIRED = ("capture_id", "fixture_id", "fixture_sha256", "mode",
                   "roll_deg", "roll_rad", "crossed", "zero_roll_baseline",
                   "pose_message", "effective_options", "shader_sha256",
                   "renderer_class", "status", "error", "image",
                   "acceptance_class", "command")


def _validate_image(base, rec_id, img):
    for key in ("path", "sha256", "width", "height"):
        if key not in img:
            raise InputError(f"capture {rec_id}: image missing {key!r}")
    path = img["path"]
    if not os.path.isabs(path):
        path = os.path.join(base, path)
    if not os.path.isfile(path):
        raise InputError(f"capture {rec_id}: image file missing: {img['path']}")
    actual = sha256_file(path)
    if actual != img["sha256"]:
        raise InputError(
            f"capture {rec_id}: image sha256 mismatch (record "
            f"{img['sha256'][:12]}..., file {actual[:12]}...): "
            "evidence not hash-bound, refusing")
    return path


def _parse_golden(base, rid, golden, is_evidence):
    """rec.golden carries the zero-roll golden carrier: bound flag, sha256,
    path. Bound goldens of evidence records must hash-verify."""
    if golden is None:
        return None
    if not isinstance(golden, dict) or "bound" not in golden:
        raise InputError(f"capture {rid}: malformed golden field")
    if not golden["bound"]:
        return {"bound": False}
    sha = golden.get("golden_sha256") or ""
    if not (len(sha) == 64
            and all(c in "0123456789abcdef" for c in sha)):
        raise InputError(f"capture {rid}: bound golden lacks 64-hex sha256")
    path = golden.get("path") or golden.get("golden_path")
    if not path:
        raise InputError(f"capture {rid}: bound golden lacks a path")
    p = path if os.path.isabs(path) else os.path.join(base, path)
    if is_evidence:
        if not os.path.isfile(p):
            raise InputError(f"capture {rid}: golden file missing: {path}")
        if sha256_file(p) != sha:
            raise InputError(f"capture {rid}: golden sha256 mismatch")
    elif os.path.isfile(p) and sha256_file(p) != sha:
        raise InputError(f"capture {rid}: golden sha256 mismatch")
    return {"bound": True, "sha256": sha,
            "path": p if os.path.isfile(p) else None}


def load_capture_index(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            idx = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        raise InputError(f"capture index unreadable: {e}")
    if idx.get("schema") != SCHEMA_CAPTURE_INDEX:
        raise InputError(
            f"capture index schema must be {SCHEMA_CAPTURE_INDEX!r}, "
            f"got {idx.get('schema')!r}")
    src = idx.get("source") or {}
    if src.get("commit") != SOURCE_COMMIT:
        raise InputError(
            f"capture index source.commit must be {SOURCE_COMMIT}, "
            f"got {src.get('commit')!r}")
    if src.get("repo") != SOURCE_REPO:
        raise InputError(
            f"capture index source.repo must be {SOURCE_REPO!r}, "
            f"got {src.get('repo')!r}")
    if src.get("path") != SOURCE_PATH:
        raise InputError(
            f"capture index source.path must be {SOURCE_PATH!r}, "
            f"got {src.get('path')!r}")
    fm = idx.get("fixtures_manifest") or {}
    if fm.get("schema") != SCHEMA_MANIFEST or "sha256" not in fm:
        raise InputError("capture index fixtures_manifest binding missing")
    binding = src.get("binding_status")
    if binding not in ("verified", "missing", "mismatch", "unbound-smoke"):
        raise InputError(
            f"source.binding_status must be verified|missing|mismatch|"
            f"unbound-smoke, got {binding!r}")
    if binding == "verified":
        actual = src.get("actual_sha256") or ""
        if not (len(actual) == 64 and all(
                c in "0123456789abcdef" for c in actual)):
            raise InputError("verified binding requires a 64-hex "
                             "source.actual_sha256")
        expected = src.get("expected_sha256") or ""
        if not (len(expected) == 64 and all(
                c in "0123456789abcdef" for c in expected)):
            raise InputError("verified binding requires a 64-hex "
                             "source.expected_sha256 (null not allowed)")
        if expected != actual:
            raise InputError("source.expected_sha256 != actual_sha256")
    env = idx.get("environment") or {}
    if env.get("renderer_class") not in ("hardware", "software", "unavailable"):
        raise InputError("capture index environment.renderer_class must be "
                         "hardware|software|unavailable")
    base = os.path.dirname(os.path.abspath(path))
    captures = []
    for i, rec in enumerate(idx.get("captures") or []):
        rid = rec.get("capture_id", f"#{i}")
        for key in RECORD_REQUIRED:
            if key not in rec:
                raise InputError(f"capture {rid}: missing field {key!r}")
        if not isinstance(rec["roll_deg"], (int, float)) \
                or isinstance(rec["roll_deg"], bool) \
                or not math.isfinite(rec["roll_deg"]):
            raise InputError(f"capture {rid}: roll_deg not a finite number")
        if not isinstance(rec["roll_rad"], (int, float)) \
                or isinstance(rec["roll_rad"], bool) \
                or not math.isfinite(rec["roll_rad"]):
            raise InputError(f"capture {rid}: roll_rad not a finite number")
        if abs(rec["roll_rad"] - math.radians(rec["roll_deg"])) > 1e-6:
            raise InputError(f"capture {rid}: roll_rad inconsistent with roll_deg")
        for flag in ("crossed", "zero_roll_baseline"):
            if not isinstance(rec[flag], bool):
                raise InputError(f"capture {rid}: {flag} must be boolean")
        if rec["renderer_class"] not in ("hardware", "software", "unavailable"):
            raise InputError(f"capture {rid}: renderer_class invalid")
        if rec["acceptance_class"] not in (
                "evidence", "smoke_not_evidence", "not_run"):
            raise InputError(f"capture {rid}: acceptance_class invalid")
        if rec["status"] not in ("captured", "not_run", "error",
                                 "captured_shader_error"):
            raise InputError(f"capture {rid}: status invalid")
        if rec["acceptance_class"] == "evidence":
            if binding != "verified":
                raise InputError(
                    f"capture {rid}: evidence-class record under unbound "
                    f"source ({binding}); an unbound smoke is never evidence")
            if rec["shader_sha256"] != src["actual_sha256"]:
                raise InputError(
                    f"capture {rid}: shader_sha256 != source.actual_sha256")
        if rec["image"] is not None:
            if (rec["image"].get("width"), rec["image"].get("height")) \
                    != (2560, 1600):
                raise InputError(
                    f"capture {rid}: protocol requires 2560x1600 captures, "
                    f"got {rec['image'].get('width')}x"
                    f"{rec['image'].get('height')}")
        img_path = None
        if rec["image"] is not None:
            if (rec["acceptance_class"] == "evidence"
                    and rec["status"] == "captured"):
                img_path = _validate_image(base, rid, rec["image"])
            else:
                # non-evidence metadata: validate when the file is there,
                # never required (the runner's smoke tree may be absent)
                p = rec["image"]["path"]
                if not os.path.isabs(p):
                    p = os.path.join(base, p)
                if os.path.isfile(p):
                    img_path = _validate_image(base, rid, rec["image"])
        elif rec["status"] == "captured" \
                and rec["acceptance_class"] == "evidence":
            raise InputError(f"capture {rid}: status captured but image null")
        captures.append({
            "capture_id": rec["capture_id"],
            "fixture_id": rec["fixture_id"],
            "fixture_sha256": rec["fixture_sha256"],
            "mode": rec["mode"],
            "roll_deg": float(rec["roll_deg"]),
            "crossed": rec["crossed"],
            "zero_roll_baseline": rec["zero_roll_baseline"],
            "pose_message": rec["pose_message"],
            "effective_options": rec["effective_options"],
            "shader_sha256": rec["shader_sha256"],
            "renderer_class": rec["renderer_class"],
            "acceptance_class": rec["acceptance_class"],
            "status": rec["status"],
            "error": rec["error"],
            "image_path": img_path,
            "image_sha256": rec["image"]["sha256"] if rec["image"] else None,
            "image_width": rec["image"]["width"] if rec["image"] else None,
            "image_height": rec["image"]["height"] if rec["image"] else None,
            "golden_comparison": rec.get("golden_comparison"),
            "golden": _parse_golden(base, rid, rec.get("golden"),
                                    rec["acceptance_class"] == "evidence"),
            "command": rec["command"],
        })
    shipping = None
    gc_blk = idx.get("golden_comparison")
    if isinstance(gc_blk, dict):
        shipping = gc_blk.get("shipping_shader_sha256")
    if not shipping:
        for rec in idx.get("captures") or []:  # raw records: parsed goldens
            g = rec.get("golden")              # drop unknown keys
            if rec.get("zero_roll_baseline") and isinstance(g, dict) \
                    and g.get("shipping_shader_sha256"):
                shipping = g["shipping_shader_sha256"]
                break
    if not shipping:
        shipping = idx.get("shipping_shader_sha256")
    if shipping is not None:
        if not (isinstance(shipping, str) and len(shipping) == 64
                and all(c in "0123456789abcdef" for c in shipping)):
            raise InputError("shipping_shader_sha256 must be 64-hex")
    return {"captures": captures, "environment": env, "source": src,
            "runner": idx.get("runner", {}),
            "golden_comparison": idx.get("golden_comparison"),
            "shipping_shader_sha256": shipping,
            "fixtures_manifest_sha256": fm["sha256"]}


# --------------------------- marker matching --------------------------------
# Primary locator: per-marker identity colour from the manifest (unique RGB
# per marker; scale- and rotation-free). Connected components of the colour
# mask give the marker centroid (subpixel via pixel-centre mean); zero
# components falls back to zero-mean NCC template matching (scale-sensitive:
# use only when identity colour is absent), more than one legal component is
# a duplicate and can never pass.

def mask_components(mask, min_n=MIN_COLOUR_PIXELS, max_n=MAX_COLOUR_PIXELS):
    """Connected components of a boolean mask. Returns list of (cx, cy, n):
    pixel-centre centroid and pixel count, 8-connectivity, run-length
    union-find."""
    parent = []
    runs_per_row = []

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    padded = np.pad(mask, ((0, 0), (1, 0)))
    row_has = np.any(np.diff(padded.astype(np.int8), axis=1) != 0, axis=1) \
        | np.any(mask, axis=1)
    prev = []
    for y in range(mask.shape[0]):
        if not row_has[y]:
            prev = []
            runs_per_row.append([])
            continue
        padded_row = padded[y]
        edges = np.flatnonzero(np.diff(padded_row.astype(np.int8)))
        cur = []
        for s, e in edges.reshape(-1, 2):
            lbl = len(parent)
            parent.append(lbl)
            for ps, pe, pl in prev:
                if ps <= e - 1 and s <= pe:
                    ra, rb = find(lbl), find(pl)
                    if ra != rb:
                        parent[ra] = rb
            cur.append((int(s), int(e) - 1, lbl))
        runs_per_row.append(cur)
        prev = cur
    acc = {}
    for y, cur in enumerate(runs_per_row):
        for s, e, lbl in cur:
            r = find(lbl)
            n = e - s + 1
            sx, sy, sn = acc.get(r, (0.0, 0.0, 0))
            acc[r] = (sx + (s + e) / 2.0 * n, sy + y * n, sn + n)
    out = []
    for sx, sy, n in acc.values():
        if min_n <= n <= max_n:
            out.append((sx / n, sy / n, n))
    return out


def colour_components(region_rgb, identity_rgb):
    """Components of pixels within IDENTITY_SEGMENT_TOL of identity_rgb."""
    diff = np.abs(region_rgb - np.asarray(identity_rgb, dtype=np.float64))
    return mask_components(np.all(diff <= IDENTITY_SEGMENT_TOL, axis=2))


def _integral(a):
    return np.pad(np.cumsum(np.cumsum(a, axis=0), axis=1), ((1, 0), (1, 0)))


def _window_sum(ii, h, w):
    return ii[h:, w:] - ii[:-h, w:] - ii[h:, :-w] + ii[:-h, :-w]


def ncc_surface(region, template):
    """Zero-mean normalized cross-correlation. ncc[y, x] scores the template
    with top-left at (x, y). None when the template cannot correlate."""
    H, W = region.shape
    h, w = template.shape
    if h > H or w > W:
        return None
    t = template - template.mean()
    t_norm = float(np.sqrt((t ** 2).sum()))
    if t_norm == 0.0:
        return None
    shape = (H + h - 1, W + w - 1)
    conv = np.fft.irfft2(np.fft.rfft2(region, shape)
                         * np.fft.rfft2(t[::-1, ::-1], shape), shape)
    conv_valid = conv[h - 1:H, w - 1:W]
    sum_i = _window_sum(_integral(region), h, w)
    sum_i2 = _window_sum(_integral(region * region), h, w)
    var_i = sum_i2 - (sum_i * sum_i) / (h * w)
    denom = np.sqrt(np.maximum(var_i, 0.0)) * t_norm
    out = np.zeros_like(conv_valid)
    np.divide(conv_valid, denom, out=out, where=denom > 1e-9)
    return out


def _subpixel(surf, y, x):
    def fit(vm, v0, vp):
        d = vm - 2.0 * v0 + vp
        return 0.0 if d >= 0.0 else 0.5 * (vm - vp) / d
    dy = fit(surf[y - 1, x], surf[y, x], surf[y + 1, x]) \
        if 0 < y < surf.shape[0] - 1 else 0.0
    dx = fit(surf[y, x - 1], surf[y, x], surf[y, x + 1]) \
        if 0 < x < surf.shape[1] - 1 else 0.0
    return y + dy, x + dx


def _ncc_match(region_rgb, template_rgb):
    """Template fallback. Returns (x, y, ncc, duplicate) pixel-centre coords
    in the region, or None."""
    surf = ncc_surface(region_rgb.mean(axis=2), template_rgb.mean(axis=2))
    if surf is None or not surf.size:
        return None
    h, w = template_rgb.shape[0], template_rgb.shape[1]
    y, x = np.unravel_index(int(np.argmax(surf)), surf.shape)
    peak = float(surf[y, x])
    if peak < NCC_THRESHOLD:
        return None
    sy, sx = _subpixel(surf, y, x)
    duplicate = False
    masked = surf.copy()
    masked[max(0, y - h):y + h + 1, max(0, x - w):x + w + 1] = -1.0
    second = float(masked.max())
    if second >= NCC_THRESHOLD:
        y2, x2 = np.unravel_index(int(np.argmax(masked)), masked.shape)
        duplicate = math.hypot(x2 - x, y2 - y) > DUPLICATE_DISTANCE_PX
    return sx + (w - 1) / 2.0, sy + (h - 1) / 2.0, peak, duplicate


COLOUR_MERGE_RADIUS_PX = 60.0  # one marker's lobes cluster within this


def _cluster_components(comps, radius=COLOUR_MERGE_RADIUS_PX):
    """Single-linkage clustering of colour components: one marker's identity
    colour legitimately appears as several lobes (cross arms around a bright
    core); genuinely separate markers are hundreds of px apart."""
    comps = list(comps)
    clusters = []
    for c in comps:
        merged = False
        for cl in clusters:
            if any(math.hypot(c[0] - o[0], c[1] - o[1]) <= radius for o in cl):
                cl.append(c)
                merged = True
                break
        if not merged:
            clusters.append([c])
    # one pass of single-linkage merging can miss chains; merge clusters
    changed = True
    while changed:
        changed = False
        for i in range(len(clusters)):
            for j in range(i + 1, len(clusters)):
                if any(math.hypot(a[0] - b[0], a[1] - b[1]) <= radius
                       for a in clusters[i] for b in clusters[j]):
                    clusters[i].extend(clusters[j])
                    del clusters[j]
                    changed = True
                    break
            if changed:
                break
    out = []
    for cl in clusters:
        n = sum(c[2] for c in cl)
        out.append((sum(c[0] * c[2] for c in cl) / n,
                    sum(c[1] * c[2] for c in cl) / n, n))
    return out


WHITE_CORE_MIN = 220          # per-channel floor for a marker's white core
CORE_WINDOW_PX = 40           # identity sampling half-window around a core
MIN_CORE_PIXELS = 10


SYMMETRY_WINDOW_RADIUS = 40
SYMMETRY_SEARCH = 8


def symmetry_centre(img_gray, cx, cy):
    """Refine a marker position to its symmetry centre.

    Marker patterns are centrosymmetric (cross + radial ramp), and rendering
    blur (bilinear/bicubic resampling, GPU sampling) is symmetric, so the
    centre of symmetry is the true marker centre regardless of template
    subpixel rasterization phase. conv(A, A) of the zero-mean window peaks
    at twice the centre offset; parabolic interpolation gives subpixel.
    Falls back to the input position on degenerate windows.
    """
    H, W = img_gray.shape
    cx, cy = int(round(cx)), int(round(cy))
    R = SYMMETRY_WINDOW_RADIUS
    x0, x1 = max(0, cx - R), min(W, cx + R + 1)
    y0, y1 = max(0, cy - R), min(H, cy + R + 1)
    win = img_gray[y0:y1, x0:x1].astype(np.float64)
    if win.shape[0] < 9 or win.shape[1] < 9 or win.std() < 1e-6:
        return float(cx), float(cy)
    a = win - win.mean()
    h, w = a.shape
    s = (2 * h - 1, 2 * w - 1)
    f = np.fft.rfft2(a, s)
    conv = np.fft.irfft2(f * f, s)
    # peak of conv(A, A) sits at twice the centre offset from the window
    # origin; search near the window-centre lag (h-1, w-1)
    k = SYMMETRY_SEARCH
    sub = conv[h - 1 - k:h + k, w - 1 - k:w + k]
    iy, ix = np.unravel_index(int(np.argmax(sub)), sub.shape)
    py, px = h - 1 - k + iy, w - 1 - k + ix

    def fit(vm, v0, vp):
        d = vm - 2.0 * v0 + vp
        return 0.0 if d >= 0.0 else 0.5 * (vm - vp) / d

    dy = fit(conv[py - 1, px], conv[py, px], conv[py + 1, px]) \
        if 0 < py < conv.shape[0] - 1 else 0.0
    dx = fit(conv[py, px - 1], conv[py, px], conv[py, px + 1]) \
        if 0 < px < conv.shape[1] - 1 else 0.0
    return x0 + (px + dx) / 2.0, y0 + (py + dy) / 2.0


def _patch_ncc(patch, tmpl):
    """Zero-mean NCC, RGB channels pooled. Colour-sensitive: an impostor
    identity's template mismatches both shape and colour ramp."""
    p = patch - patch.reshape(-1, 3).mean(axis=0)
    t = tmpl - tmpl.reshape(-1, 3).mean(axis=0)
    den = float(np.sqrt((p ** 2).sum() * (t ** 2).sum()))
    return float((p * t).sum() / den) if den > 0.0 else 0.0


SCALE_GRID = tuple(round(0.3 + 0.2 * i, 2) for i in range(12))  # 0.3..2.5
ASPECT_FAMILIES = (1.0, 2.222)  # (sy/sx): square; preview half 1600/720
IDENT_NCC_MIN = 0.50
IDENT_NCC_MARGIN = 0.05
IDENT_MEAN_TOL = 8.0  # per-channel patch-vs-template mean gate


def _scaled_template(tmpl, sx, sy, cache):
    key = (id(tmpl), sx, sy)
    if key in cache:
        return cache[key]
    w = max(4, int(round(tmpl.shape[1] * sx)))
    h = max(4, int(round(tmpl.shape[0] * sy)))
    out = np.asarray(Image.fromarray(tmpl.astype(np.uint8)).resize(
        (w, h), Image.BILINEAR), dtype=np.float64)
    cache[key] = out
    return out


def _identify_by_template(region_rgb, cx, cy, cand_ids, templates_by_id,
                          scale_cache, angle_deg=0.0):
    """Pick the identity whose template best matches at the core, searching
    scale (aspect family x scale grid). Returns (id, ncc) or (None, best)."""
    H, W = region_rgb.shape[0], region_rgb.shape[1]
    per_id = {}
    for mid in cand_ids:
        for tmpl in templates_by_id.get(mid, ()):  # already SAR-corrected
            for fam in ASPECT_FAMILIES:
                for sx in SCALE_GRID:
                    t = _scaled_template(tmpl, sx, sx * fam, scale_cache)
                    if angle_deg:
                        # marker content rotates with the rolled view
                        key = (id(t), sx, sx * fam, angle_deg)
                        if key in scale_cache:
                            t = scale_cache[key]
                        else:
                            t = np.asarray(Image.fromarray(
                                t.astype(np.uint8)).rotate(
                                angle_deg, resample=Image.BILINEAR,
                                fillcolor=(12, 12, 12)), dtype=np.float64)
                            scale_cache[key] = t
                    th, tw = t.shape[0], t.shape[1]
                    y0, x0 = int(round(cy)) - th // 2, int(round(cx)) - tw // 2
                    if y0 < 0 or x0 < 0 or y0 + th > H or x0 + tw > W:
                        continue
                    patch = region_rgb[y0:y0 + th, x0:x0 + tw]
                    # mean-colour gate: an impostor identity (blend-ring
                    # lookalike) keeps its own mean colour, the true marker
                    # matches it; NCC alone cannot separate them reliably
                    if np.abs(patch.reshape(-1, 3).mean(axis=0)
                              - t.reshape(-1, 3).mean(axis=0)).max() \
                            > IDENT_MEAN_TOL:
                        continue
                    ncc = _patch_ncc(patch, t)
                    if ncc > per_id.get(mid, -1.0):
                        per_id[mid] = ncc
    ranked = sorted(per_id.items(), key=lambda kv: -kv[1])
    if not ranked or ranked[0][1] < IDENT_NCC_MIN:
        return None, ranked[0][1] if ranked else -1.0
    if len(ranked) > 1 and ranked[0][1] - ranked[1][1] < IDENT_NCC_MARGIN:
        return None, ranked[0][1]  # ambiguous identity: never a silent pick
    return ranked[0]


def locate_marker_cores(region_rgb, identity_map, templates_by_id=None,
                        angle_deg=0.0):
    """Locate marker candidates in a frame.

    Every marker has a white core (unambiguous: no identity colour or
    background is near-white, and blends only approach white at the core
    itself). Identity comes from the dominant identity colour in a window
    around the core; when colour counts are ambiguous (blend rings can
    imitate another identity, e.g. (96,255,96)->white passes through
    (176,255,176)), a scale-searching template NCC at the core decides.
    Returns (cores_by_id, n_cores): cores_by_id maps marker id -> list of
    (x, y, core_pixels) candidates, duplicates included.
    """
    H, W = region_rgb.shape[0], region_rgb.shape[1]
    white = np.all(region_rgb >= WHITE_CORE_MIN, axis=2)
    cores = _cluster_components(
        mask_components(white, MIN_CORE_PIXELS, MAX_COLOUR_PIXELS))
    cores_by_id = {}
    scale_cache = {}
    n_unidentified = 0
    for cx, cy, n in cores:
        x0 = max(0, int(cx) - CORE_WINDOW_PX)
        x1 = min(W, int(cx) + CORE_WINDOW_PX + 1)
        y0 = max(0, int(cy) - CORE_WINDOW_PX)
        y1 = min(H, int(cy) + CORE_WINDOW_PX + 1)
        win = region_rgb[y0:y1, x0:x1]
        counts = {}
        for mid, col in identity_map.items():
            d = np.abs(win - np.asarray(col, dtype=np.float64)).max(axis=2)
            counts[mid] = int((d <= IDENTITY_SEGMENT_TOL).sum())
        ranked = sorted(counts.items(), key=lambda kv: -kv[1])
        best_id, best_n = ranked[0]
        if best_n < MIN_COLOUR_PIXELS:
            n_unidentified += 1
            continue  # white structure without a known marker colour
        ambiguous = [mid for mid, c in ranked if c >= max(MIN_COLOUR_PIXELS,
                                                         0.5 * best_n)]
        if len(ambiguous) > 1 and templates_by_id:
            mid, ncc = _identify_by_template(region_rgb, cx, cy, ambiguous,
                                             templates_by_id, scale_cache,
                                             angle_deg=angle_deg)
            if mid is None:
                n_unidentified += 1
                continue  # unresolved identity: counted, never ignored
            best_id = mid
        cores_by_id.setdefault(best_id, []).append((cx, cy, n))
    return cores_by_id, len(cores), n_unidentified


def match_marker(region_rgb, template_rgb, identity_rgb):
    """Locate one marker in a region. Returns dict with x, y, method
    (colour|template), ncc or colour_pixels, duplicate; or None."""
    comps = colour_components(region_rgb, identity_rgb)
    clusters = _cluster_components(comps) if comps else []
    clusters = [c for c in clusters
                if MIN_COLOUR_PIXELS <= c[2] <= MAX_COLOUR_PIXELS * 4]
    if len(clusters) == 1:
        cx, cy, n = clusters[0]
        return {"x": cx, "y": cy, "method": "colour", "ncc": None,
                "colour_pixels": n, "duplicate": False}
    if len(clusters) > 1:
        return {"x": None, "y": None, "method": "colour", "ncc": None,
                "colour_pixels": [c[2] for c in clusters], "duplicate": True}
    m = _ncc_match(region_rgb, template_rgb)
    if m is None:
        return None
    x, y, ncc, dup = m
    return {"x": x, "y": y, "method": "template", "ncc": ncc, "duplicate": dup}


# ------------------------------ capture scoring -----------------------------

def eye_regions(width, height):
    """Screen search regions per eye, image coords (x0, y0, w, h).

    Preview modes compose the two eyes into left/right halves of the output
    surface (assumption for flat-tb sources: production presents them in the
    same left/right preview layout; a wrong assumption yields unmatched
    markers, never a silent pass). vr180 native split stays screen-aligned:
    halves first, flagged full-frame fallback in score_capture.
    """
    half = width // 2
    return {"left": (0, 0, half, height), "right": (half, 0, width - half, height)}


def _prepare_template(fx, eye, pos, cache):
    key = (fx["id"], eye, pos["template_path"])
    if key in cache:
        return cache[key]
    if not os.path.isfile(pos["template_path"]):
        raise InputError(f"fixture {fx['id']!r}: template missing: {pos['template_path']}")
    actual = sha256_file(pos["template_path"])
    if actual != pos["template_sha256"]:
        raise InputError(
            f"fixture {fx['id']!r} {eye}: template sha256 mismatch (manifest "
            f"{pos['template_sha256'][:12]}..., file {actual[:12]}...)")
    tmpl = load_rgb(pos["template_path"])
    sar = fx["sample_aspect_ratio"]
    if sar[0] != sar[1]:
        # restore logical-eye aspect (half-SBS sar 2:1: source columns are
        # stretched 2x on display); match in display geometry
        new_w = int(round(tmpl.shape[1] * sar[0] / sar[1]))
        tmpl = np.asarray(Image.fromarray(tmpl.astype(np.uint8)).resize(
            (new_w, tmpl.shape[0]), Image.BILINEAR), dtype=np.float64)
    cache[key] = tmpl
    return tmpl


def theta_eff_deg(rec):
    """Effective on-screen roll: production rollSign path; crossed runs carry
    rollSign = -1 (protocol 7 sign-confirmation runs)."""
    return (-1.0 if rec["crossed"] else 1.0) * rec["roll_deg"]


def predict_position(eye, u, v, width, height, theta_eff):
    """Rigid-roll hypothesis for preview modes: the composed pair rotates
    about the output centre by theta_eff, so a marker at eye-uv (u, v) lands
    at c + R(theta_eff) . (base - c), base = half_offset + (u*half_w, v*H).
    R is the content rotation mapping (S, 0) -> S*(cos th, sin th)."""
    x = (0.0 if eye == "left" else width / 2.0) + u * width / 2.0
    y = v * height
    th = math.radians(theta_eff)
    dx, dy = x - width / 2.0, y - height / 2.0
    return (width / 2.0 + dx * math.cos(th) - dy * math.sin(th),
            height / 2.0 + dx * math.sin(th) + dy * math.cos(th))


ASSIGN_MAX_DIST_PX = 420.0   # model-mismatch allowance for eye assignment
ASSIGN_MIN_RATIO = 2.0       # farther prediction must be >= this x nearer


def _assign_eye(cand, preds):
    dl = math.hypot(cand[0] - preds["left"][0], cand[1] - preds["left"][1])
    dr = math.hypot(cand[0] - preds["right"][0], cand[1] - preds["right"][1])
    near, dnear, dfar = ("left", dl, dr) if dl <= dr else ("right", dr, dl)
    if dnear <= ASSIGN_MAX_DIST_PX and dfar >= ASSIGN_MIN_RATIO * max(dnear, 1.0):
        return near
    return None


def score_capture(fx, rec, template_cache):
    """Score one captured, evidence-class record against its fixture."""
    img = load_rgb(rec["image_path"])
    H, W = img.shape[0], img.shape[1]
    if (W, H) != (rec["image_width"], rec["image_height"]):
        raise InputError(
            f"capture {rec['capture_id']}: recorded "
            f"{rec['image_width']}x{rec['image_height']} != actual {W}x{H}")
    regions = eye_regions(W, H)
    teff = theta_eff_deg(rec)
    identity_map = {mk["id"]: mk["identity_rgb"] for mk in fx["markers"]}
    native = fx["mode"] in NATIVE_MODES
    templates_by_id = {}
    for mk in fx["markers"]:
        tmpls = []
        for eye in ("left", "right"):
            pos = mk["positions"].get(eye) or mk["positions"].get("mono")
            if pos is not None:
                tmpls.append(_prepare_template(fx, eye, pos, template_cache))
        templates_by_id[mk["id"]] = tmpls
    cores_by_id, n_cores, n_unidentified = locate_marker_cores(
        img, identity_map, templates_by_id, angle_deg=-teff)
    markers = []
    extras = []
    for mk in fx["markers"]:
        entry = {"id": mk["id"], "eyes": {}}
        if n_cores == 0:
            # no white cores anywhere: per-marker colour/template fallback
            for eye in ("left", "right"):
                pos = mk["positions"].get(eye) or mk["positions"].get("mono")
                if pos is None:
                    entry["eyes"][eye] = {"status": "no_source_position"}
                    continue
                tmpl = _prepare_template(fx, eye, pos, template_cache)
                xr, yr, wr, hr = regions[eye]
                region = img[yr:yr + hr, xr:xr + wr]
                m = match_marker(region, tmpl, mk["identity_rgb"])
                if m is None or m.get("duplicate"):
                    entry["eyes"][eye] = (
                        {"status": "duplicate_match", "method": m["method"]}
                        if m and m.get("duplicate")
                        else {"status": "unmatched"})
                    continue
                entry["eyes"][eye] = {"status": "matched", "x": xr + m["x"],
                                      "y": yr + m["y"], "method": m["method"],
                                      "ncc": m["ncc"]}
            pl, pr = entry["eyes"].get("left"), entry["eyes"].get("right")
            if (pl and pr and pl.get("status") == "matched"
                    and pr.get("status") == "matched"):
                entry["e_v"] = vertical_error((pr["x"], pr["y"]),
                                              (pl["x"], pl["y"]), teff)
                entry["separation_px"] = axial_separation(
                    (pr["x"], pr["y"]), (pl["x"], pl["y"]), teff)
            markers.append(entry)
            continue
        cands = [list(c) for c in cores_by_id.get(mk["id"], [])]
        if len(cands) > 2:
            for eye in ("left", "right"):
                entry["eyes"][eye] = {"status": "duplicate_match",
                                      "method": "colour"}
            markers.append(entry)
            extras.append(mk["id"])
            continue
        if not native:
            preds = {}
            for e2 in ("left", "right"):
                p2 = mk["positions"].get(e2) or mk["positions"].get("mono")
                if p2 is not None and p2.get("eye_uv"):
                    u2, v2 = p2["eye_uv"]
                    preds[e2] = predict_position(e2, u2, v2, W, H, teff)
            if len(preds) < 2:
                preds = None
        else:
            preds = None  # native split stays screen-aligned: halves
        claimed = set()
        for eye in ("left", "right"):
            fallback_half = False
            pos = mk["positions"].get(eye) or mk["positions"].get("mono")
            if pos is None:
                entry["eyes"][eye] = {"status": "no_source_position"}
                continue
            _prepare_template(fx, eye, pos, template_cache)  # hash binding
            chosen = None
            for i, cand in enumerate(cands):
                if i in claimed:
                    continue
                if preds is not None:
                    hit = _assign_eye(cand, preds)
                    if hit is None:
                        # measured-FAIL fallback: geometry too far off the
                        # rigid model for prediction; bounded half assignment
                        # keeps the marker so e_v reports the failure
                        hit = ("left" if cand[0] < W / 2.0 else "right")
                        fallback_half = True
                else:
                    hit = "left" if cand[0] < W / 2.0 else "right"
                if hit == eye:
                    chosen = cand
                    claimed.add(i)
                    break
            if chosen is None:
                entry["eyes"][eye] = {"status": "unmatched"}
                continue
            rx, ry = symmetry_centre(img.mean(axis=2), chosen[0], chosen[1])
            st = {"status": "matched", "x": rx, "y": ry,
                  "method": "colour+symmetry", "ncc": None,
                  "core_pixels": chosen[2]}
            if fallback_half:
                st["assigned_by"] = "half_fallback"
            entry["eyes"][eye] = st
        if len(cands) > len(claimed) and len(cands) <= 2:
            entry["unassigned_extra_cores"] = len(cands) - len(claimed)
        markers.append(entry)


        pl, pr = entry["eyes"].get("left"), entry["eyes"].get("right")
        if (pl and pr and pl.get("status") == "matched"
                and pr.get("status") == "matched"):
            entry["e_v"] = vertical_error((pr["x"], pr["y"]),
                                          (pl["x"], pl["y"]), teff)
            entry["separation_px"] = axial_separation(
                (pr["x"], pr["y"]), (pl["x"], pl["y"]), teff)
    matched = [m for m in markers if "e_v" in m]
    unmatched = [m["id"] for m in markers if any(
        m["eyes"].get(e, {}).get("status") != "matched" for e in ("left", "right"))]
    n_extra = sum(m.get("unassigned_extra_cores", 0) for m in markers)
    return {"fixture_id": fx["id"], "mode": fx["mode"],
            "capture_id": rec["capture_id"],
            "roll_deg": rec["roll_deg"], "crossed": rec["crossed"],
            "theta_eff_deg": teff, "markers": markers,
            "n_pairs_matched": len(matched), "n_markers": len(markers),
            "unmatched_marker_ids": unmatched,
            "clipped_marker_ids": list(unmatched),
            "n_unidentified_cores": n_unidentified,
            "n_unassigned_extra_cores": n_extra,
            "max_abs_e_v": max((abs(m["e_v"]) for m in matched), default=None)}


def diff_exact(path_a, path_b):
    a, b = load_rgb(path_a), load_rgb(path_b)
    if a.shape != b.shape:
        return {"identical": False, "reason": "dimension_mismatch",
                "shape_a": list(a.shape), "shape_b": list(b.shape),
                "diff_pixels": None}
    d = np.any(a != b, axis=2)
    n = int(d.sum())
    return {"identical": n == 0, "diff_pixels": n,
            "max_channel_delta": int(np.abs(a - b).max()) if n else 0}


# -------------------------- evaluation / acceptance -------------------------

REQUIRED_PLAN = {
    "sbs": (-0.02, 0.0, 0.02),
    "half_sbs": (-0.02, 0.0, 0.02),
    "top_bottom": (-0.02, 0.0, 0.02),
    "mono": (0.0,),
    "native_vr180": (-0.02, 0.0, 0.02),
}
PLAN_MARKERS_PER_FIXTURE = 9


def validate_plan(manifest):
    """The 191c plan is fixed: 13 fixtures (mode x disparity sign set),
    9 markers each. A partial plan must never reach acceptance; use
    --allow-subset-manifest for diagnostics."""
    want = {}
    for mode, signs in REQUIRED_PLAN.items():
        for s in signs:
            want[(mode, s)] = 0
    for fid, fx in manifest.items():
        if fx["mode"] not in REQUIRED_PLAN:
            raise InputError(f"fixture {fid}: mode {fx['mode']!r} not in the "
                             "191c plan")
        if fx.get("signed_disparity_fraction") not in REQUIRED_PLAN[fx["mode"]]:
            raise InputError(f"fixture {fid}: disparity "
                             f"{fx.get('signed_disparity_fraction')} not in "
                             f"the plan for {fx['mode']}")
        if len(fx["markers"]) != PLAN_MARKERS_PER_FIXTURE:
            raise InputError(f"fixture {fid}: plan requires "
                             f"{PLAN_MARKERS_PER_FIXTURE} markers, got "
                             f"{len(fx['markers'])}")
        want[(fx["mode"], fx["signed_disparity_fraction"])] += 1
    missing = [f"{m}/{s}" for (m, s), n in want.items() if n == 0]
    dup = [f"{m}/{s}" for (m, s), n in want.items() if n > 1]
    if missing or dup:
        raise InputError(f"plan incomplete: missing {missing or '[]'}, "
                         f"duplicate {dup or '[]'}; use "
                         "--allow-subset-manifest for diagnostics")


def evaluate(manifest, index, tolerance_px=TOLERANCE_PX):
    report = {
        "schema": "roll-fusion-score/v1",
        "conventions": {
            "pixel_origin": "top-left, x right, y down (image rows)",
            "e_v": "(p_R - p_L) . a_perp, a=(cos th,sin th), a_perp=(-sin th,cos th)",
            "theta_eff": "(-1 if crossed else +1) * roll_deg "
                         "(production rollSign path)",
            "tolerance_px": tolerance_px,
            "preview_acceptance": "max|e_v| <= tolerance, all marker pairs "
                                  "matched, complete angle set, zero-roll "
                                  "pixel-exact",
            "native": "reported separately as regression; not gated on 1 px",
            "evidence_rule": "only status=captured AND "
                             "acceptance_class=evidence records are scored",
        },
        "environment": index.get("environment", {}),
        "source": index.get("source", {}),
        "runner": index.get("runner", {}),
        "preview": {}, "crossed": {}, "native_regression": {},
        "zero_roll": {}, "failures": [], "incomplete": [],
    }
    template_cache = {}
    for rec in index["captures"]:
        fx = manifest.get(rec["fixture_id"])
        if fx is None:
            raise InputError(
                f"capture {rec['capture_id']}: unknown fixture "
                f"{rec['fixture_id']!r}")
        if fx["sha256"] != rec["fixture_sha256"]:
            raise InputError(
                f"capture {rec['capture_id']}: fixture_sha256 != manifest "
                "sha256; refusing unbound evidence")
        if rec["mode"] != MODE_MAP[fx["mode"]]:
            raise InputError(
                f"capture {rec['capture_id']}: mode {rec['mode']!r} does not "
                f"match fixture mode {fx['mode']!r} -> {MODE_MAP[fx['mode']]!r}")
    usable, refused = {}, 0
    for rec in index["captures"]:
        key = (rec["fixture_id"], rec["roll_deg"], rec["crossed"],
               rec["zero_roll_baseline"])
        if rec["status"] != "captured" or rec["acceptance_class"] != "evidence":
            refused += 1
            note = ("shader error cell: not scorable"
                    if rec["status"] == "captured_shader_error"
                    else "not evidence")
            report["incomplete"].append(
                f"capture {rec['capture_id']}: status={rec['status']!r} "
                f"acceptance_class={rec['acceptance_class']!r} "
                f"error={rec['error']!r} -> {note}")
            continue
        if key in usable:
            raise InputError(f"duplicate capture record for {key}")
        usable[key] = rec
    # completeness: every fixture x required angles; crossed on zero-d fixtures
    for fid, fx in sorted(manifest.items()):
        for ang in REQUIRED_ANGLES_DEG:
            if (fid, ang, False, False) not in usable:
                report["incomplete"].append(
                    f"missing capture: {fid} @ {ang:+.6g} deg")
        b0 = usable.get((fid, 0.0, False, True))
        has_golden = (b0 is not None and b0.get("golden")
                      and b0["golden"].get("bound")
                      and b0["golden"].get("path"))
        if not has_golden:
            report["incomplete"].append(
                f"missing zero-roll golden carrier: {fid}")
    # crossed +/-15: one pair per production kind (runner plan governs).
    # Acceptance runs bind the full manifest, so every production kind is
    # required; --allow-subset-manifest binds a subset manifest, scoping the
    # kinds to that subset for diagnostics only.
    kinds = {}
    for fid, fx in manifest.items():
        kinds.setdefault(MODE_MAP[fx["mode"]], []).append((fid, fx))
    for kind, members in sorted(kinds.items()):
        zero_fids = [fid for fid, fx in members
                     if fx.get("signed_disparity_fraction") == 0.0]
        if not zero_fids:
            report["incomplete"].append(
                f"no zero-disparity fixture for crossed runs: {kind}")
            continue
        for ang in CROSSED_ANGLES_DEG:
            if not any((fid, ang, True, False) in usable for fid in zero_fids):
                report["incomplete"].append(
                    f"missing crossed capture for kind {kind} @ "
                    f"{ang:+.6g} deg (fixtures: {zero_fids})")
    # score every usable capture, even when the set is incomplete
    for (fid, ang, crossed, baseline), rec in sorted(usable.items()):
        if baseline:
            continue  # baselines only feed the zero-roll exact diff
        fx = manifest[fid]
        res = score_capture(fx, rec, template_cache)
        bucket = ("native_regression" if fx["mode"] in NATIVE_MODES
                  else "crossed" if crossed else "preview")
        fx_rep = report[bucket].setdefault(fid, {
            "mode": fx["mode"],
            "signed_disparity_fraction": fx["signed_disparity_fraction"],
            "renderer_class": rec["renderer_class"],
            "shader_sha256": rec["shader_sha256"], "angles": {}})
        ang_key = f"{ang:+.6g}" + (" crossed" if crossed else "")
        fx_rep["angles"][ang_key] = {
            "capture_id": rec["capture_id"],
            "max_abs_e_v": res["max_abs_e_v"],
            "n_pairs_matched": res["n_pairs_matched"],
            "n_markers": res["n_markers"],
            "unmatched_marker_ids": res["unmatched_marker_ids"],
            "clipped_marker_ids": res["clipped_marker_ids"],
            "n_unidentified_cores": res["n_unidentified_cores"],
            "n_unassigned_extra_cores": res["n_unassigned_extra_cores"],
            "theta_eff_deg": res["theta_eff_deg"],
            "pairs": [{"id": m["id"], "e_v": m.get("e_v"),
                       "separation_px": m.get("separation_px"),
                       "left": m["eyes"].get("left"),
                       "right": m["eyes"].get("right")}
                      for m in res["markers"]],
        }
    # preview acceptance gate (native deliberately excluded)
    for bucket in ("preview", "crossed"):
        for fid, fx_rep in report[bucket].items():
            for ang_s, a_rep in fx_rep["angles"].items():
                if a_rep["n_pairs_matched"] < a_rep["n_markers"]:
                    report["incomplete"].append(
                        f"{bucket} {fid} @ {ang_s}: "
                        f"{a_rep['n_pairs_matched']}/{a_rep['n_markers']} pairs "
                        f"matched (unmatched: {a_rep['unmatched_marker_ids']})")
                elif a_rep["n_unidentified_cores"] or \
                        a_rep["n_unassigned_extra_cores"]:
                    report["incomplete"].append(
                        f"{bucket} {fid} @ {ang_s}: unidentified/extra marker "
                        f"cores present ({a_rep['n_unidentified_cores']} "
                        f"unidentified, {a_rep['n_unassigned_extra_cores']} "
                        f"extra); not clean evidence")
                elif a_rep["max_abs_e_v"] is None \
                        or a_rep["max_abs_e_v"] > tolerance_px:
                    report["failures"].append(
                        f"{bucket} {fid} @ {ang_s}: max|e_v| = "
                        f"{a_rep['max_abs_e_v']} px > {tolerance_px} px")
    # native completeness gate (no 1 px acceptance; regression only)
    for fid, fx_rep in report["native_regression"].items():
        for ang_s, a_rep in fx_rep["angles"].items():
            if a_rep["n_pairs_matched"] < a_rep["n_markers"]:
                report["incomplete"].append(
                    f"native {fid} @ {ang_s}: "
                    f"{a_rep['n_pairs_matched']}/{a_rep['n_markers']} pairs "
                    f"matched (unmatched: {a_rep['unmatched_marker_ids']})")
            elif a_rep["n_unidentified_cores"] or \
                    a_rep["n_unassigned_extra_cores"]:
                report["incomplete"].append(
                    f"native {fid} @ {ang_s}: unidentified/extra marker "
                    f"cores present ({a_rep['n_unidentified_cores']} "
                    f"unidentified, {a_rep['n_unassigned_extra_cores']} "
                    f"extra); not clean evidence")
    # zero-roll pixel-exact comparison per fixture: the golden carrier is
    # the bound, hash-verified golden on the __baseline record (an
    # independent image). The baseline capture image itself is never used,
    # and run-record golden fields are ignored. golden_comparison NOT_RUN
    # is reported as NOT_RUN.
    report["shipping_shader_sha256"] = index.get("shipping_shader_sha256")
    idx_gc = index.get("golden_comparison")
    idx_gc_not_run = idx_gc == "NOT_RUN" or (
        isinstance(idx_gc, dict) and idx_gc.get("status") == "NOT_RUN")
    for fid in sorted(manifest):
        run = usable.get((fid, 0.0, False, False))
        if run is None:
            continue  # missing run already reported above
        rec_gc = run.get("golden_comparison")
        gc_not_run = idx_gc_not_run or rec_gc == "NOT_RUN" or (
            isinstance(rec_gc, dict) and rec_gc.get("status") == "NOT_RUN")
        b = usable.get((fid, 0.0, False, True))
        g = (b or {}).get("golden") or {}
        if gc_not_run:
            report["zero_roll"][fid] = {
                "not_run": True, "reason": "golden_comparison NOT_RUN"}
            report["incomplete"].append(
                f"zero-roll {fid}: golden_comparison NOT_RUN")
            continue
        if not (b is not None and g.get("bound") and g.get("path")):
            report["zero_roll"][fid] = {
                "not_run": True,
                "reason": "no bound golden on the baseline record"}
            report["incomplete"].append(
                f"zero-roll {fid}: baseline record lacks a bound golden")
            continue
        d = diff_exact(run["image_path"], g["path"])
        entry = {"golden_sha256": g["sha256"],
                 "golden_carrier": "baseline_record",
                 "baseline_capture_id": b["capture_id"],
                 "run_capture_id": run["capture_id"],
                 "baseline_shader_sha256": b["shader_sha256"],
                 "run_shader_sha256": run["shader_sha256"], **d}
        report["zero_roll"][fid] = entry
        if not d["identical"]:
            report["failures"].append(
                f"zero-roll {fid}: capture differs from golden "
                f"(diff_pixels={d.get('diff_pixels')}, "
                f"reason={d.get('reason', 'pixel_diff')})")
    sw = any(r["renderer_class"] == "software" for r in usable.values())
    if sw:
        report["rendering_note"] = ("software rendering present: labelled "
                                    "software, not Mac/GPU acceptance")
    report["n_refused_records"] = refused
    if not usable:
        # no usable evidence at all: nothing measured, never a pass/fail
        report["verdict"] = "INCOMPLETE"
        report["not_run"] = True
    elif report["failures"]:
        # a measured acceptance failure is a FAIL even where other cells
        # lack evidence; the incomplete list stays in the report
        report["verdict"] = "FAIL"
    elif report["incomplete"]:
        report["verdict"] = "INCOMPLETE"
    else:
        report["verdict"] = "PASS"
    return report


def print_summary(report, out=sys.stdout):
    print("191c R4 roll-fusion score summary", file=out)
    print(f"verdict: {report['verdict']}"
          + (" (not run: no usable evidence)" if report.get("not_run") else ""),
          file=out)
    if report.get("rendering_note"):
        print(f"note: {report['rendering_note']}", file=out)
    for bucket, label in (("preview", "PREVIEW"), ("crossed", "CROSSED"),
                          ("native_regression", "NATIVE (regression, not gated)")):
        for fid, fx_rep in sorted(report[bucket].items()):
            print(f"{label} {fid} mode={fx_rep['mode']} "
                  f"renderer={fx_rep['renderer_class']}", file=out)
            for ang_s, a_rep in sorted(
                    fx_rep["angles"].items(),
                    key=lambda kv: ("crossed" in kv[0],
                                    float(kv[0].split()[0]))):
                print(f"  {ang_s:>6} deg  max|e_v|={a_rep['max_abs_e_v']} px  "
                      f"pairs={a_rep['n_pairs_matched']}/{a_rep['n_markers']}  "
                      f"clipped={len(a_rep['clipped_marker_ids'])}", file=out)
    for fid, z in sorted(report["zero_roll"].items()):
        if z.get("not_run"):
            print(f"zero-roll {fid}: NOT_RUN "
                  f"({z.get('reason', 'no golden carrier')})", file=out)
        else:
            print(f"zero-roll {fid}: identical={z['identical']} "
                  f"diff_pixels={z.get('diff_pixels')}", file=out)
    for f_ in report["failures"]:
        print(f"FAIL: {f_}", file=out)
    for i_ in report["incomplete"]:
        print(f"INCOMPLETE: {i_}", file=out)


def main(argv=None):
    ap = argparse.ArgumentParser(description="191c R4 roll-fusion pixel scorer")
    ap.add_argument("--manifest", required=True, help="roll-markers/v1 manifest.json")
    ap.add_argument("--capture-index", required=True,
                    help="roll-capture/v1 capture index JSON")
    ap.add_argument("--output", help="write JSON report here")
    ap.add_argument("--tolerance-px", type=float, default=TOLERANCE_PX,
                    help="acceptance tolerance; values other than the "
                         "protocol default mark the run diagnostic and "
                         "non-acceptance")
    ap.add_argument("--allow-subset-manifest", action="store_true",
                    help="diagnostic mode: score a subset of the 13-fixture "
                         "plan; never acceptance evidence")
    args = ap.parse_args(argv)
    if not math.isfinite(args.tolerance_px) or not (
            0.0 <= args.tolerance_px <= TOLERANCE_PX):
        print(f"INPUT ERROR: --tolerance-px must be finite and within "
              f"[0, {TOLERANCE_PX}]", file=sys.stderr)
        return EXIT_INPUT_ERROR
    try:
        manifest = load_manifest(args.manifest)
        index = load_capture_index(args.capture_index)
        msha = sha256_file(args.manifest)
        if msha != index["fixtures_manifest_sha256"]:
            raise InputError(
                f"manifest sha256 ({msha[:12]}...) != capture index "
                f"fixtures_manifest.sha256 "
                f"({index['fixtures_manifest_sha256'][:12]}...); "
                "index is bound to a different manifest")
        if not args.allow_subset_manifest:
            validate_plan(manifest)
        report = evaluate(manifest, index, tolerance_px=args.tolerance_px)
        diagnostic = []
        if args.allow_subset_manifest:
            diagnostic.append("subset manifest")
        if args.tolerance_px != TOLERANCE_PX:
            diagnostic.append(f"tolerance override {args.tolerance_px}")
        if diagnostic:
            report["diagnostic"] = True
            report["acceptance"] = False
            report["diagnostic_reasons"] = diagnostic
        else:
            report["diagnostic"] = False
            report["acceptance"] = report["verdict"] == "PASS"
    except InputError as e:
        print(f"INPUT ERROR: {e}", file=sys.stderr)
        return EXIT_INPUT_ERROR
    print_summary(report)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=1)
    return {"PASS": EXIT_PASS, "FAIL": EXIT_ACCEPTANCE_FAIL,
            "INCOMPLETE": EXIT_INCOMPLETE}[report["verdict"]]


if __name__ == "__main__":
    sys.exit(main())
