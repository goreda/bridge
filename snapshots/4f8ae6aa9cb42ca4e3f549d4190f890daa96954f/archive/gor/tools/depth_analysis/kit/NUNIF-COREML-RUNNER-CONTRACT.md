# nunif CoreML runner contract (190w W3, E-G runner wiring)

Kit: `iw3-nunif-coreml` lock row, gorav release `gor-kit-2026-11-09`,
`gor-kit-nunif-coreml.tar` sha256
`ef67c3939b1560ed92e3f82dec69861101aed3654dee49bc3f992d124a0fd218`
(149,964,800 B). Manifest mirror: `nunif-coreml-kit-manifest.json` in this
directory (identical to the tar's `kit_manifest.json`). Owner-private Mac
build ONLY (190w W1); distribution is a go-live gate. Converted on Linux,
NEVER EXECUTED on Mac: verify each package against its fixture npz before
first use.

All references are to upstream nunif (github.com/nagadomi/nunif) release
0.0.0 code; the local reference clone used for conversion is iw3 @ 190t.

## Tier map

| Tier | Method label (render key v4) | Packages |
| --- | --- | --- |
| T1 | `mlbw_l2_inpaint_video` | nunif_mask_mlbw_l2_d1_fp16 + nunif_light_video_inpaint_v1_fp16 |
| T2 | `mlbw_l2_inpaint` | nunif_mask_mlbw_l2_d1_fp16 + nunif_light_inpaint_v1_fp16 |
| T3 | `row_flow_v3` | nunif_row_flow_v3_fp16 |
| fallback | `dibr_golden` | no learned model |

## Warp models (mask_mlbw, row_flow)

Input `x = [1,3,H,W]`, channels built runner-side per
`iw3/backward_warp.py:make_input_tensor(c=None)`:

1. `depth` (float, upstream range as prepared)
2. `divergence_feature`: full-image constant =
   `make_divergence_feature_value(divergence, convergence, image_width)`
   with `image_width = max(H, W)`
3. `convergence_feature`: full-image constant (same helper)

Divergence/convergence are NEVER model inputs; one conversion serves all
strengths. `preserve_screen_border` tapers those two channels toward the
borders when enabled (upstream lines 31-47); keep the default off.

Outputs (delta_output=True mode, `iw3/models/mlbw.py:_forward_delta_only`,
`row_flow_v3.py:_forward_delta_only`):

- mask_mlbw: `delta`, `layer_weight`, `hole_mask_logits`
- row_flow: `delta` (2 channels, second is zeros)

Consumption per `iw3/backward_warp.py:apply_divergence_nn_delta_weight`:
`layer_weight` is bilinear-interpolated to the frame size runner-side
(`align_corners=True, antialias=True`), delta drives `backward_warp`
(grid_sample, bilinear, padding border, align_corners=True), hole mask is
thresholded at 0.15 (`MASK_MLBW_THRESHOLD`) and post-processed by
`postprocess_hole_mask`.

## Inpaint models (light_inpaint image, light_video_inpaint video)

Package boundary is `model.forward(x, mask, skip_i2i_offset=True)`:
inputs `x [B,3,H,W]` masked RGB + `mask [B,1,H,W]`, output `out [B,3,H,W]`.

Runner-side (mirrors `iw3/models/light_*_inpaint_v1.py:preprocess` and
`iw3/base_inpaint.py`):

1. hole mask post-process: `postprocess_hole_mask` then
   `preprocess(closing=iw3 default, inner/outer_dilation, base_width)`:
   `x = x * (1 - mask)`; `mask = clamp(mask_blur(mask) + mask, 0, 1)` with
   `SeparableGaussianFilter2d(1, kernel 15)`
2. video: `SEQ_LEN = 12` frames per window (`B = 12`); windows overlap
   3 + 3 frames (`BaseVideoInpaint`, pre_padding = post_padding = 3);
   non-multiple-of-12 tails are padded by edge-frame replication
   (`LightVideoInpaintV1.infer`) and cropped back
3. output is already composited over the source by the model
   (`src * (1 - mask) + out * mask`, clamped to [0,1])

## Padding

Upstream models always pad one full block (replication) and crop back.
The converted graphs do the same internally; the negative-crop was
traced as a slice (numerically identical). Inputs must be pre-padded
(replication) so H, W are multiples of 96 (LCM of the models' alignments:
mlbw 32, row_flow 96, inpaints 64), then outputs cropped back.

## Shapes in this kit

- nunif_row_flow_v3_fp16, nunif_mask_mlbw_l2_d1_fp16,
  nunif_light_inpaint_v1_fp16: fixed 768x1344 (720p + pad)
- nunif_light_video_inpaint_v1_fp16: fixed 288x480, BRING-UP ONLY (this
  Linux box OOMs tracing it larger). Re-convert at production resolution
  on the Mac: `tools/depth_analysis/nunif_convert.py --only video --shape
  768x1344`. Do not ship T1 quality from the 288x480 package.

## Parity fixtures

Each `*_fixture.npz` holds seeded inputs (`in_*`) and torch fp32 reference
outputs (`out_*`) at the exact package boundary. Mac check: run the
package on `in_*`, compare to `out_*`; report max abs diff per output.
Fixture shas are in `nunif-coreml-kit-manifest.json` under `fixtures`.
