"""Source proxy (source_shot_NNNNN.mp4): VT-readable HEVC, native res,
frame-accurate PTS pairing with the depth mp4, resume covers proxy-only gaps."""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np

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
    # 2 shots, moving content so adjacent frames differ measurably
    subprocess.run([
        "ffmpeg", "-y", "-v", "error",
        "-f", "lavfi", "-i", f"testsrc2=s={w}x{h}:r={fps}:d=2",
        "-f", "lavfi", "-i", f"smptehdbars=s={w}x{h}:r={fps}:d=2",
        "-filter_complex", "[0:v][1:v]concat=n=2:v=1",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", path], check=True)


def grab(video, frame, w, h):
    # YUV420 domain: the honest fidelity metric for the proxy - VT decodes
    # source and proxy through the SAME converter on the Mac, so RGB-domain
    # diffs here would only measure swscale 8/10-bit conversion asymmetry.
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", video,
                          "-vf", f"select='eq(n\\,{frame})'", "-frames:v", "1",
                          "-f", "rawvideo", "-pix_fmt", "yuv420p", "-"],
                         capture_output=True)
    a = np.frombuffer(out.stdout, dtype=np.uint8)
    assert a.size == w * h * 3 // 2, (a.size, w, h)
    return a.astype(np.int16)


def psnr(a, b):
    mse = ((a.astype(np.float64) - b.astype(np.float64)) ** 2).mean()
    return 99.0 if mse == 0 else 10 * np.log10(255.0 ** 2 / mse)


def main():
    w, h, fps = 140, 84, 8
    d = tempfile.mkdtemp()
    vid = os.path.join(d, "t.mp4")
    make_video(vid, w, h, fps)
    c = cache_mod.Cache(os.path.join(d, "cache"))
    pf = prepare_film.PrepareFilm(c, CKPT, input_size=84, chunk_seconds=300,
                                  moge_checkpoint=MOGE_CKPT)
    shots = pf.open_film(vid, fps=fps, n_frames=32)
    done, total = pf.work_chunk(vid, shots, fps=fps)
    assert done == total, (done, total)
    entry = c.entry(vid)

    for i, (s, e) in enumerate(shots):
        p = entry.path(f"source_shot_{i:05d}.mp4")
        assert os.path.exists(p), p
        pr = json.loads(subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=codec_name,profile,pix_fmt,width,height,nb_frames",
             "-of", "json", p], capture_output=True, text=True).stdout)["streams"][0]
        assert pr["codec_name"] == "hevc" and "Main 10" in pr["profile"], pr
        assert pr["pix_fmt"] == "yuv420p10le", pr
        assert int(pr["nb_frames"]) == e - s + 1, pr
        assert int(pr["width"]) == w + (w & 1) and int(pr["height"]) == h + (h & 1), pr
        pk = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                             "-show_entries", "packet=pts_time", "-of", "csv",
                             "-read_intervals", "%+#1", p],
                            capture_output=True, text=True).stdout
        start = float(pk.strip().splitlines()[0].split(",")[1])
        assert abs(start - s / fps) < 0.01, (i, start, s / fps)
        # frame-accurate + high fidelity: proxy frame 1 == source frame s+1
        if e - s >= 1:
            a = grab(p, 1, w, h)
            same = psnr(a, grab(vid, s + 1, w, h))
            offby = psnr(a, grab(vid, min(s + 2, e), w, h))
            maxabs = int(np.abs(a - grab(vid, s + 1, w, h)).max())
            assert same > 45.0 and maxabs <= 8, (i, same, maxabs)  # transparent feed
            moving = psnr(grab(vid, s + 1, w, h), grab(vid, min(s + 2, e), w, h)) < 45.0
            if moving:  # static shots make the off-by-one probe meaningless
                assert same > offby + 3.0, (i, same, offby)  # not an off-by-one frame
        meta = json.load(open(entry.path(f"depth_shot_{i:05d}.json")))
        assert meta["source_width"] == w and meta["source_height"] == h, meta
    print(f"PASS source proxy: hevc Main10 mp4, native {w}x{h}, PTS-paired, "
          f"PSNR ok, sidecar dims")

    # PTS pairing with the depth file: same shot -> identical start PTS
    d0 = prepare_film.read_depth_hevc(entry.path("depth_shot_00000.mp4"))[1]
    hit = prepare_film.find_shot_at_pts(entry.dir, (shots[0][0] + 1) / fps)
    assert hit["source_mp4"] and hit["source_mp4"].endswith("source_shot_00000.mp4"), hit
    assert abs(d0 - shots[0][0] / fps) < 0.01
    print("PASS PTS pairing + find_shot_at_pts source_mp4")

    # resume with only the proxy missing: depth mp4 untouched, proxy rewritten
    victim = 1 if len(shots) > 1 else 0
    os.remove(entry.path(f"source_shot_{victim:05d}.mp4"))
    dmt = os.path.getmtime(entry.path(f"depth_shot_{victim:05d}.mp4"))
    done, _ = pf.work_chunk(vid, shots, fps=fps)
    assert done == total and os.path.exists(entry.path(f"source_shot_{victim:05d}.mp4"))
    assert os.path.getmtime(entry.path(f"depth_shot_{victim:05d}.mp4")) == dmt
    print("PASS resume: proxy-only gap refilled, depth not rewritten")
    print("ALL SOURCE-PROXY TESTS PASS")


if __name__ == "__main__":
    main()
