"""Real-time budget model for the Mac playback path (CONTRACT-190v s31).

Fanless M1 Air, live (unprepared) 2D -> VR180 playback. Per-stage
FLOPs/bytes from the s19 op counts, the kit package shapes and the
s28/s24 stage definitions; per-frame ms at 24/30/60 fps on M1 GPU+ANE
anchors. Every anchor is an explicit assumption below - the LOAD side
is analytical, the M1 UTILIZATION side is a stated estimate, and
nothing here is a Mac measurement (owner-Mac verification pending).

Units: GFLOP, MB, ms, W.
"""

# --- hardware anchors (ASSUMPTIONS, fanless M1) -----------------------
ANE_TOPS_FP16 = 11.0       # M1 ANE peak fp16
ANE_UTIL = 0.35            # sustained util for ViT-S-class fp16 packages
GPU_TFLOPS_FP16 = 2.6      # M1 GPU fp16 peak
GPU_UTIL = 0.40            # sustained util for mixed kernels
DRAM_GBS = 68.25           # M1 unified memory bandwidth
ANE_SHARE, GPU_SHARE = 0.75, 0.20  # CoreML .all split (s19); CPU <5%
VT_W = 0.5                 # VideoToolbox encode+decode package watts, est.
SERIOUS_ONSET_W = 6.0      # thermal_budget.py anchor (est.)

# --- stage op counts (analytical) -------------------------------------
# VDA-S streaming export is 154x266 (209 tokens; vda_stream_common).
# s19 counted the 518x294 (777-token) analysis shape at 79 GFLOP; FLOPs
# scale ~pixels for the conv bulk and ~tokens for the head, so the
# stream shape is ~79 * (154*266)/(518*294) = ~21 GFLOP (ASSUMPTION:
# proportional scaling; attention at 209 tokens is negligible either way).
VDA_S19_GFLOP = 79.0
VDA_PIXEL_RATIO = (154 * 266) / (518 * 294)
VDA_STREAM_GFLOP = VDA_S19_GFLOP * VDA_PIXEL_RATIO      # ~21.2
VDA_WEIGHTS_MB = 50.0    # ViT-S fp16, resident after first frame
VDA_ACT_MB = 40.0        # activations + temporal cache traffic, est.

MOGE_GFLOP_KF_169 = 74.0        # s19
MOGE_GFLOP_KF_VR180 = 148.0     # s19, per eye @518x518
MOGE_STRIDE = 12

# depth upsample (s24 inverse-plane bilinear) to 1280x720: ~10 ops/px
UPSAMPLE_GFLOP = 1280 * 720 * 10 / 1e9                  # ~0.009
UPSAMPLE_MB = 0.3 + 2 * 1.8                             # in + fp16 out eyes

# surround r4 per eye at 720x720 (s28): the 32-pass 3x3 pre-blur
# dominates. Naive full-frame: 32 * 9 taps * 3 ch * 518k px.
SURROUND_EYE_PX = 720 * 720
SURROUND_NAIVE_GFLOP = 32 * 9 * 3 * 2 * SURROUND_EYE_PX / 1e9   # ~0.90
# footprint-restricted + separable-box port (E-G note, s31): pre-blur
# only inside the footprint + 32px margin (~60% of the eye), and the
# multi-radius blur runs off ONE integral image (2 cumsum passes +
# 3 window reads, ~30 ops/px).
SURROUND_OPT_GFLOP = (32 * 9 * 3 * 2 * 0.6 * SURROUND_EYE_PX
                      + 30 * 2 * SURROUND_EYE_PX) / 1e9          # ~0.57
SURROUND_MB = 4 * 3 * SURROUND_EYE_PX * 4 / 1e6  # f32 ping-pong, ~25MB

# SBS render (DIBR warp + fill, s20/s27): ~25 ops + 2 samples per
# output px, both eyes.
RENDER_GFLOP = 25 * 2 * SURROUND_EYE_PX / 1e9                     # ~0.026
RENDER_MB = 2 * 2 * 3 * SURROUND_EYE_PX / 1e6                     # ~12MB

# HEVC proxy encode/decode: VideoToolbox dedicated silicon; zero
# GPU/ANE load, ~1-2 ms wall time off the compute path.
VT_MS = 2.0


def _ms(gflop):
    """Serialized ANE-share + GPU-share latency of a compute stage."""
    ane = ANE_SHARE * gflop / (ANE_TOPS_FP16 * ANE_UTIL)  # GFLOP/TFLOPS = ms
    gpu = GPU_SHARE * gflop / (GPU_TFLOPS_FP16 * GPU_UTIL)
    return ane + gpu


def per_frame_ms(fps=24.0, vr180=True, depth_rate=None,
                 surround_optimized=False):
    """Per-frame ms of the live path. depth_rate: VDA runs per second
    (None = every frame). MoGe amortized at the contract stride."""
    rate = depth_rate if depth_rate is not None else fps
    vda = _ms(VDA_STREAM_GFLOP) * (rate / fps)
    moge_per_kf = MOGE_GFLOP_KF_VR180 if vr180 else MOGE_GFLOP_KF_169
    eyes = 2.0 if vr180 else 1.0
    moge = _ms(moge_per_kf * eyes) * (rate / MOGE_STRIDE) / fps
    sg = SURROUND_OPT_GFLOP if surround_optimized else SURROUND_NAIVE_GFLOP
    post = _ms(UPSAMPLE_GFLOP + sg + RENDER_GFLOP)
    return {"vda": vda, "moge_amortized": moge, "post": post,
            "vt": VT_MS, "total": vda + moge + post}


