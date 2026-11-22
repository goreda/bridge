"""s45 visible-quality regression gate: rerun the quality_bar pipeline on
the e2 clips and fail if any viewer-facing metric worsens beyond the
measured noise margin (quality_bar.MARGINS) against the committed
baseline (tools/depth_analysis/quality_baseline.json). Skips when the
models or clips are unavailable (like test_moge.py)."""
import argparse
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..",
                                "tools", "depth_analysis"))

MODELS = os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models"))
CLIPS = {"live": os.path.expanduser("~/s4/e2/clips/live.mp4"),
         "cg": os.path.expanduser("~/s4/e2/clips/anim.mp4"),
         "dark": os.path.expanduser("~/s4/e2/clips/dark.mp4")}
BASELINE = os.path.join(os.path.dirname(__file__), "..", "..",
                        "tools", "depth_analysis", "quality_baseline.json")

_need = [os.path.join(MODELS, "moge2_vits_normal.pt"),
         os.path.join(MODELS, "vda-stream-encoder_fp16.onnx"),
         os.path.join(MODELS, "vda-stream-stream_fp16.onnx"),
         BASELINE] + list(CLIPS.values())
_missing = [p for p in _need if not os.path.exists(p)]
if not os.path.exists(os.environ.get(
        "MOGE_REPO", os.path.expanduser("~/s4/190t/moge"))):
    _missing.append("MOGE_REPO clone")
if _missing:
    print("SKIP: missing", _missing[0], "(set S4_MODELS)")
    sys.exit(0)
try:
    import onnxruntime  # noqa: F401
    import torch  # noqa: F401
except ImportError as e:
    print("SKIP:", e)
    sys.exit(0)

import quality_bar  # noqa: E402

work = tempfile.mkdtemp(prefix="qbar-test-")
for clip in sorted(CLIPS):
    # live/cg resolve through rehearsal.CLIPS (keeping their baseline
    # names); dark goes by path and is named by its basename
    src = clip if clip in quality_bar.CLIPS else CLIPS[clip]
    quality_bar.cmd_prepare(argparse.Namespace(
        clip=src, work=work, frames=24, proxy_w=640, models=MODELS))
quality_bar.cmd_measure(argparse.Namespace(work=work, md=None))
rc = quality_bar.cmd_check(argparse.Namespace(work=work, baseline=BASELINE))
if rc:
    print("FAIL test_quality_bar: a viewer-facing metric regressed past "
          "its noise margin (see above)")
    sys.exit(1)
print("PASS test_quality_bar")
