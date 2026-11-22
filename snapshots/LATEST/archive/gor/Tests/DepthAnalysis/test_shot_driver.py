"""End-to-end shot driver: cuts -> depth+proxy, playhead-ordered from start
PTS, render-ready.json sidecar (ready flags, failures), failure capture +
retry, resume-safe. Moving content."""
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


def make_video(path, w=140, h=84, fps=8):
    # 3 shots, all moving content
    subprocess.run([
        "ffmpeg", "-y", "-v", "error",
        "-f", "lavfi", "-i", f"testsrc2=s={w}x{h}:r={fps}:d=1",
        "-f", "lavfi", "-i", f"smptehdbars=s={w}x{h}:r={fps}:d=1",
        "-f", "lavfi", "-i", f"testsrc2=s={w}x{h}:r={fps}:d=1:rate={fps}",
        "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", path], check=True)


def main():
    fps, n_frames = 8, 24
    d = tempfile.mkdtemp()
    vid = os.path.join(d, "t.mp4")
    make_video(vid, fps=fps)
    c = cache_mod.Cache(os.path.join(d, "cache"))
    pf = prepare_film.PrepareFilm(c, CKPT, input_size=84, chunk_seconds=300,
                                  moge_checkpoint=MOGE_CKPT)

    # playhead-ordered from a start PTS in the LAST shot: it becomes ready first
    pf.chunk_seconds = 0.0  # one shot per chunk
    shots = pf.open_film(vid, fps=fps, n_frames=n_frames)
    assert len(shots) == 3, shots
    pf.work_chunk(vid, shots, fps=fps, playhead_frame=int(2.5 * fps))
    doc = json.load(open(c.entry(vid).path("render-ready.json")))
    ready = [r["shot"] for r in doc["shots"] if r["ready"]]
    assert ready == [2], doc
    assert doc["n_ready"] == 1 and doc["n_failed"] == 0
    row = doc["shots"][2]
    assert row["depth_ready"] and row["source_ready"] and row["error"] is None
    print(f"PASS drive ordering: start_pts 2.5s -> shot 2 ready first; sidecar rows ok")

    # failure capture: poison shot 0's depth write, then run the rest
    orig = prepare_film.write_depth_hevc
    def poison(path, inv, fps_, start):
        if start == shots[0][0]:
            raise RuntimeError("boom")
        return orig(path, inv, fps_, start)
    prepare_film.write_depth_hevc = poison
    pf.chunk_seconds = 300
    try:
        pf.work_chunk(vid, shots, fps=fps, playhead_frame=int(2.5 * fps))
    finally:
        prepare_film.write_depth_hevc = orig
    doc = json.load(open(c.entry(vid).path("render-ready.json")))
    by = {r["shot"]: r for r in doc["shots"]}
    assert by[0]["failed"] and "boom" in by[0]["error"], by[0]
    assert by[1]["ready"] and by[2]["ready"]
    assert not os.path.exists(c.entry(vid).path("depth_shot_00000.mp4"))
    print("PASS failure capture: shot 0 failed+boom, others ready, no partial file")

    # retry clears the failure (shot 0 was never marked prepared)
    pf.work_chunk(vid, shots, fps=fps)
    doc = json.load(open(c.entry(vid).path("render-ready.json")))
    assert doc["n_ready"] == 3 and doc["n_failed"] == 0, doc
    assert all(r["ready"] and not r["failed"] and r["error"] is None
               for r in doc["shots"])
    print("PASS retry: failed shot recovered, sidecar clean")

    # drive() end to end on a FRESH cache: resume-safe, idempotent
    c2 = cache_mod.Cache(os.path.join(d, "cache2"))
    pf2 = prepare_film.PrepareFilm(c2, CKPT, input_size=84, chunk_seconds=300,
                                   moge_checkpoint=MOGE_CKPT)
    done, total, doc = pf2.drive(vid, fps, n_frames, start_pts=1.0)
    assert (done, total) == (3, 3) and doc["n_ready"] == 3, (done, total, doc)
    done2, total2, doc2 = pf2.drive(vid, fps, n_frames, start_pts=1.0)
    assert done2 == 3 and doc2["n_ready"] == 3
    print("PASS drive(): end-to-end ready, idempotent rerun")
    print("ALL SHOT-DRIVER TESTS PASS")


if __name__ == "__main__":
    main()
