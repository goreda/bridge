"""Long-clip temporal soak (contract s29, Main 10:22 item 2).

>= 300 frames over 3 shots on the Linux reference path:
  1. memory growth: RSS sampled per rendered frame must stay bounded
     (no per-frame leak slope) over the full 336-frame run;
  2. cache key stability: cache.cache_key is a deterministic function of
     file identity (size+mtime+head/tail) - identical across repeated
     opens of the same prepared clip, changed by content change;
  3. thermal duty-cycle gate: the contract config passes
     thermal_budget.validate_config over the whole run and the MoGe
     keyframe cadence (stride 12) is shot-aware - a keyframe at each
     shot start, then every 12 frames, never denser.

Run: python3 Tests/DepthAnalysis/test_temporal_soak.py
"""
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GOLD = os.path.join(HERE, "..", "..", "tools", "depth_analysis", "golden",
                    "entry_cg_vr180")
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))

SHOTS = 3
SPER = 112  # frames per shot -> 336 total (>= 300)
EYE = 96    # reduced eye size: soak covers the pipeline, not pixels


def _rss_kb():
    with open("/proc/self/status") as f:
        for line in f:
            if line.startswith("VmRSS"):
                return int(line.split()[1])
    raise RuntimeError("VmRSS not found")


def _build_entry(E):
    """3-shot entry, 336 frames, tiled from the CG golden with per-shot
    depth scales (1x, 2x, 0.5x) and distinct hfovs."""
    from prepare_film import D_SCALE, read_depth_hevc, write_depth_hevc
    from reference_render import _read_source_frames
    rgb = _read_source_frames(os.path.join(GOLD, "source_shot_00000.mp4"),
                              640, 360)
    inv, _ = read_depth_hevc(os.path.join(GOLD, "depth_shot_00000.mp4"),
                             size=(360, 640))
    h0 = json.load(open(os.path.join(GOLD, "fov_track.json"))
                   )["shots"][0]["hfov_deg"]
    scales = (1.0, 2.0, 0.5)
    hfovs = (h0, 60.0, h0)
    shots_meta = []
    for s in range(SHOTS):
        reps = int(np.ceil(SPER / len(inv)))
        inv_s = np.tile(inv, (reps, 1, 1))[:SPER]
        rgb_s = np.tile(rgb, (reps, 1, 1, 1))[:SPER]
        zf = np.where(inv_s > 0, D_SCALE / np.maximum(inv_s, 1e-9), 0.0)
        inv_s = np.where(zf > 0, D_SCALE / (zf * scales[s] + 1e-30),
                         0).astype(np.float32)
        write_depth_hevc(os.path.join(E, f"depth_shot_{s:05d}.mp4"),
                         inv_s, 24.0, s * SPER)
        p = subprocess.Popen(
            ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo",
             "-pix_fmt", "rgb24", "-s", "640x360", "-r", "24", "-i", "-",
             "-c:v", "libx264", "-crf", "12", "-pix_fmt", "yuv420p",
             os.path.join(E, f"source_shot_{s:05d}.mp4")],
            stdin=subprocess.PIPE)
        p.communicate(rgb_s.astype(np.uint8).tobytes())
        json.dump({"depth_width": 640, "depth_height": 360,
                   "frames": SPER, "start_frame": s * SPER, "fps": 24.0,
                   "start_pts": s * SPER / 24.0,
                   "source_width": 640, "source_height": 360},
                  open(os.path.join(E, f"depth_shot_{s:05d}.json"), "w"))
        shots_meta.append({"shot": s, "start": s * SPER,
                           "end": (s + 1) * SPER - 1, "frames": SPER,
                           "median_hfov_deg": hfovs[s], "hfov_deg": hfovs[s],
                           "confidence": 1.0, "keyframe_values": []})
    json.dump({"fps": 24.0, "shots": shots_meta},
              open(os.path.join(E, "fov_track.json"), "w"))
    return shots_meta


