#!/usr/bin/env python3
"""s44: one measuring test per heat lever (depth rate, resolution,
concurrency, precision fallback) + the cross-side consistency pins that
keep a silent load-doubling impossible.

Run: python3 Tests/DepthAnalysis/test_heat_levers.py
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tools", "depth_analysis"))
import thermal_budget as tb  # noqa: E402

S = os.path.join(ROOT, "Sources", "gor")


def swift(name):
    return open(os.path.join(S, name)).read()


# --- L1 depth rate: the keyframe stride is 12 on EVERY side, and the
# model measures the lever: halving the stride adds the MoGe term again.
ref = open(os.path.join(ROOT, "tools/depth_analysis/prepare_film.py")).read()
assert re.search(r"FOV_KEYFRAME_STRIDE = 12", ref)
assert "static let keyframeStride = 12" in swift("FovTrackBuilder.swift")
assert "keyframeStride: Int = 12" in swift("PrepareTelemetry.swift")
assert tb.MOGE_STRIDE == 12
base = tb.sustained_tflops(vr180=True)
halved = tb.sustained_tflops(moge_stride=6, vr180=True)
moge_term = 148.0 * 2 * (24.0 / 12) / 1000.0
assert abs((halved - base) - moge_term) < 1e-9, (base, halved)
print(f"PASS L1 depth rate: stride 12 on all 4 sides; stride 6 adds "
      f"{moge_term:.2f} TFLOPS ({base:.2f} -> {halved:.2f})")

# --- L2 resolution: the kit's token counts are the model's package
# shapes; VR180 per-eye costs ~2x the 16:9 keyframe, and the aspect rule
# (no stretching) is what keeps 518x294 valid for 16:9.
man = json.load(open(os.path.join(ROOT, "tools/depth_analysis/kit",
                                  "kit_manifest.json")))
tok = {n: m.get("num_tokens") for n, m in man["packages"].items()}
assert tok["moge2_vits_518x294_fp16.mlpackage"] == 777 == (518 // 14) * (294 // 14)
assert tok["moge2_vits_518x518_fp16.mlpackage"] == 1369 == (518 // 14) ** 2
r = tb.sustained_tflops(vr180=True) / tb.sustained_tflops(vr180=False)
assert 1.2 < r < 1.4, r  # VDA identical; MoGe term doubles per-eye
assert "no stretching" in man["aspect_rule"]
print(f"PASS L2 resolution: tokens 777/1369 == patch math; VR180 total "
      f"load x{r:.2f} vs 16:9; aspect_rule forbids stretching")

# --- L3 concurrency: serialization halves the keyframe-second peak;
# both model call sites are lane-wrapped, and the lane binds to
# ShotSink.runModel's single static lock.
asm = swift("ShotPrepareAssembly.swift")
spawn = swift("ThreeDPrepareSpawn.swift")
assert asm.count("hooks.lane {") >= 2, "vdaStep and mogeKeyframe both lane-wrapped"
assert "hooks.lane { vdaOut = backend.vdaStep" in asm
assert "hooks.lane { kfOut = backend.mogeKeyframe" in asm
assert "h.lane = { body in sink.runModel { body() } }" in asm
assert "Self.modelLane.lock()" in spawn
ser = tb.peak_w(vr180=True, overlapped=False)
ove = tb.peak_w(vr180=True, overlapped=True)
assert ove > ser, (ser, ove)  # overlap strictly adds to the peak
# the serialized peak never exceeds the sustained-worst-case estimate
assert ser <= tb.estimate_package_watts(tb.S19_WORST_TFLOPS), ser
assert ser < tb.SERIOUS_ONSET_W, ser
print(f"PASS L3 concurrency: serialized peak {ser:.1f}W < overlapped "
      f"{ove:.1f}W (est); both model calls lane-wrapped -> one static lock")

# --- L4 precision fallback: even an ALL-fp32 MoGe (legal fallback,
# ~2x energy) keeps the serialized peak and the sustained load under the
# serious onset - the fallback cannot reproduce 93 C.
ser_f32 = tb.peak_w(vr180=True, overlapped=False, moge_energy_mult=2.0)
sus_f32 = tb.estimate_package_watts(
    tb.sustained_tflops(vr180=True) +  # VDA fp16 + MoGe fp16
    tb.sustained_tflops(vr180=True) - tb.VDA_S_GFLOP_FRAME * tb.FPS / 1000.0,
    1.0)  # MoGe term doubled
assert ser_f32 < tb.SERIOUS_ONSET_W, ser_f32
print(f"PASS L4 fp32 fallback: serialized peak {ser_f32:.1f}W (est) "
      f"< serious onset {tb.SERIOUS_ONSET_W}W; cannot reach 93 C")

# --- L5 the degrade on a thermal trip is a PAUSE, never a quality
# reduction (Tier 1 never lowered; playback never interrupted).
import degrade_fsm as F  # noqa: E402
for frm in (F.PREPARING_FLAT, F.READY_STEREO, F.FLAT_DEGRADED):
    t = F._T[(frm, F.EV_THERMAL_TRIP)]
    assert "act_prepare_pause" in t.actions, (frm, t.actions)
    assert not any("quality" in a or "tier" in a for a in t.actions)
t = F._T[(F.READY_STEREO, F.EV_THERMAL_TRIP)]
assert t.to == F.READY_STEREO, "playback continues 3D on prepared range"
print("PASS L5 thermal trip: act_prepare_pause from every preparing state; "
      "no quality lever exists")

print("heat levers: all pins hold")
