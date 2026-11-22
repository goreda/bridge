#!/usr/bin/env python3
"""s39 pins: the dress rehearsal produces the Mac first-run artefact set
and selftest_check accepts the log end to end (CONTRACT-190v s39).

Runs rehearsal.py at 12 frames (fast) into a temp dir. Clips default to
live,cg; REHEARSAL_TEST_CLIPS subsets them (this box runs one clip per
invocation under the 2-minute shell budget; both halves must pass).

Run: python3 Tests/DepthAnalysis/test_rehearsal.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
REH = os.path.join(ROOT, "tools", "depth_analysis", "rehearsal.py")

# SKIP (not fail) off-box: the rehearsal needs the MoGe repo + checkpoint,
# the VDA ONNX stream and the e2 clips (same guard style as test_moge.py)
MODELS = os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models"))
if not os.path.exists(os.path.join(MODELS, "moge2_vits_normal.pt")):
    print("SKIP: MoGe checkpoint not found under", MODELS, "(set S4_MODELS)")
    sys.exit(0)
if not all(os.path.exists(os.path.join(MODELS, f))
           for f in ("vda-stream-encoder_fp16.onnx",
                     "vda-stream-bootstrap_fp16.onnx",
                     "vda-stream-stream_fp16.onnx")):
    print("SKIP: VDA stream ONNX export not found under", MODELS)
    sys.exit(0)
if not os.path.exists(os.environ.get("MOGE_REPO",
                                     os.path.expanduser("~/s4/190t/moge"))):
    print("SKIP: MOGE_REPO clone not found (set MOGE_REPO)")
    sys.exit(0)
try:
    import moge  # noqa: F401
except ImportError:
    sys.path.insert(0, os.environ.get("MOGE_REPO",
                                      os.path.expanduser("~/s4/190t/moge")))
    try:
        import moge  # noqa: F401
    except ImportError:
        print("SKIP: moge module not importable (MOGE_REPO)")
        sys.exit(0)
if not all(os.path.exists(p) for p in
           ("/home/sandbox/s4/e2/clips/live.mp4",
            "/home/sandbox/s4/e2/clips/anim.mp4")):
    print("SKIP: e2 clips not present on this box")
    sys.exit(0)

out = tempfile.mkdtemp(prefix="s39_test_")
clips = os.environ.get("REHEARSAL_TEST_CLIPS", "live,cg")
r = subprocess.run([sys.executable, REH, "--out", out, "--frames", "12",
                    "--clips", clips], capture_output=True, text=True)
assert r.returncode == 0, r.stdout[-1500:] + r.stderr[-1500:]
for c in clips.split(","):
    assert f"== {c}: selftest_check exit 0" in r.stdout, r.stdout
assert "REHEARSAL PASS" in r.stdout

for c in clips.split(","):
    cdir = os.path.join(out, c)
    for fn in ("gor3d-selftest.log", "shot0.dzc", "align_track.json",
               "render_full_sbs.mp4", "render_vr180.mp4",
               "render_key_v4.txt"):
        p = os.path.join(cdir, fn)
        assert os.path.isfile(p) and os.path.getsize(p) > 0, p

    log = open(os.path.join(cdir, "gor3d-selftest.log")).read()
    # the exact line families the first Mac run must carry (contract s39)
    for needle in ("gor3d-selftest v1 begin ",
                   "note key=clip value=640x360 12f @24.0",
                   "stage name=clip_write ", "stage name=prepare_total ",
                   "stage name=render_shot ",
                   "note key=moge_precision value=",
                   "note key=first_3d_frame_sha256 value=",
                   "note key=rt_config value=fps=24.0",
                   "rtstage name=vda ", "rtstage name=moge ",
                   "rtstage name=upsample ", "rtstage name=surround ",
                   "rtstage name=render ", "rtstage name=vt_decode ",
                   "rtstage name=vt_encode ",
                   "thermal_peak level=", "depth min=", " end errors=0",
                   "note key=jitter_rel value=",
                   "note key=render_key_v4 value=v4|",
                   "3dfsm from=READY_STEREO ev=playhead_uncovered to=LGD_HOLD",
                   "3dfsm from=INIT ev=probe_ok to=PREPARING_FLAT"):
        assert needle in log, (c, needle)
    assert "SYNTHETIC-TIMING" in log and "thermal_source value=synthetic" in log

    aj = json.load(open(os.path.join(cdir, "align_track.json")))
    assert aj["weighted_ema"] and aj["kf_stride"] == 12 and aj["track"]
    keys = dict(l.split(" ", 1) for l in
                open(os.path.join(cdir, "render_key_v4.txt")).read().splitlines())
    assert set(keys) == {"full_sbs", "vr180"}
    assert all(v.startswith("v4|mlbw_l2_inpaint_video|comfort|") for v in keys.values())

    sys.path.insert(0, os.path.join(ROOT, "tools", "depth_analysis"))
    import depth_container
    info = depth_container.read_info(os.path.join(cdir, "shot0.dzc"))
    assert info["n_frames"] == 12, info

man = json.load(open(os.path.join(out, "manifest.json")))
for c in clips.split(","):
    assert f"{c}/gor3d-selftest.log" in man
    assert f"{c}/shot0.dzc" in man
print(f"PASS test_rehearsal ({clips})")
