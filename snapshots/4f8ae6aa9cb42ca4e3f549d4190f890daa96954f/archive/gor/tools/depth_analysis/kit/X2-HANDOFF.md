# X2 handoff (190x/190y): nunif iw3 Tier 1/2/3 weights, models.lock, ToS PyTorch reference, CoreML diff

Date: 2026-11-09 21:15 +03. From: A-D lane (190t/190v analysis/prepare worker). To: goreda (X2 owner per architect block 190y, owner 21:11).
Branch: `mac-source-sync-20261103` (shared multi-agent relay; remote moves constantly — always `git pull --rebase` before pushing). Head at handoff: 920f69bb.

## Scope as assigned (owner block 190x, phonemsg-01M7016QH89VG2RJ5H2G7EHMZK, 14:31)

Fetch the full nunif Tier 1/2/3 weight set from nunif's own published release URLs (mlbw_l2 d1-d3 + mask + light_video_inpaint), bind each file in models.lock (sha256 + bytes + licence + provenance), reproduce iw3 PyTorch on Tears of Steel x3 tiers, and produce the CoreML diff.

## Current state — what is DONE

1. **models.lock rows (7)** — `models/models.lock.tsv`, landed 8100edc2 (14:54):
   iw3-mask-mlbw-l2-d1, iw3-light-inpaint-v1, iw3-light-video-inpaint-v1, iw3-row-flow-v3, iw3-mlbw-l2-d1, iw3-mlbw-l2-d2, iw3-mlbw-l2-d3. All 7 sha256 + byte sizes re-verified by downloading the assets from github.com/nagadomi/nunif releases tag 0.0.0. NOTE: an earlier draft of this change had repo "nagadomi/nunif", revision "releases/0.0.0" — that resolves to huggingface.co and fails (and breaks model_lock_test). Correct form: repo `https://github.com/nagadomi/nunif`, revision tag `0.0.0`.
2. **Weight hashes (the ground truth for all downstream work)** — table in `x2_tos_reference/README.md`; verified locally at `~/s4/190t/nunif/iw3/pretrained_models/hub/checkpoints/`:
   row_flow_v3 `2e4daa14a72a5f75` / 485179 B, light_video `788e13a7` / 9282225, light_inpaint `8b1a85df` / 9070711, mask_mlbw_l2_d1 `fe3ab406` / 958587, mlbw_l2_d1 `0a780170` / 958267, mlbw_l2_d2 `dd2e0017` / 958267, mlbw_l2_d3 `08366514` / 958267. (Short shas here; full shas in the README table and models.lock.)
