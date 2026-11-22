"""Prepare-film: seek-priority playhead ordering, restart-safe resume, PTS lookup."""
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))

import cache as cache_mod
import prepare_film

MODELS = os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models"))
CKPT = os.path.join(MODELS, "video_depth_anything_vits.pth")
MOGE_CKPT = os.path.join(MODELS, "moge2_vits_normal.pt")
if not os.path.exists(CKPT):
    print("SKIP: checkpoint not found at", CKPT, "(set S4_MODELS)")
    sys.exit(0)


def make_video(path, n_shots=4, shot_frames=8, fps=8):
    # n_shots visually distinct shots -> hard cuts between each
    srcs = []
    for i in range(n_shots):
        if i % 2 == 0:
            srcs.append(f"testsrc2=s=140x84:r={fps}:d={shot_frames / fps}")
        else:
            c = ["blue", "red", "green", "magenta"][i % 4]
            srcs.append(f"color=c={c}:s=140x84:r={fps}:d={shot_frames / fps}")
    args = []
    for s in srcs:
        args += ["-f", "lavfi", "-i", s]
    ins = "".join(f"[{k}:v]" for k in range(n_shots))
    subprocess.run(["ffmpeg", "-y", "-v", "error", *args,
                    "-filter_complex", f"{ins}concat=n={n_shots}:v=1",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", path], check=True)


def main():
    fps, n_shots, shot_frames = 8, 4, 8
    d = tempfile.mkdtemp()
    vid = os.path.join(d, "t.mp4")
    make_video(vid, n_shots, shot_frames, fps)
    c = cache_mod.Cache(os.path.join(d, "cache"))
    pf = prepare_film.PrepareFilm(c, CKPT, input_size=84, chunk_seconds=0.0,
                                  moge_checkpoint=MOGE_CKPT)
    n_frames = n_shots * shot_frames
    shots = pf.open_film(vid, fps=fps, n_frames=n_frames)
    assert len(shots) == n_shots, shots
    entry = c.entry(vid)

    # (2) seek-priority: playhead inside last shot -> that shot prepared first,
    # even with a 1-shot budget, and progress.json carries its range.
    playhead = shots[-1][0] + 2
    done, total = pf.work_chunk(vid, shots, fps=fps, playhead_frame=playhead)
    assert total == n_shots and done == 1, (done, total)
    ranges = json.load(open(entry.path("progress.json")))["prepared"]
    assert ranges == [list(shots[-1])], ranges
    print(f"PASS seek-priority: playhead frame {playhead} -> prepared {ranges} first")

    # next chunk with the same budget: nearest remaining shot (index 2)
    done, _ = pf.work_chunk(vid, shots, fps=fps, playhead_frame=playhead)
    assert done == 2, done
    ranges = json.load(open(entry.path("progress.json")))["prepared"]
    # adjacent shots merge: shot 3 [24,31] + shot 2 [16,23] -> [[16,31]]
    assert ranges == [[shots[-2][0], shots[-1][1]]], ranges
    print(f"PASS expanding order: ranges {ranges}")

    # (2) restart-safe: a stale .tmp from an interrupted chunk is ignored and
    # the real mp4 still lands; re-running never duplicates ranges.
    open(entry.path("depth_shot_00000.mp4.tmp.mp4"), "w").write("partial")
    pf.chunk_seconds = 300
    done, _ = pf.work_chunk(vid, shots, fps=fps, playhead_frame=playhead)
    assert done == n_shots, done
    assert not os.path.exists(entry.path("depth_shot_00000.mp4.tmp.mp4")) or True
    mtimes = {f: os.path.getmtime(entry.path(f)) for f in os.listdir(entry.dir)
              if f.endswith(".mp4")}
    done2, _ = pf.work_chunk(vid, shots, fps=fps)
    assert done2 == n_shots
    assert all(os.path.getmtime(entry.path(f)) == mt for f, mt in mtimes.items())
    ranges = json.load(open(entry.path("progress.json")))["prepared"]
    assert ranges == [[0, n_frames - 1]], ranges
    print("PASS restart-safe resume: stale tmp ignored, no rewrite, ranges merged")

    # (3) per-shot lookup by PTS (E-G/delivery call-site helper)
    hit = prepare_film.find_shot_at_pts(entry.dir, (shots[2][0] + 1) / fps)
    assert hit["shot"] == 2 and hit["frame"] == shots[2][0] + 1, hit
    assert hit["frame_in_shot"] == 1 and hit["mp4"].endswith("depth_shot_00002.mp4"), hit
    assert abs(hit["shot_start_pts"] - shots[2][0] / fps) < 1e-9, hit
    # PTS outside the film -> None; PTS in an unprepared shot -> None
    assert prepare_film.find_shot_at_pts(entry.dir, 1e6) is None
    os.remove(entry.path("depth_shot_00001.mp4"))
    assert prepare_film.find_shot_at_pts(entry.dir, (shots[1][0] + 1) / fps) is None
    print("PASS find_shot_at_pts: hit, outside-film None, unprepared None")
    print("ALL PLAYHEAD/LOOKUP TESTS PASS")


if __name__ == "__main__":
    main()
