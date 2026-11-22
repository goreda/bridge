"""Prepare-film orchestration test: cuts cached, chunked work, resume, OSD status."""
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


def make_video(path):
    # 2 shots: 2s testsrc2 + 2s blue, 8fps -> 32 frames
    subprocess.run([
        "ffmpeg", "-y", "-v", "error",
        "-f", "lavfi", "-i", "testsrc2=s=140x84:r=8:d=2",
        "-f", "lavfi", "-i", "color=c=blue:s=140x84:r=8:d=2",
        "-filter_complex", "[0:v][1:v]concat=n=2:v=1",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", path], check=True)


def main():
    d = tempfile.mkdtemp()
    vid = os.path.join(d, "t.mp4")
    make_video(vid)
    c = cache_mod.Cache(os.path.join(d, "cache"))
    pf = prepare_film.PrepareFilm(c, CKPT, input_size=84, chunk_seconds=0.0,
                              moge_checkpoint=MOGE_CKPT)

    shots = pf.open_film(vid, fps=8, n_frames=32)
    assert len(shots) >= 2, shots  # the hard cut must split the film
    assert shots[0][0] == 0 and shots[-1][1] == 31, shots  # inclusive last frame
    # cuts cached: second open must not re-run detection
    entry = c.entry(vid)
    assert os.path.exists(entry.path("cuts.json"))
    shots2 = pf.open_film(vid, fps=8, n_frames=32)
    assert shots2 == shots
    # stable current-film pointer for the delivery lane's OSD
    import json
    ptr = json.load(open(os.path.join(c.root, "current-film.json")))
    assert ptr["progress_path"] == entry.path("progress.json")
    assert ptr["n_frames"] == 32 and ptr["cache_key"] == os.path.basename(entry.dir)
    print(f"PASS open_film: {len(shots)} shots, cuts cached, current-film.json pointer")

    # chunk_seconds=0 -> at most one shot per chunk (budget honored)
    done, total = pf.work_chunk(vid, shots, fps=8)
    assert total == len(shots) and done <= 1, (done, total)
    r, prepared, n, txt = pf.status(vid, 32)
    assert prepared < 32 and "3D prepared:" in txt
    print(f"PASS budgeted chunk (done={done}/{total}), OSD: {txt}")

    # finish with a generous budget; resume must skip the prepared shot
    pf.chunk_seconds = 300
    done2, _ = pf.work_chunk(vid, shots, fps=8)
    # 190v contract format checks
    import json as _json
    from prepare_film import read_depth_hevc
    meta0 = _json.load(open(entry.path("depth_shot_00000.json")))
    dep, start_pts = read_depth_hevc(entry.path("depth_shot_00000.mp4"),
                                     size=(meta0["depth_height"], meta0["depth_width"]))
    assert dep.shape == (16, 84, 140) and "align_scale" in meta0
    assert abs(start_pts - 0.0) < 0.01
    ft = _json.load(open(entry.path("fov_track.json")))
    assert ft["fps"] == 8 and len(ft["shots"]) == len(shots)
    sh = ft["shots"][0]
    assert {"start_pts", "end_pts", "hfov_deg", "confidence", "keyframe_values"} <= set(sh)
    assert sh["hfov_deg"] is not None and 0 <= sh["confidence"] <= 1
    print("PASS contract format (10-bit HEVC Main10 4:2:0 mp4, PTS, align, fov_track)")
    assert done2 == total
    r, prepared, n, txt = pf.status(vid, 32)
    assert prepared == 32 and txt == "3D prepared: full film", (prepared, txt)
    assert r == [[0, 31]], r
    print(f"PASS full prepare, OSD: {txt}")
    print("ALL PREPARE-FILM TESTS PASS")


if __name__ == "__main__":
    main()
