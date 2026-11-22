#!/usr/bin/env python3
"""190y X2 goreda lane: S5 smear/artifact metrics for SBS stereo renders (parity plan S5).

Definitions (pinned here so every lane measures the same thing):
- input: SBS video/still, any size; each half is one synthesized eye.
- smear run: maximal horizontal run of pixels where max(|dR|,|dG|,|dB|) to the previous
  pixel in the row <= TOL (uint8 codes, TOL=1). Fill smears from warping are long flat runs.
- outer band: the outer BAND=15% of columns of each eye half (the hole-fill region at
  divergence 2.0 on 320-wide eyes = up to ~0.02*320/2 px geometry, band covers it).
- per frame per eye: fill-run p95 (95th percentile of run lengths in the outer band),
  band flat-fraction (fraction of outer-band pixels inside runs of length >= 8).
Output: JSON per input: frames, per-eye p95 mean/min/max, flat-fraction mean.
Usage: s5_artifact_metrics.py <video-or-png> [...]  (needs ffmpeg for compressed inputs)
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

TOL = 1
BAND = 0.15
MINRUN = 8


def load_frames(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo",
                          "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                            "-show_entries", "stream=width,height", "-of", "csv=p=0",
                            str(path)], capture_output=True, check=True, text=True).stdout.strip()
    w, h = (int(x) for x in probe.split(","))
    return np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3)


def eye_metrics(eye):  # eye [H,W,3] uint8
    h, w, _ = eye.shape
    bw = max(1, int(round(w * BAND)))
    # runs where pixel equals previous within TOL
    p95s, flats = [], []
    for bandimg in (eye[:, :bw], eye[:, w - bw:]):
        d = np.abs(bandimg[:, 1:].astype(np.int16) - bandimg[:, :-1].astype(np.int16)).max(axis=2)
        s = d <= TOL
        runs = []
        flat = 0
        for row in s:
            # run lengths of True (plus 1 for the starting pixel)
            padded = np.concatenate(([False], row, [False]))
            edges = np.flatnonzero(np.diff(padded.astype(np.int8)))
            lens = edges[1::2] - edges[0::2] + 1
            runs.append(lens)
            flat += int(lens[lens >= MINRUN].sum())
        r = np.concatenate(runs) if runs else np.array([0])
        p95s.append(float(np.percentile(r, 95)))
        flats.append(flat / (h * bw))
    return {"p95_left": p95s[0], "p95_right": p95s[1],
            "flat_left": flats[0], "flat_right": flats[1]}


def main(paths):
    out = {}
    for p in paths:
        p = Path(p)
        if p.suffix == ".png":
            with tempfile.NamedTemporaryFile(suffix=".mp4") as t:
                subprocess.run(["ffmpeg", "-v", "error", "-loop", "1", "-frames:v", "1",
                                "-i", str(p), "-c:v", "libx264", "-pix_fmt", "yuv420p", t.name, "-y"],
                               check=True)
                frames = load_frames(t.name)
        else:
            frames = load_frames(p)
        w = frames.shape[2]
        eyes = {"L": frames[:, :, :w // 2], "R": frames[:, :, w // 2:]}
        per = [eye_metrics(eyes[e][i]) for e in ("L", "R") for i in range(frames.shape[0])]
        # merge: each frame produced entries for both eyes; regroup by frame
        lf = per[0:frames.shape[0]]
        rf = per[frames.shape[0]:]
        def agg(rows, k):
            v = np.array([r[k] for r in rows])
            return {"mean": round(float(v.mean()), 3), "max": round(float(v.max()), 3)}
        out[p.name] = {
            "frames": int(frames.shape[0]),
            "p95_left": agg(lf, "p95_left"), "p95_right": agg(lf, "p95_right"),
            "flat_left": agg(lf, "flat_left"), "flat_right": agg(lf, "flat_right"),
            "defs": {"TOL": TOL, "BAND": BAND, "MINRUN": MINRUN},
        }
        print("measured", p.name, file=sys.stderr, flush=True)
    print(json.dumps(out, indent=1))
    return out


if __name__ == "__main__":
    main(sys.argv[1:])
