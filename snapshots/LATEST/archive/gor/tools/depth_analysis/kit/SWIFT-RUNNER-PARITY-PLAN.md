# Swift-runner per-stage parity plan (190w X2 follow-on, owner bar 14:50)

Owner bar: the 2D->3D feature must be flawless, a breakthrough in the field. Gate = reference-vs-gor
numeric comparison at EVERY stage; no quality claim without numbers. Each stage names its reference,
its metric and where the evidence lands. A stage that has not posted numbers is not done.

## S0 Weights integrity
- Reference: models.lock per-file rows (7 nunif weights, sha256+bytes, releases/0.0.0) + kit tar
  content_sha256 (kit_hash.py canonical algorithm).
- Metric: exact sha256 match per file at load time; fail closed.
- Evidence: load log line per file (id + sha prefix).

## S1 Pre-model pipeline (channel build, hole mask, delta convention, feature values, gaussian k15 sigma=2.6)
- Reference: tools/depth_analysis/kit/nunif_pipeline_reference.py + nunif_pipeline_fixture.npz
  (numpy reference of nunif's pre/post-model math, landed f695e393).
- Metric: max-abs per tensor vs fixture at the runner's own working precision; postprocess_hole_mask
  closing/dilation params must match the reference exactly (contract s: MASK_MLBW_THRESHOLD 0.15).
- Evidence: per-tensor max-abs table posted with the runner PR.

## S2 Per-package model parity (CoreML vs torch)
- Reference: the kit's *_fixture.npz (seeded in_*, torch fp32 out_*) at each package boundary
  (NUNIF-COREML-RUNNER-CONTRACT.md "Parity fixtures").
- Metric: max abs diff per output (contract wording) + PSNR for image outputs. fp16 packages are
  expected to deviate; post the measured numbers, do not pre-claim a pass threshold.
- Evidence: table of package x output x (max-abs, PSNR).

## S3 Video windowing (T1)
- Reference: numpy window semantics (SEQ_LEN 12, 3+3 pre/post, step 6, edge-clamped tail), confirmed
  vs BaseVideoInpaint and mirrored in Tests/NunifMath.
- Metric: window boundary indices + overlap blend weights exact vs reference; per-frame output
  equality with S2 within fp16 tolerance.
- Evidence: boundary table for a 48-frame input (windows at 0,6,...,42 + tail), blend weight dump.

## S4 End-to-end render parity (gor vs iw3 reference)
- Reference: tools/depth_analysis/kit/x2_tos_reference/ (iw3 PyTorch renders of the ToS 48f 320x180
  clip at divergence 2.0, convergence 1.0 + the exact normalized depth fixture npz).
- Metric: per-frame PSNR + max-abs of gor's T1/T2/T3 renders vs tos_t1/t2/t3 references; report the
  distribution, not the best frame. CRITICAL: depth must be per-frame minmax normalized to [0,1]
  before the warp (iw3 default, SimpleMinMaxScaler) — raw VDA range (0.045..16.6) striping is the
  known failure mode.
- Evidence: metric table + one side-by-side frame per tier.

## S5 Temporal + artifact metrics (owner-issue F1-F3 fixes land here)
- Smear: fill-run length p95 and band flat-fraction per frame (baseline from the owner screenshot:
  runs to 130px, flat-frac 85% in outer bands — but that shot was vr180-look on a 2D frame, so the
  dibr baselines must be re-measured on a true fallback render).
- Temporal: d2 jitter p95 on a static scene (s30 precedent), plus fill-run boundary stability.
- Depth strength: per-shot disparity span (p95-p5, degrees) on the ToS clip; comfort budget math vs
  tools/depth_analysis/comfort.py.
- Evidence: before/after numbers per fix, no fix merges without them.

## S6 Owner gate
- Numbers from S0-S5 posted; owner reviews on his Mac. No go-live, no quality claims before.
