"""s34: source colour/format probe + verdicts (CONTRACT-190v s34).

One ffprobe read of a source film -> normalized facts + per-dimension
verdicts for the 3D chain (source -> HEVC proxy -> depth -> render ->
display). Dimensions: 8/10-bit, limited vs full range, BT.709/BT.2020/P3
primaries, HDR10/HLG/Dolby Vision, 4:2:0 chroma, odd sizes, anamorphic
(non-square) pixels, rotated/portrait, VFR.

Verdict statuses:
  ok     - chain handles it as-is
  note   - handled, but a behaviour worth pinning (tests do)
  warn   - handled by a default rule; tagging the source would be better
  fix    - the chain must normalize this before prepare (rotation, SAR)
  refuse - prepare must not run; play 2D. HDR/Dolby Vision are NEVER
           silently tone-clipped; VFR breaks frame-indexed prepare.

The Mac lane ports this with AVAssetTrack format-description extensions
(port notes in contract s34).
"""
import json
import subprocess

HDR_TRANSFERS = {"smpte2084", "arib-std-b67", "smpte428"}   # PQ, HLG, 428
DV_CODEC_TAGS = {"dvhe", "dvh1", "dvav", "dva1"}
# canonical matrix names we pass to ffmpeg scale in_color_matrix
MATRIX_CANON = {"bt709": "bt709", "bt470bg": "bt470bg", "smpte170m": "smpte170m",
                "fcc": "fcc", "bt2020nc": "bt2020nc", "bt2020_ncl": "bt2020nc",
                "bt2020c": "bt2020c", "chroma-derived-nc": "bt470bg",
                "iec61966-2-1": None}   # sRGB 'matrix': not a YCbCr matrix

VFR_REL_TOL = 0.002     # |r_frame_rate - avg_frame_rate| beyond this = VFR
GRID_MIN_SAMPLES = 30   # 195k: below this the sample-grid check abstains, metadata guard stands


def sample_grid_cfr(deltas_ms, tick_ms=1.0):
    """Whole-timeline cumulative grid. Never accept dropped-frame or mixed cadence."""
    import math
    if len(deltas_ms) < GRID_MIN_SAMPLES:
        return None
    if not math.isfinite(tick_ms) or tick_ms < 0 or any(not math.isfinite(d) or d <= 0 for d in deltas_ms):
        return False
    g = sum(deltas_ms) / len(deltas_ms)
    if not math.isfinite(g) or g <= 1 or g > 1000:
        return False
    eps = max(tick_ms, 1.0)
    elapsed = 0.0
    for i, d in enumerate(deltas_ms, 1):
        elapsed += d
        if abs(d - g) > eps or abs(elapsed - i * g) > eps:
            return False
    return True


def sample_deltas(video_path):
    """PTS metadata only, no decoding. Scan full timeline, including late cadence changes."""
    pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                         "-show_entries", "packet=pts_time", "-of", "json", video_path],
                        capture_output=True, text=True)
    try:
        pts = [float(p["pts_time"]) for p in json.loads(pr.stdout)["packets"] if "pts_time" in p]
    except Exception:
        return []
    pts.sort()
    return [(b - a) * 1000.0 for a, b in zip(pts, pts[1:])]


def _rate(s):
    try:
        n, d = s.split("/")
        return float(n) / float(d) if float(d) else 0.0
    except Exception:
        return 0.0


def _sar(s):
    try:
        n, d = s.split(":")
        return float(n) / float(d) if float(d) else 1.0
    except Exception:
        return 1.0


def bit_depth(pix_fmt):
    """Bit depth from the ffmpeg pixel-format name."""
    f = (pix_fmt or "").lower()
    for b in (16, 14, 12, 10, 9):
        if "p%d" % b in f or "gbrp%d" % b in f:
            return b
    if "gray16" in f or "rgb48" in f or "rgba64" in f:
        return 16
    return 8


