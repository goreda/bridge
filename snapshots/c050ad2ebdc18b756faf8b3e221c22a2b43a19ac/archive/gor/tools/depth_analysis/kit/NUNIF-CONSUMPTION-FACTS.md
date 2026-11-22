# nunif consumption facts (190v, A-D for E-G 15:02)

Upstream refs are iw3 @ `b1548e8` (the pinned clone); weights per the
models.lock rows landed at 8100edc2. Fixtures:
`nunif_consumption_fixtures.npz` (torch + real weights,
`gen_consumption_fixtures.py`); numpy reference:
`nunif_pipeline_reference.py`; torch-free gate:
`Tests/NunifMath/nunif_consumption_test.py` (17 checks).

## 1. T3 row_flow consumption — `apply_divergence_nn_LR`

Locked "row_flow" weights (`2e4daa14…`, 485,179 B) =
`iw3_row_flow_v3_20250627.pth` = `RowFlowV3` (`iw3/models/row_flow_v3.py`),
loaded by `load_row_flow_model` with `symmetric=False, delta_output=True`
(`iw3/stereo_model_factory.py:103-110`).

Dispatch (`iw3/backward_warp.py:206-266`): symmetric=False and
`synthetic_view="both"` → two calls of `apply_divergence_nn(..., shift=-1)`
(left) and `shift=+1` (right) at the GIVEN divergence. `"right"`/`"left"`
alone run ONE call with `divergence*2` (`backward_warp.py:249/262`).

`apply_divergence_nn_delta` (`backward_warp.py:315-366`), the T3 path:
- shift>0 (right eye): flip `c` and `depth` horizontally FIRST, flip the
  result back at the end.
- `base_size = max(H, W)` (used as `image_width` in the feature channels,
  NOT the frame width); `divergence_step = divergence/steps`;
  `delta_scale = 1/(W//2 - 1)` with W the DEPTH width.
- Per step j: `x = make_input_tensor(None, depth_warp, divergence_step,
  convergence, base_size)` (3ch: depth, divergence_feature =
  `div*0.5*0.01*base_size/32`, convergence_feature =
  `-div*0.5*0.01*base_size*convergence/32`, `backward_warp.py:10-16`);
  `delta = model(x)`; between steps the DEPTH is re-warped
  (`backward_warp(depth_warp, grid, delta, delta_scale)`); the deltas are
  collected.
- The IMAGE is warped once per collected delta, IN ORDER, after the loop
  (`backward_warp.py:359-361`), then clamp(0,1).
- `backward_warp` (`backward_warp.py:75-92`): `grid + delta*delta_scale`;
  if the image and depth resolutions differ, the GRID (not the image) is
  bilinearly resampled to the image size (align_corners=True,
  antialias=False); `F.grid_sample(mode=bilinear,
  padding_mode=border, align_corners=True)`, clamp 0..1.
- RowFlowV3 `_forward_delta_only` (`row_flow_v3.py:102-108`): replication-
  pads the 3ch input to a multiple of `mod*8 = 96`, conv trunk,
  crops back, returns `cat([delta_x, 0])` ([B,2,H,W], float32). The
  model's own `delta_scale` buffer (1/127) is NOT used on the delta path.

Warp steps (`iw3/utils.py:2837-2845,61-64`, `args.warp_steps=None` →
auto): single-eye view doubles divergence first; then row_flow_v2: div >
2.5 → `ceil(div/2)`; row_flow/v3: div > 5.0 → `ceil(div/4)` (note: 5.0
exactly stays 1 step); else 1. Divergence 2.5 (iw3 default) → steps=1.

Upstream call site (`iw3/utils.py:515-531`): if `args.stereo_width` is
set, the DEPTH alone is resized first (bilinear, align_corners=True,
antialias=True, clamp 0..1) — the image is NOT. `convergence` may be a
per-batch tensor (flattened) or a scalar (broadcast). Default
`stereo_width=None` → no resize.

Fixture `rf_*`: synthetic 48x64, divergence 2.5, convergence 0.5,
steps=1, fp32 no-AMP (iw3 passes `enable_amp=True`; AMP changes numerics
on CUDA only). Real RowFlowV3 delta range on this input: [-0.476, 1.054]
half-px units. Numpy orchestration reproduces both eyes ≤ 4.3e-6.

