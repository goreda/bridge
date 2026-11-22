# X2 ToS reference renders (190w X2)

iw3 reference (PyTorch, Linux) reproduction of the three learned tiers on a Tears of Steel test clip,
for parity diffing against the converted CoreML graphs (Mac side).

## Provenance

- Source clip: Tears of Steel 720p, cut to 48 frames at 320x180, 24 fps (regenerate with ffmpeg if needed).
- COMMITTED INPUT FIXTURE (B3, 2026-11-09): `tos_input_320x180_48f.mp4`, 63,977 B,
  sha256 `b7eaa61e065d9682e5d3bc2ceae3c79f46a799e792260419dffd38b10bc49956` (h264, 320x180, 24 fps, 48 frames).
  Cut: `ffmpeg -v error -ss 60 -i tears_of_steel_720p.mov -t 2 -vf scale=320:180 -c:v libx264 -preset fast -crf 18 -an tos_test_320x180_48f.mp4`
  from `https://ftp.nluug.nl/pub/graphics/blender/demo/movies/ToS/tears_of_steel_720p.mov`
  (local full file sha256 `efa9062d9cdb7a338e40ad530dfdf234806743f29ae6a1a136b97ece4e588e8f`, 372,178,639 B).
  Licence: film is Creative Commons Attribution 3.0 (mango.blender.org/about; "(CC) Blender Foundation").
  NOTE: the `copyright.txt` next to the movie on the mirror covers the SOUNDTRACK (CC-BY-ND-3.0), not the film;
  this fixture carries no audio (`-an`).
- Depth: VideoDepthAnything VDA_S torch, `VideoDepthAnythingModel("VDA_S").load(gpu=-1, resolution=266)`
  (memory-bounded box; iw3's own resolution path). Raw output 266x462, then iw3's DEFAULT video
  normalisation: per-frame independent minmax to [0,1] (`ema_normalize=False`, SimpleMinMaxScaler;
  verified in iw3/utils.py + base_depth_model.py + depth_scaler.py at b1548e8), then bilinear resize
  to 320x180. The exact normalised depth the renders consumed is committed as
  `tos_depth_minmax_320x180_fp16.npz` (key `depth`, [48,1,180,320] fp16) so the Mac parity run does
  not need a torch VDA.
- Synthesis parameters: divergence 2.0, convergence 1.0, steps 1, synthetic_view="both",
  preserve_screen_border=False, inner/outer_dilation 0, enable_amp=False, fp32 CPU.
- Driver: `ref_run.py` (runs against an iw3 checkout at nagadomi/nunif b1548e8; two local
  compatibility edits for py3.10 CPU-only are needed, noted in the driver).

## Renders

- `tos_t1_mlbw_l2_inpaint_video.mp4` — T1 (mlbw_l2_inpaint, video mode, 12-frame windows 3+3 step 6): 48 frames, 640x180 SBS
- `tos_t2_mlbw_l2_inpaint_image.png` — T2 (same model, image mode) on the first frame: 640x180 SBS
- `tos_t3_row_flow_v3.mp4` — T3 (row_flow_v3 via apply_divergence_nn_LR): 48 frames, 640x180 SBS

Sanity (this box): L-R meandiff T1 52.6 / T3 55.1 (parallax present), temporal d1 ~3.7, no near-black
hole pixels, T1 vs T3 meandiff 30.0. Earlier broken runs (dense vertical comb striping) were caused by
feeding RAW unnormalised VDA depth (range 0.045..16.6) into the warp; iw3 clamps to [0,1] after
per-frame minmax. That failure mode is visible as vertical comb striping.

## Weights used (nunif published release URLs, github.com/nagadomi/nunif releases tag 0.0.0)

| file | sha256 | bytes |
|---|---|---|
| iw3_mask_mlbw_l2_d1_20250903.pth | fe3ab406ba102662550e34798eac03c0e14b9486bcdc460b0b0e4b97dccfb1b7 | 958587 |
| iw3_light_inpaint_v1_20250919.pth | 8b1a85df321ede3ea45d0b37a7f2c509e941687c062e1d584aab8808c253db6d | 9070711 |
| iw3_light_video_inpaint_v1_20250919.pth | 788e13a77f4ace05c76bfcd6577b15e9ca220cbb3f9c43d3f14510dc15cb9aae | 9282225 |
| iw3_row_flow_v3_20250627.pth | 2e4daa14a72a5f751ffff489c1809ce2c4c6aea6191d47f67f2f72afe4ef612a | 485179 |
| iw3_mlbw_l2_d1_20250627.pth | 0a780170538f8d71b484e7886369c199f1bd7d23cf8b8c5ee45baf06e74f064d | 958267 |
| iw3_mlbw_l2_d2_20250627.pth | dd2e0017b878e4470a03142ee5a2eab269b1a45af27085a4ffcc52b0c068b0e7 | 958267 |
| iw3_mlbw_l2_d3_20250627.pth | 083665140fd24eba0411210c37a0e748196b6e8ae6447eb97bb5bd8cf32fa1fb | 958267 |

All 7 load via nunif load_model on this box (MLBW d1, LightInpaintV1, LightVideoInpaintV1, RowFlowV3
verified instantiating + inference). mlbw_l2 d1-d3 serve plain mlbw_l2 (not in the tier list; fetched
for completeness per X2).

## Mac-side parity (CoreML vs this reference)

CoreML cannot execute on this Linux box, so the diff vs the converted graphs is Mac-side by design:
run each converted package on the same 48-frame clip (same depth npz, same divergence/convergence),
then compare against the renders here. Report PSNR/max-abs per package. The bring-up-shape exception
is light_video_inpaint (shipped at 288x480; re-convert at 320x180 on the Mac via
nunif_convert.py --only video --shape before parity).