def probe(video_path):
    """One ffprobe read -> normalized fact dict for the first video stream."""
    # -show_streams (full): ffmpeg 4.4's show_entries has no side-data selector
    pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                         "-show_streams", "-of", "json", video_path],
                        capture_output=True, text=True)
    st = json.loads(pr.stdout)["streams"][0]
    rot = 0
    for sd in st.get("side_data_list", []):
        if "rotation" in sd:
            rot = int(round(float(sd["rotation"])))
            break
    if rot == 0 and st.get("tags", {}).get("rotate"):
        rot = int(round(float(st["tags"]["rotate"])))
    rot = (-rot) % 360      # ffprobe reports counter-clockwise; store clockwise
    tag = (st.get("codec_tag_string") or "").lower()
    profile = (st.get("profile") or "").lower()
    dv = tag in DV_CODEC_TAGS or "dolby" in profile
    r, avg = _rate(st.get("r_frame_rate", "0/1")), _rate(st.get("avg_frame_rate", "0/1"))
    deltas = sample_deltas(video_path)
    grid = sample_grid_cfr(deltas)
    vfr = (not grid) if grid is not None else (r > 0 and avg > 0 and abs(r - avg) / max(r, avg) > VFR_REL_TOL)
    return {
        "width": int(st["width"]), "height": int(st["height"]),
        "pix_fmt": st.get("pix_fmt", ""), "bit_depth": bit_depth(st.get("pix_fmt", "")),
        "color_range": st.get("color_range") or "unknown",
        "color_space": st.get("color_space") or "unknown",
        "color_transfer": st.get("color_transfer") or "unknown",
        "color_primaries": st.get("color_primaries") or "unknown",
        "sar": _sar(st.get("sample_aspect_ratio", "1:1")),
        "sar_str": st.get("sample_aspect_ratio", "1:1"),
        "dar_str": st.get("display_aspect_ratio", ""),
        "rotation": rot,
        "r_fps": r, "avg_fps": avg, "vfr": vfr, "grid_cfr": grid,
        "dolby_vision": dv, "codec_tag_string": tag, "profile": profile,
    }


def matrix_for(p):
    """YCbCr->RGB matrix the chain uses for this source.

    Tagged -> the tag. Untagged -> the size rule AVFoundation and mpv both
    apply (HD bt709, SD bt601-family); bt470bg and smpte170m decode
    identically for practical content and swscale's untagged default is
    bt470bg, so the SD fallback is bt470bg (= swscale default: no golden
    drift)."""
    t = p["color_space"]
    if t in MATRIX_CANON and MATRIX_CANON[t]:
        return MATRIX_CANON[t]
    return "bt709" if (p["width"] >= 1280 or p["height"] > 576) else "bt470bg"


def normalized_size(p):
    """Display size the chain must present: square pixels, rotation applied.

    SAR scales width first, then a 90/270 rotation swaps the axes."""
    w = int(round(p["width"] * p["sar"]))
    h = p["height"]
    if p["rotation"] in (90, 270):
        w, h = h, w
    return (w, h)