def keyframe_burst_ms(vr180=True):
    """Wall latency of one MoGe keyframe (both eyes for VR180) - the
    per-frame table amortizes it; the burst is what can drop a frame."""
    g = MOGE_GFLOP_KF_VR180 * 2.0 if vr180 else MOGE_GFLOP_KF_169
    return _ms(g)


def sustained_watts(fps=24.0, vr180=True, depth_rate=None):
    """Sustained package watts (thermal_budget anchors, ESTIMATE)."""
    rate = depth_rate if depth_rate is not None else fps
    tf = (VDA_STREAM_GFLOP * rate
          + (MOGE_GFLOP_KF_VR180 if vr180 else MOGE_GFLOP_KF_169)
          * (2.0 if vr180 else 1.0) * (rate / MOGE_STRIDE)
          + (UPSAMPLE_GFLOP + SURROUND_OPT_GFLOP + RENDER_GFLOP) * fps) / 1000.0
    ane = ANE_SHARE * tf / ANE_TOPS_FP16 * 2.5
    gpu = GPU_SHARE * tf / GPU_TFLOPS_FP16 * 11.0
    return ane + gpu + 1.0 + VT_W, tf


def audit(vr180=True):
    """The s31 table: per-fps fit, breaking stage, headroom."""
    rows = []
    for fps in (24.0, 30.0, 60.0):
        budget = 1000.0 / fps
        m = per_frame_ms(fps, vr180)
        w, tf = sustained_watts(fps, vr180)
        rows.append({"fps": fps, "budget_ms": round(budget, 1),
                     "total_ms": round(m["total"], 1),
                     "fits": m["total"] <= budget,
                     "tflops": round(tf, 2), "watts_est": round(w, 1),
                     "thermal_ok": w < SERIOUS_ONSET_W})
        # fixes: depth at half rate + optimized surround
        m2 = per_frame_ms(fps, vr180, depth_rate=fps / 2,
                          surround_optimized=True)
        w2, tf2 = sustained_watts(fps, vr180, depth_rate=fps / 2)
        rows.append({"fps": fps, "budget_ms": round(budget, 1),
                     "total_ms": round(m2["total"], 1),
                     "fits": m2["total"] <= budget, "fixed": True,
                     "tflops": round(tf2, 2), "watts_est": round(w2, 1),
                     "thermal_ok": w2 < SERIOUS_ONSET_W})
    return rows


if __name__ == "__main__":
    print("s31 real-time budget (ASSUMPTIONS: ANE "
          f"{ANE_UTIL:.0%} of {ANE_TOPS_FP16} TOPS, GPU {GPU_UTIL:.0%} of "
          f"{GPU_TFLOPS_FP16} TFLOPS, VDA stream {VDA_STREAM_GFLOP:.1f} "
          "GFLOP/frame @154x266, MoGe 74 GFLOP/kf 16:9 / 148 GFLOP/kf/eye "
          "VR180, VT on dedicated silicon)")
    for vr in (False, True):
        mode = "VR180 native (per-eye MoGe)" if vr else "2D->VR180 (16:9 MoGe)"
        print(f"== {mode}; MoGe burst {keyframe_burst_ms(vr):.1f} ms")
        for r in audit(vr):
            tag = "FIXED " if r.get("fixed") else "as-is "
            print(f"  {r['fps']:.0f} fps {tag}: {r['total_ms']:.1f} ms / "
                  f"{r['budget_ms']:.1f} ms budget -> "
                  f"{'FITS' if r['fits'] else 'BREAKS'}; "
                  f"{r['tflops']} TFLOPS ~{r['watts_est']}W "
                  f"({'thermal ok' if r['thermal_ok'] else 'THERMAL RISK'})")


# --- s32: per-stage model expectations for the self-test verdict ------
RT_STAGES = ("vda", "moge", "upsample", "surround", "render",
             "vt_decode", "vt_encode")
# which model assumption a stage's deviation revises (s32 verdict table)
RT_ASSUMPTION = {
    "vda": "ANE util (VDA-S should be ANE-resident fp16; a high ratio "
           "says the compute plan fell back to GPU/CPU - check the plan)",
    "moge": "MoGe GFLOP/keyframe or package shape (518x294 16:9 vs "
            "518x518 per-eye VR180; check which package ran)",
    "upsample": "GPU util (post stages are small GPU kernels)",
    "surround": "GPU util (surround r4 kernels; check footprint "
                "restriction landed)",
    "render": "GPU util (SBS warp/fill kernel)",
    "vt_decode": "VT offload assumption (decode not on VideoToolbox?)",
    "vt_encode": "VT offload assumption (proxy preset/resolution)",
}


def expected_stage_ms(fps=24.0, vr180=False, depth_rate=None,
                      surround_optimized=False):
    """Modelled per-stage ms for the s32 self-test verdict (s31 anchors).
    vda/upsample/surround/render/vt_* are per-frame; moge is the
    per-keyframe burst (measured on keyframe frames only)."""
    rate = depth_rate if depth_rate is not None else fps
    sg = SURROUND_OPT_GFLOP if surround_optimized else SURROUND_NAIVE_GFLOP
    return {"vda": _ms(VDA_STREAM_GFLOP) * (rate / fps),
            "moge": keyframe_burst_ms(vr180),
            "upsample": _ms(UPSAMPLE_GFLOP),
            "surround": _ms(sg),
            "render": _ms(RENDER_GFLOP),
            "vt_decode": VT_MS / 2.0,
            "vt_encode": VT_MS / 2.0}