## 2. 1080p → model input ("768x1344"): SCALE, then REPLICATION-PAD

iw3 never letterboxes or crop-to-shape. Two stages:

1. `BaseInpaint._resize` (`iw3/base_inpaint.py:200-209`): only when
   `max_width` is set and the frame is wider: `new_w = max_width` (bumped
   to even), `new_h = int(max_width/W*H)` (bumped to even) — aspect kept;
   `F.interpolate(mode=bilinear, antialias=True, align_corners=False)`.
   With `max_width=1344`: 1920x1080 → **756x1344**. (`max_width` default
   is None — no resize; GUI offers "" or "1920", `iw3/gui.py:319-322`.)
2. `LightVideoInpaintV1.forward` (`iw3/models/light_video_inpaint_v1.py:
   200-207`): replication-pads RIGHT and BOTTOM by
   `mod*downscaling_factor − dim % (mod*downscaling_factor)` = 64 −
   dim % 64, runs, crops back. NB: when a dimension is ALREADY divisible
   the pad is a full 64 px, not 0 — 756x1344 → **768x1408**, not
   768x1344. The 768x1344 figure is the padded HEIGHT × the SCALED
   width; a fixed-shape 768x1344 runner must add the 64 replicated
   columns itself (iw3 semantics) or accept a border difference in the
   rightmost 64 source columns.
   Temporal: frame batch is padded to SEQ_LEN=12 by repeating the
   first/last frame symmetrically (`light_video_inpaint_v1.py:137-150`).

Fixture `rs_*`: deterministic 1080p frame (seed 7, regenerable via
`ref.make_frame_1080p`), torch output slices + pad spec
(t,b,l,r = 0,12,0,64). Numpy resize vs torch: ≤ 1.5e-5.

## 3. layer_weight resize (MLBW composite): align_corners=True + antialias

`apply_divergence_nn_delta_weight` (`iw3/backward_warp.py:435-441`): when
the image and model-output resolutions differ,
`F.interpolate(layer_weight, size=c.shape[-2:], mode=bilinear,
align_corners=True, antialias=True)`.

Torch quirk pinned by fixture: in the generic antialias path the SAMPLE
CENTERS are always half-pixel (`scale*(i+0.5) − 0.5`); `align_corners`
bends only the SCALE (`(in−1)/(out−1)` vs `in/out`). So
align_corners=True + antialias=True is NOT the classic align_corners
bilinear, and antialias is not a no-op there — a runner with only
`resizeBilinearAlignCorners` (no aa) mismatches even on UPSCALING.
Numpy reference `resize_bilinear_torch(x, size, align_corners,
antialias)` reproduces torch ≤ 2.4e-6 on all four flag combinations,
up and down (fixture `lw_*`: 27x45 → 108x180, 100x100, 13x22, and
54x90 no-aa contrast).

## 4/5. F1 fill + F3 comfort (landed ac2af3fe)

- F1: `tools/vr180_render_ref.py` `fill_rows`/`fill_edge_runs`: runs ≤ 16
  px blend the two endpoint colours linearly; longer runs take the far
  endpoint column's vertical average (33-row window, covered pixels
  only). All quantisation is integer-exact round-half-up
  (`(2n+d)//(2d)`), so the float32 kernel can match the float64
  reference BIT-EXACTLY. Metrics `fill_run_lengths` / `flat_fraction` /
  `vstep_mean`; staged depth-step check in `stereo3d_kernel_test.py`:
  run p95 4 px, max 42 px; flat-frac 1.000 → 0.905; vstep 81.8 → 27.7
  (constant-fill rule → F1). The kernel-side `s3d_fill` (and its text
  pins) is E-G's to update to this spec.
- F3: `tools/depth_analysis/comfort.py` `shot_comfort_span(_values)` +
  `quantile_frames` mirror `ShotComfort.swift` (ShotComfortSpan span, 195y G2) exactly
  (bisection 60 iters on [0.25, 3], p5/p95 numpy-linear quantiles,
  budgets 2.0/−1.0 deg, `span_before` from the median-baseline scale);
  pinned in `test_comfort.py` with E-G's five synthetic shots (flat
  distant → gain 3.0 clamped; close deep → 0.65; tiny range → 3.0
  clamped). The render key + `test_render_key_matrix` change lands WITH
  the wiring (A-D updates the matrix when the key shape lands).