def verdicts(p):
    """Per-dimension verdict list: (dimension, status, detail)."""
    out = []
    bd = p["bit_depth"]
    out.append(("bit_depth", "ok" if bd >= 10 else "note",
                f"{bd}-bit {p['pix_fmt']}" + ("" if bd >= 10 else
                " (8-bit kept end-to-end; 10-bit sources must NOT be read at 8-bit - banding)")))
    rng = p["color_range"]
    if rng == "pc":
        out.append(("range", "note", "full range: tags pass through to the proxy; "
                    "every decode must honour the range flag (reference does via stream tags)"))
    elif rng == "tv":
        out.append(("range", "ok", "limited/video range"))
    else:
        out.append(("range", "note", "range untagged: consumers assume limited (tv)"))
    mx = p["color_space"]
    if mx in MATRIX_CANON and MATRIX_CANON[mx]:
        out.append(("matrix", "ok", f"tagged {mx}"))
    else:
        out.append(("matrix", "warn", f"matrix untagged ({mx}): assuming {matrix_for(p)} by size rule "
                    "(AVFoundation/mpv do the same); tag the source to override"))
    pr = p["color_primaries"]
    if pr in ("bt709", "unknown", "unspecified"):
        out.append(("primaries", "ok" if pr == "bt709" else "note", f"primaries {pr}"))
    elif pr in ("smpte432", "bt2020"):
        out.append(("primaries", "note", f"primaries {pr}: gamut wider than sRGB; SDR chain converts "
                    "matrix only, wide-gamut colours clip at the rgba8 render - acceptable for SDR transfers, see hdr_transfer"))
    else:
        out.append(("primaries", "note", f"primaries {pr}"))
    tr = p["color_transfer"]
    if tr in HDR_TRANSFERS or (p["color_primaries"] == "bt2020" and tr in HDR_TRANSFERS):
        out.append(("hdr_transfer", "refuse", f"HDR transfer {tr}: 3D prepare refuses; play 2D. "
                    "HDR is never silently tone-clipped"))
    else:
        out.append(("hdr_transfer", "ok", f"transfer {tr}"))
    if p["dolby_vision"]:
        out.append(("dolby_vision", "refuse", f"Dolby Vision ({p['codec_tag_string']} {p['profile']}): "
                    "prepare refuses; play 2D (RPU reshaping is out of scope)"))
    else:
        out.append(("dolby_vision", "ok", "not Dolby Vision"))
    out.append(("chroma", "note", "4:2:0: chroma bled by the SOURCE encoder is baked in; the chain must "
                "not add more (left-sited upsample, no chroma resample across depth edges)"))
    odd = (p["width"] & 1) or (p["height"] & 1)
    out.append(("odd_size", "note" if odd else "ok",
                f"{p['width']}x{p['height']}" + (" odd: proxy pads black bottom-right to even, depth edge-pads; sidecar carries the unpadded size" if odd else "")))
    if abs(p["sar"] - 1.0) > 1e-3:
        nw, nh = normalized_size(p)
        out.append(("sar", "fix", f"anamorphic sar {p['sar_str']}: normalize to square pixels {nw}x{nh} "
                    "BEFORE depth and proxy so both see display geometry"))
    else:
        out.append(("sar", "ok", "square pixels"))
    if p["rotation"]:
        nw, nh = normalized_size(p)
        out.append(("rotation", "fix", f"display matrix rotation {p['rotation']} CW: normalize to {nw}x{nh}; "
                    "depth input and proxy must BOTH be rotated (ffmpeg autorotates; cv2 and VT do not)"))
    else:
        out.append(("rotation", "ok", "no rotation"))
    if p["vfr"]:
        how = ("samples off the average-delta grid" if p.get("grid_cfr") is False
               else f"r_frame_rate {p['r_fps']:.3f} != avg {p['avg_fps']:.3f}")
        out.append(("vfr", "refuse", f"VFR: {how}; "
                    "frame-indexed prepare assumes CFR - transcode to CFR first (or play 2D)"))
    else:
        out.append(("vfr", "ok", "CFR (sample-grid consistent)" if p.get("grid_cfr") else "CFR"))
    return out


def refuse_reasons(p):
    """The refuse verdicts, or [] when prepare may run."""
    return [d for _, s, d in verdicts(p) if s == "refuse"]


def rgb_decode_scale(p):
    """Explicit scale-filter arg for YCbCr->RGB decodes of this source.

    Untagged streams get the size-rule matrix explicitly (identical to
    swscale's default for SD, but pinned against ffmpeg-version drift and
    fixed for HD-untagged, where swscale would still default to bt470bg
    while AVFoundation/mpv assume bt709); tagged streams pass through with
    in_color_matrix=auto."""
    mx = p["color_space"]
    if mx in MATRIX_CANON and MATRIX_CANON[mx]:
        return "scale=in_color_matrix=auto"
    return f"scale=in_color_matrix={matrix_for(p)}"
