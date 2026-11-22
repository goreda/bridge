# gor prepare kit - VDA-S + MoGe-2 CoreML builds - UNMEASURED, Mac-only execution

Status: CONVERTED on Linux with coremltools 9.0 (torch 2.14.1 trace). NEVER
EXECUTED - CoreML execution requires macOS. All numbers for these artifacts
must come from the owner Mac; none exist yet.

Pieces (mirror the vda-stream ONNX split, EmreGneri repo, Apache-2.0):
- encoder_fp16.mlpackage   pixels [1,3,154,266] -> feat1..4 [1,209,384]
- bootstrap_fp16.mlpackage feat1..4 -> depth [1,1,154,266] + cache0..7 (T=1)
- stream_fp16.mlpackage    feat1..4 + cache0..7 (T=31) -> depth + nextCache0..7

Source: Video-Depth-Anything-Small (Apache-2.0), checkpoint
video_depth_anything_vits.pth sha256
13379300b739e659f076a59d52e9801bd8d38c541a7e71f73bbca4dcfb013609,
upstream commit 4f5ae23172ba60fd7bc11ef671cca678842c7072.
Converter: tools/depth_analysis/coreml_convert.py (this repo).

UNVERIFIED DEVIATION vs the PyTorch reference: coremltools has no
upsample_bicubic2d, so DINOv2 positional-embedding interpolation is traced
with bilinear instead of bicubic (one op, pos-embed path only). Expected
effect: small depth-value differences vs the 0.15% fp16/fp32 ONNX parity
baseline. MUST be measured on the Mac before any quality claim:
run the same 20 synthetic frames from the parity fixtures through
encoder+bootstrap/stream via coremltools predict and compare against the
ONNX outputs (test prints per-frame diffs; reuse the same frames).

Rebuild: python3 tools/depth_analysis/coreml_convert.py --piece all --out <dir> (VDA-S); python3 tools/depth_analysis/moge_convert.py (MoGe-2)

MoGe-2 (contract s13 c3, moge_convert.py; aspect-correct enumerated
shapes - the runner picks by source aspect, never stretches; focal
recovery + projection + metric-scale application port to Swift):
- moge2_vits_518x294_fp16.mlpackage  71MB  16:9-class (777 tokens, default)
- moge2_vits_518x294_fp32.mlpackage  142MB (fp32 fallback)
- moge2_vits_518x518_fp16.mlpackage  72MB  VR180 per-eye square (1369 tokens)
- moge2_vits_518x518_fp32.mlpackage  144MB (fp32 fallback)
forward() boundary: image [1,3,H,W] -> points/normal/mask/metric_scale.
Same status: CONVERTED on Linux, NEVER EXECUTED (macOS only). Torch-level
fp16 deviation 0.024-0.028% rel (real frames), but CoreML lowering is
unverified. The old square-only moge2_vits_{fp16,fp32}.mlpackage pair
was retired (calibration-only, s13 c1).

## content_sha256 algorithm (canonical, contract s13)

Every content_sha256 in kit_manifest.json is: sha256 over the stream
built from all regular files under the .mlpackage, recursive - each
file's path relative to the package root, UTF-8, '/'-separated, no
leading './', sorted BYTEWISE - feeding per file in order:
path_bytes + NUL + file_bytes + NUL. Symlinks are forbidden (build
fails); dotfiles are ordinary files (none expected). Reference
implementation: tools/depth_analysis/kit_hash.py (also the verifier:
python3 kit_hash.py --verify <unpacked kit dir> checks every package
against kit_manifest.json content_sha256 + size_bytes). Consumers
recompute after unpack before first use; a mismatch means a corrupted
or tampered package - refuse to load.

## 190w additions (2026-11-09)

- windowed_encoder_fp16.mlpackage (vda-s windowed DINO encoder, pixels
  [B(1..32),3,154,266] -> feat1..4 [B,209,384]) + windowed_head_fp16.mlpackage
  (feat1..4 [32,209,384] -> depth [1,32,154,266]) - 190w W4: windowed
  (non-streaming) VDA for prepared ranges; streaming stays for unprepared
  live ranges. Upstream windowing convention (INFER_LEN 32 / OVERLAP 10 /
  KEYFRAMES [0,12,24..31] / tail-pad) is in the kit manifest and
  windowed_convert.py. Split composition verified BIT-EXACT vs the full
  upstream windowed model on Linux; the single-package [1,32,3,H,W] form
  OOMs the 2GB Linux converter at trace time, hence the split. Same
  CONVERTED-on-Linux NEVER-EXECUTED status: verify on the Mac against
  windowed_ref_fixture.npz (torch fp32 reference) before first use.
  Asset: gor-kit-vda-windowed-bec7ef65.tar (upload pending, 75.6MB).
- gor-kit-nunif-4743841e.tar: iw3 row_flow_v3 + mlbw_l2_inpaint +
  mlbw_l2_inpaint_video weights (owner-private-Mac approval only, 190w
  W1; Depth Pro-fork training-data provenance caveat in NOTICE-models.md).
