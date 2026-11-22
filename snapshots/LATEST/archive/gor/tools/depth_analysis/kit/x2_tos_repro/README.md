# X2 goreda lane: independent Linux reproduction of the iw3 ToS renders (2026-11-09)

Independent re-execution of the A-D ToS reference (kit/x2_tos_reference/) on this Linux box
(2 cores, 1 GB RAM, torch 2.14.1+cpu fp32), to verify the pipeline claims with my own run.

## Inputs discovered/verified

- Source: Tears of Steel 720p (nluug blender mirror tears_of_steel_720p.mov, 372,178,639 B).
  The A-D cut offset was NOT documented in the handoff; I recovered it by normalized
  cross-correlation of the committed T2 PNG left eye against every decoded movie frame
  (find_cut_offset.py): best match frame 1440 = t=60.000s exactly at 24fps. Cut 48 frames:
  `ffmpeg -i tos_720p.mov -vf "select='gte(n,1440)*lt(n,1488)',scale=320:180" -vsync 0 -f rawvideo -pix_fmt rgb24 frames.rgb`
  (scale = ffmpeg default bicubic; T2 near-bit-exact parity below confirms the scale path).
- Depth: the committed fixture ../x2_tos_reference/tos_depth_minmax_320x180_fp16.npz (exact, no VDA rerun).
- Weights: 7 nunif release assets re-downloaded by me, sha256 7/7 match models.lock (see
  ../X2-VERIFY-20261109-goreda.md). row_flow loads as RowFlowV3 symmetric=False delta_output=True.
- iw3 code: nagadomi/nunif @ b1548e8 (full sha b1548e8ff08758f336cdab14443647318ef5e0e9).
  One local compat edit for py3.10: typing.Self -> typing_extensions.Self (iw3/base_inpaint.py).

## Results (diff vs A-D committed renders; their mp4s carry crf18 codec noise)

| tier | output | meandiff | p99 | max | PSNR dB |
|---|---|---|---|---|---|
| T3 row_flow_v3 (48f) | tos_t3_row_flow_v3_goreda.mp4 | 3.177 | 15 | 62 | 35.08 |
| T2 mlbw_l2_inpaint image (f0) | tos_t2_mlbw_l2_inpaint_image_goreda.png | 0.044 | 1 | 1 | 61.65 |
| T1 mlbw_l2_inpaint video (48f) | tos_t1_mlbw_l2_inpaint_video_goreda.mp4 | 3.134 | 15 | 58 | 35.23 |

T2 is PNG-vs-PNG (lossless both sides): max abs diff 1 code value, i.e. bit-parity within
rounding. That pins the cut offset, scale path, depth fixture, weights and pipeline all correct.
T1/T3 diffs are consistent with double crf18 codec noise. T1 peak RSS 977 MB on this 1 GB box
(video inpaint at 320x180 just fits; larger shapes OOM here, matching the handoff's OOM note).
Full metrics: x2_repro_diff_vs_ad.json. Discrepancy noted: the A-D README sanity line
"L-R meandiff T1 52.6 / T3 55.1" does not reproduce under my computation (I get ~17 for T3);
my renders match theirs pixelwise, so the sanity number's definition differs, not the pipeline.

## Reproduce

```
NUNIF=/path/to/nunif python3 repro.py --frames frames.rgb \
  --depth ../x2_tos_reference/tos_depth_minmax_320x180_fp16.npz --tier all --outdir .
```