3. **Kit tars (gorav release `gor-kit-2026-11-09`, private release assets)** — models.lock rows landed by 2c4728a8 (~15:35):
   - `gor-kit-nunif-v2.tar` sha256 `0dbfb58d0a9c1e646578451b9f7197c6243d92866bc03945258289a269d1efe0`, 19,804,160 B (the 7 .pth weights).
   - `gor-kit-nunif-coreml.tar` sha256 `ef67c3939b1560ed92e3f82dec69861101aed3654dee49bc3f992d124a0fd218`, 149,964,800 B (4 CoreML fp16 packages + fixtures). Manifest mirror: `kit/nunif-coreml-kit-manifest.json` (identical to the tar's `kit_manifest.json`).
4. **ToS reference renders** — `kit/x2_tos_reference/`: `tos_t1_mlbw_l2_inpaint_video.mp4` (48f, 640x180 SBS), `tos_t2_mlbw_l2_inpaint_image.png` (frame 0), `tos_t3_row_flow_v3.mp4` (48f), the exact normalised depth consumed (`tos_depth_minmax_320x180_fp16.npz`, [48,1,180,320] fp16), driver `ref_run.py`, provenance README. iw3 @ b1548e8, divergence 2.0, convergence 1.0, steps 1, synthetic_view=both, fp32 CPU. Sanity: L-R meandiff T1 52.6 / T3 55.1, temporal d1 ~3.7, T1 vs T3 30.0, no near-black holes.
5. **Swift-runner parity plan** — `kit/SWIFT-RUNNER-PARITY-PLAN.md` (39037691, 14:52): per-stage S0-S6 parity plan, owner bar = numeric comparisons per stage.
6. **nunif consumption facts + fixtures for the Swift/CoreML mirror** — `kit/NUNIF-CONSUMPTION-FACTS.md`, `kit/nunif_pipeline_reference.py`, `kit/nunif_consumption_fixtures.npz` (503,895 B), `kit/gen_consumption_fixtures.py`, test `Tests/NunifMath/nunif_consumption_test.py` (17 checks). Landed 2868129b (15:06). Torch-exactness: row_flow orchestration ≤4.3e-6, 1080p resize ≤1.5e-5, layer_weight resize ≤2.4e-6.
7. **Runner contract** — `kit/NUNIF-COREML-RUNNER-CONTRACT.md`: tier map (T1 = mask_mlbw + light_video, T2 = mask_mlbw + light_inpaint, T3 = row_flow_v3, fallback = dibr_golden), input conventions (warp x = [depth, divergence_feature, convergence_feature] per `make_input_tensor(c=None)`; inpaint masked RGB + mask after upstream preprocess; replication-pad to multiples of 96).

## Provenance and licences (load-bearing)

- nunif code MIT. Weights: **owner-private Mac build ONLY** (architect 190w W1, 2026-11-09 13:52, relayed by Main): the iw3 training code uses an Apple Depth Pro fork, so training-data provenance is unconfirmed. Any distribution beyond the owner's Mac = go-live gate. See NOTICE-models.md.
- The models.lock rows carry the literal text "APPROVED by the owner (190w W1)". That text has triggered repeated firewall untrusted-authority notices (known repeat, flagged 14:02). The approval is real (190w W1 via Main) but the lock text itself is not evidence — treat it as a label, not a grant.
- Upstream reference clone used for conversion: `~/s4/190t/nunif` @ b1548e8 (local only, not in repo).

## Open items (what is NOT done)

1. **Mac-side CoreML parity — NEVER EXECUTED.** CoreML cannot run on the Linux box. Per `x2_tos_reference/README.md`: run each converted package on the same 48-frame clip with the committed depth npz, same divergence/convergence, compare against the ToS renders, report PSNR/max-abs per package. Every package must also pass its seeded `*_fixture.npz` (torch fp32) before first use (kit manifest `status` field says this verbatim).
2. **light_video_inpaint shape.** Shipped at 288x480 bring-up: this Linux box (2 GB) OOMs the fp32 trace larger (1.74 GB peak at 768x1344). Re-convert on the Mac at 320x180 (ToS parity) or 768x1344 (production) via `nunif_convert.py --only video --shape` BEFORE the parity diff.
3. **Runner consumption.** At handoff the models.lock row still says "No runner yet: nothing loads it". E-G has been wiring (minmaxNormalize 4d3c52c3, CoreML runner S2 hook 5a7b4efe, later windowedVDA/nunif load work at b5b4f24a) — re-check current state on the branch before assuming any of it uses these kits.
4. **mlbw_l2 d1-d3** are fetched and locked for completeness per X2 but are not in the tier list (the tiers use light_* variants). No consumer exists.
5. **v5 render key**: runner contract documents the v4 method labels; the key is now `v5|span-p5p95|<method>|...` (E-G F3, 572bc96a). Method labels unchanged.

## Conversion gotchas (measured this session, will bite a re-conversion)

- torch.jit.trace under `torch.inference_mode()`; slice-crop F.pad shim for negative pads; fp16 trace hits a mixed-dtype conv upstream of the inpaint models; shapes must be multiples of 96.
- 1080p: iw3 SCALES 1920x1080 -> 756x1344 (bilinear, antialias=True, align_corners=False, even rounding), then the MODEL replication-pads to 768x1408 (pad = 64 − dim%64, a full 64 when divisible) — NOT 768x1344. A fixed-shape runner must add 64 replicated columns or accept a right-edge border difference.
- torch antialias quirk (pinned by fixture): with antialias=True the sample centers are ALWAYS half-pixel; align_corners only bends the scale. ac=T+aa=T ≠ classic align_corners bilinear even when upscaling. `resize_bilinear_torch` in `nunif_pipeline_reference.py` matches all 4 flag combos ≤2.4e-6. Degenerate 1-pixel axes break torch's aa path — probe with real 2D tensors.
- Feeding RAW unnormalised VDA depth (range 0.045..16.6) into the warp produces dense vertical comb striping. iw3 clamps to [0,1] after per-frame independent minmax (ema_normalize=False is the default). This failure mode is visible as comb striping and was hit and fixed during the ToS bring-up.
- row_flow weights load as RowFlowV3, symmetric=False, delta_output=True (stereo_model_factory.py:103-110 at b1548e8).
