"""Thermal budget model + 93C audit (CONTRACT-190v s19).

Executable form of the s19 op-count budget plus the audit of the owner
93 C finding, derived from the budget ONLY (the owner gor thermal log is
not available to this lane; Main 08:31). All power figures are coarse
public-ballpark estimates for fanless M1/M2 and are labelled estimates;
the LOAD side is the s19 analytical op count and is exact.

Units: GFLOP per inference, TFLOPS sustained, watts package.
"""

# --- s19 measured/analytical op counts (do not edit without s19) ---
VDA_S_GFLOP_FRAME = 79.0        # VDA-S stream @518x294, 777 tokens
MOGE_GFLOP_KF_169 = 74.0        # MoGe-2 keyframe @518x294
MOGE_GFLOP_KF_VR180 = 148.0     # MoGe-2 @518x518, PER EYE (s19: both eyes -> 0.59 TFLOPS at stride 12)
FPS = 24.0
MOGE_STRIDE = 12                # contract keyframe stride
S19_WORST_TFLOPS = 2.5          # s19 total worst case (VR180 per-eye)

# --- coarse fanless M1-class power anchors (ESTIMATES, audit-only) ---
ANE_TOPS_FP16 = 11.0            # M1 ANE peak
ANE_PEAK_W = 2.5                # est. package watts at ANE peak
GPU_TFLOPS_FP16 = 2.6           # M1 GPU fp16 peak
GPU_PEAK_W = 11.0               # est. package watts at GPU peak
MISC_W = 1.0                    # CPU <5% + VT decode + rest-of-SoC, est.
SERIOUS_ONSET_W = 6.0           # est. sustained package where fanless
                                # M1/M2 approaches thermalState serious
                                # (warm ambient, charging); 93 C sits
                                # past serious, toward critical
# s19 unit split: ANE ~75% of FLOPs, GPU spill ~20%, CPU <5%
ANE_SHARE, GPU_SHARE = 0.75, 0.20


def sustained_tflops(vda_fps=FPS, moge_stride=MOGE_STRIDE, vr180=True):
    """Sustained compute load of a prepare config, TFLOPS.

    vda_fps: VDA-S stream rate (every source frame). moge_stride: one
    MoGe-2 keyframe pass per N frames. vr180: per-eye 518x518 MoGe
    packages (both eyes) instead of the 16:9 package."""
    vda = VDA_S_GFLOP_FRAME * vda_fps / 1000.0
    moge_per_kf = MOGE_GFLOP_KF_VR180 if vr180 else MOGE_GFLOP_KF_169
    eyes = 2.0 if vr180 else 1.0
    moge = moge_per_kf * eyes * (vda_fps / moge_stride) / 1000.0
    return vda + moge


def estimate_package_watts(tflops, energy_mult=1.0):
    """Coarse sustained package power for a compute load (ESTIMATE).
    energy_mult: >1 for fp32 or .cpuAndGPU configs (no ANE fp16 path,
    ~2x energy per FLOP on the GPU)."""
    ane = ANE_SHARE * tflops / ANE_TOPS_FP16 * ANE_PEAK_W
    gpu = GPU_SHARE * tflops / GPU_TFLOPS_FP16 * GPU_PEAK_W
    return (ane + gpu) * energy_mult + MISC_W


def audit_93c():
    """The 93C case against the s19 budget. Returns row dicts.

    Reading: 93 C package on fanless Apple silicon is past the serious
    onset (throttling). A config only reaches it if its sustained load
    is a large multiple of the s19 worst case."""
    rows = []
    cases = [
        ("s19 contract config (stride 12, serialized, fp16)",
         sustained_tflops(vr180=True), 1.0),
        ("s19 config, 16:9 source (stride 12)",
         sustained_tflops(vr180=False), 1.0),
        ("VIOLATION: MoGe every frame (stride 1), VR180 per-eye",
         sustained_tflops(moge_stride=1, vr180=True), 1.0),
        ("VIOLATION: MoGe every frame (stride 1), 16:9",
         sustained_tflops(moge_stride=1, vr180=False), 1.0),
        ("VIOLATION: stride 4 + VR180 per-eye",
         sustained_tflops(moge_stride=4, vr180=True), 1.0),
        ("VIOLATION: stride 1 VR180 + fp32/.cpuAndGPU (~2x energy)",
         sustained_tflops(moge_stride=1, vr180=True), 2.0),
    ]
    for name, tf, mult in cases:
        w = estimate_package_watts(tf, mult)
        rows.append({
            "case": name,
            "tflops": round(tf, 2),
            "x_s19_worst": round(tf / S19_WORST_TFLOPS, 2),
            "package_w_est": round(w, 1),
            "vs_serious_onset": "below" if w < SERIOUS_ONSET_W
                                else "AT/ABOVE",
        })
    return rows


def peak_w(vda_fps=FPS, moge_stride=MOGE_STRIDE, vr180=True,
           overlapped=False, moge_energy_mult=1.0):
    """PEAK package power estimate during a keyframe second (ESTIMATE).

    The concurrency lever: with the s19 serialization rule (one model
    lane, ShotSink.runModel) VDA-S and MoGe-2 never run at once, so the
    peak is the larger single-model load; overlapped execution sums
    them. moge_energy_mult=2 models the fp32 fallback package (legal,
    ~2x energy per FLOP).
    """
    vda_tf = VDA_S_GFLOP_FRAME * vda_fps / 1000.0
    moge_per_kf = MOGE_GFLOP_KF_VR180 if vr180 else MOGE_GFLOP_KF_169
    eyes = 2.0 if vr180 else 1.0
    # a keyframe costs its GFLOPs once per stride; during its second the
    # instantaneous MoGe draw is the per-keyframe cost (one pass) spread
    # over ~1 s
    moge_tf_peak = moge_per_kf * eyes / 1000.0 * moge_energy_mult
    if overlapped:
        return estimate_package_watts(vda_tf + moge_tf_peak)
    return estimate_package_watts(max(vda_tf, moge_tf_peak))


def validate_config(vda_fps=FPS, moge_stride=MOGE_STRIDE, vr180=True):
    """Prepare config guard: reject anything over the s19 budget."""
    tf = sustained_tflops(vda_fps, moge_stride, vr180)
    problems = []
    if tf > S19_WORST_TFLOPS + 1e-9:
        problems.append(
            f"estimated sustained load {tf:.2f} TFLOPS exceeds the s19 "
            f"budget {S19_WORST_TFLOPS} TFLOPS")
    if moge_stride < MOGE_STRIDE:
        problems.append(
            f"MoGe keyframe stride {moge_stride} < contract {MOGE_STRIDE}")
    return problems


if __name__ == "__main__":
    print("93C audit (derived from the s19 budget only; power = estimate)")
    for row in audit_93c():
        print(f"  {row['case']}: {row['tflops']} TFLOPS "
              f"({row['x_s19_worst']}x s19), ~{row['package_w_est']}W, "
              f"{row['vs_serious_onset']} serious onset")