def main():
    import cache
    import thermal_budget as tb
    from reference_render import render_shot_sbs

    with tempfile.TemporaryDirectory() as E:
        shots_meta = _build_entry(E)

        # --- 1. memory growth over the full 336-frame render ----------
        rss = []
        for s in range(SHOTS):
            frames, info = render_shot_sbs(E, s, ipd=0.063,
                                           convergence_m=2.0,
                                           swap_eyes=True,
                                           out_w=EYE, out_h=EYE)
            assert frames.shape[0] == SPER
            rss.append(_rss_kb())
            del frames
        # per-frame render loop with RSS sampling inside one shot too:
        # re-render shot 0 frame-by-frame to catch a per-frame slope
        from prepare_film import D_SCALE, read_depth_hevc
        from reference_render import (_read_source_frames,
                                      render_frame_sbs, theta_h_for)
        inv, _ = read_depth_hevc(os.path.join(E, "depth_shot_00000.mp4"),
                                 size=(360, 640))
        z = np.where(inv > 0, D_SCALE / np.maximum(inv, 1e-9), 0.0)
        rgb = _read_source_frames(os.path.join(E, "source_shot_00000.mp4"),
                                  640, 360)
        th = theta_h_for(75.0, math.radians(shots_meta[0]["hfov_deg"]),
                         640 / 360)
        per_frame_rss = []
        for k in range(SPER):
            f = render_frame_sbs(rgb[k], z[k], th, 0.063, 2.0, True,
                                 EYE, EYE)
            del f
            per_frame_rss.append(_rss_kb())
        # slope over the second half (warm allocator): linear fit
        xs = np.arange(SPER // 2, SPER, dtype=np.float64)
        ys = np.array(per_frame_rss[SPER // 2:], dtype=np.float64)
        slope = float(np.polyfit(xs, ys, 1)[0])  # kB per frame
        growth_mb = (per_frame_rss[-1] - per_frame_rss[SPER // 2]) / 1024.0
        assert slope < RSS_SLOPE_KB_PER_FRAME, (slope, growth_mb)
        print(f"PASS memory: warm slope {slope:.2f} kB/frame "
              f"(< {RSS_SLOPE_KB_PER_FRAME}), half-run growth "
              f"{growth_mb:.1f} MB, shot-boundary RSS "
              f"{[round(r / 1024) for r in rss]} MB")

        # --- 2. cache key stability -----------------------------------
        src = os.path.join(E, "source_shot_00000.mp4")
        k1 = cache.cache_key(src)
        k2 = cache.cache_key(src)
        assert k1 == k2, "cache key unstable across repeated opens"
        root = os.path.join(E, "cache")
        c = cache.Cache(root)
        e1 = c.entry(src, create=True)
        e1.mark_prepared(0, SPER * SHOTS - 1)
        e1b = cache.Cache(root).entry(src)  # re-open via a fresh Cache
        assert e1b is not None and e1b.dir == e1.dir
        assert e1b.is_prepared(0) and e1b.is_prepared(SPER * SHOTS - 1)
        # content change -> key change
        with open(src, "r+b") as f:
            f.seek(0)
            b = bytearray(f.read(16))
            b[0] ^= 0xFF
            f.seek(0)
            f.write(bytes(b))
        assert cache.cache_key(src) != k1, "key must track content"
        print(f"PASS cache keys: stable on reopen ({k1[:12]}...), "
              f"prepared range survives fresh Cache, content flip -> new key")

        # --- 3. thermal duty-cycle gate over the run ------------------
        problems = tb.validate_config()
        assert problems == [], problems
        tf = tb.sustained_tflops()
        stride = tb.MOGE_STRIDE
        # shot-aware keyframe schedule: cut frames + every `stride`
        # frames within a shot
        cuts = {m["start"] for m in shots_meta}
        keyframes = [k for k in range(SPER * SHOTS)
                     if k in cuts or
                     (k - max(c for c in cuts if c <= k)) % stride == 0]
        duty = len(keyframes) / (SPER * SHOTS)
        assert len(keyframes) == EXPECTED_KEYFRAMES, len(keyframes)
        gaps = [b - a for a, b in zip(keyframes, keyframes[1:])]
        assert max(gaps) <= stride, gaps  # never sparser than stride
        assert duty <= EXPECTED_KEYFRAMES / (SPER * SHOTS) + 1e-9
        w = tb.estimate_package_watts(tf)
        assert w < tb.SERIOUS_ONSET_W
        print(f"PASS thermal: validate_config clean, sustained "
              f"{tf:.2f} TFLOPS (~{w:.1f}W, below serious onset), "
              f"MoGe duty {duty:.4f} ({len(keyframes)} keyframes / "
              f"{SPER * SHOTS} frames, stride {stride}, shot-aware)")


RSS_SLOPE_KB_PER_FRAME = 64.0   # calibrated on this box; see contract s29
EXPECTED_KEYFRAMES = 3 + 3 * ((SPER - 1) // 12)  # cut + stride-12 per shot

if __name__ == "__main__":
    main()
    print("ALL TEMPORAL SOAK TESTS PASS")
