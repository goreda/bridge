"""190t A: shot-cut detection (reference impl; Mac lane uses same thresholds).

Wraps ffmpeg scdet; returns sorted cut frame indices. Cut = frame where a new shot
starts. Every per-shot state (depth range EMA, FoV median, scale fit) resets there.
"""
import json, re, subprocess

SCDET_THRESHOLD = 12.0  # measured: separates hard cuts in ToS/Caminandes; fades stay uncut (by design)

def detect_cuts(video_path, fps, threshold=SCDET_THRESHOLD):
    """Return sorted list of cut frame indices for video_path at the given fps."""
    # s34: force 8-bit limited luma before scdet so 10/12/16-bit sources
    # score on the same scale the threshold was calibrated on (and the Mac
    # lane feeds its 8-bit video-range luma; scdet scores scale with bit
    # depth, so a 10-bit source would otherwise need a 4x threshold).
    cmd = ["ffmpeg", "-hide_banner", "-i", video_path,
           "-vf", f"format=yuv420p,scdet=threshold={threshold}", "-f", "null", "-"]
    out = subprocess.run(cmd, capture_output=True, text=True).stderr
    times = [float(m) for m in re.findall(r"lavfi\.scd\.time: ([0-9.]+)", out)]
    return sorted({int(t * fps + 0.5) for t in times})

def shots_from_cuts(n_frames, cuts):
    """[cut list] + frame count -> list of (first, last) frame ranges per shot."""
    bounds = [0] + [c for c in cuts if 0 < c < n_frames] + [n_frames]
    return [(bounds[i], bounds[i + 1] - 1) for i in range(len(bounds) - 1)]
