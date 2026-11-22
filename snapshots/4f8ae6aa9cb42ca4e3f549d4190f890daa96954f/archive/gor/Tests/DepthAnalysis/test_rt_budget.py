"""Real-time budget model pins (CONTRACT-190v s31).

Pins the s31 model (tools/depth_analysis/rt_budget.py): stage op
counts, per-frame ms at 24/30/60 fps for the 2D->VR180 (16:9 MoGe) and
native VR180 (per-eye MoGe) paths, the MoGe keyframe burst, the
breaking stage, and that the proposed fixes (half-rate depth with s30
eased hold + footprint-restricted surround + pipelined keyframes) put
the worst case back inside budget WITHOUT touching Tier-1 quality
(the model carries no quality knob: fixes only reschedule compute).

Run: python3 Tests/DepthAnalysis/test_rt_budget.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))

import rt_budget as rt  # noqa: E402


def main():
    # op counts
    assert abs(rt.VDA_STREAM_GFLOP - 21.2497) < 0.01, rt.VDA_STREAM_GFLOP
    assert rt.MOGE_GFLOP_KF_169 == 74.0 and rt.MOGE_GFLOP_KF_VR180 == 148.0
    assert rt.SURROUND_OPT_GFLOP < rt.SURROUND_NAIVE_GFLOP
    print(f"PASS op counts: VDA stream {rt.VDA_STREAM_GFLOP:.2f} GFLOP, "
          f"surround {rt.SURROUND_NAIVE_GFLOP:.2f} -> "
          f"{rt.SURROUND_OPT_GFLOP:.2f} GFLOP")

    # MoGe keyframe burst (the frame-drop risk at any fps if serialized)
    b169, bvr = rt.keyframe_burst_ms(False), rt.keyframe_burst_ms(True)
    assert abs(b169 - 28.6) < 0.5, b169
    assert abs(bvr - 114.6) < 1.0, bvr
    assert bvr > 1000.0 / 24.0, "VR180 burst exceeds a 24fps frame: must pipeline"
    print(f"PASS keyframe burst: 16:9 {b169:.1f} ms, VR180 {bvr:.1f} ms "
          f"(> 24fps frame: pipelining mandatory)")

    # per-frame fit, 2D->VR180 (16:9 MoGe): fits at all rates as-is
    for fps in (24.0, 30.0, 60.0):
        m = rt.per_frame_ms(fps, vr180=False)
        assert m["total"] <= 1000.0 / fps, (fps, m)
    m24 = rt.per_frame_ms(24.0, vr180=False)
    assert abs(m24["total"] - 11.0) < 0.2, m24
    print(f"PASS 2D->VR180 fits 24/30/60 as-is "
          f"(24fps total {m24['total']:.1f} ms)")

    # native VR180: 60 fps breaks as-is; the fixes restore it
    m60 = rt.per_frame_ms(60.0, vr180=True)
    assert abs(m60["total"] - 18.1) < 0.2, m60
    assert m60["total"] > 1000.0 / 60.0, "60fps VR180 must break as-is"
    # breaking stage = the two model stages, not IO or post
    assert m60["vda"] > m60["post"] and m60["moge_amortized"] > m60["post"]
    assert m60["vda"] + m60["moge_amortized"] > 1000.0 / 60.0 - m60["post"]
    m60f = rt.per_frame_ms(60.0, vr180=True, depth_rate=30.0,
                           surround_optimized=True)
    assert abs(m60f["total"] - 9.1) < 0.2, m60f
    assert m60f["total"] <= 1000.0 / 60.0, "fixed 60fps VR180 must fit"
    print(f"PASS VR180 60fps: {m60['total']:.1f} ms BREAKS as-is, "
          f"{m60f['total']:.1f} ms FITS with half-rate depth + opt surround")

    # thermal: sustained watts below the serious-onset anchor everywhere
    for fps in (24.0, 30.0, 60.0):
        for vr in (False, True):
            w, tf = rt.sustained_watts(fps, vr)
            assert w < rt.SERIOUS_ONSET_W, (fps, vr, w)
    w60, tf60 = rt.sustained_watts(60.0, True)
    assert abs(w60 - 4.3) < 0.15, w60
    print(f"PASS thermal: worst sustained {w60:.1f}W ({tf60:.2f} TFLOPS) "
          f"< {rt.SERIOUS_ONSET_W}W serious onset")

    # audit table shape
    rows = rt.audit(True)
    assert len(rows) == 6 and [r["fps"] for r in rows] == [24.0]*2 + [30.0]*2 + [60.0]*2
    assert rows[4]["fits"] is False and rows[5]["fits"] is True
    print("PASS audit table: 60fps VR180 as-is BREAKS, fixed FITS")
    print("ALL RT BUDGET TESTS PASS")


if __name__ == "__main__":
    main()
