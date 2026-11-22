# 190v pipeline contract (one commit, binding for all three 190t workers)

Lanes: A-D analysis/depth (01M6YN4R), E-G stereo render (01M6R3K1),
H-K menu/OSD (01M6V74P). Owner block 190v, 03:20:50. No placeholders:
SBS + VR180, VDA Small, MoGe-2 FoV, iw3-class synthesis, Prepare film.

v2 amendment (03:33): depth container is the 190t-specified 10-bit HEVC
(v1's 16-bit NPZ format is withdrawn), and section 5 names the learned
Tier-1 route instead of the procedural stand-in. (v1 review flags relayed
by Main from R2AH at 03:32: NPZ not the specified format; procedural warp
is not neural Tier 1.) v2.1 (04:01): mp4 + Main 10 4:2:0 + full-range
signalling (sections 1, 3).

## 1. Depth frame format

- One `depth_shot_NNNNN.mp4` per shot (NNNNN = shot index in cuts.json
  order) + one `depth_shot_NNNNN.json` sidecar.
- Container: mp4, one video track, HEVC Main 10 4:2:0 (yuv420p10le), x265
  `lossless=1` - bit-exact per plane, Tier-1 quality is never lowered by the
  container (verified: Tests/DepthAnalysis/test_depth_hevc.py, max 0.50 LSB).
  Depth rides the LUMA plane; chroma is constant neutral 512. Full-range
  signalling is part of the format: x265 range=full (VUI
  video_full_range_flag=1 in the bitstream) + colr atom pc, matrix bt709, so
  VideoToolbox returns stored luma unscaled as 420YpCbCr10BiPlanarFullRange. This profile is
  the VT-decodable one: gray10le mono encodes as HEVC Rext 4:0:0, which
  VideoToolbox does not decode, and mkv is not AVFoundation-readable. The
  vendored gorav ffmpeg builds --disable-everything (ppm/mpeg4/pcm only), so
  decode on Mac is AVFoundation/VideoToolbox, NOT gorav ffmpeg.
  Odd source HxW: luma edge-padded to even; sidecar depth_width/depth_height
  give the unpadded size.
- Size: native source HxW (padded to even in the file). Bit depth: 10-bit luma.
- PTS key: container packet PTS, film time in seconds (first packet
  PTS = first_frame / fps; ffprobe packet=pts_time). Render keys frames by
  PTS, never by wall time.
- Value meaning: INVERSE DEPTH AFTER D SCALE. 10-bit sample w10 ->
  v = w10 / 1023 * 1024 inverse metres; metric depth Z = D / v = 256 / v
  metres along the optical axis. w10 == 0 means masked / infinity.
  Quantization cost: uniform +/-0.5 LSB in v -> worst-case 0.18 px disparity
  at 63 mm IPD, f = 1400 px (sub-pixel; Z-relative error grows with distance
  but stays visually irrelevant).
- Sidecar json: {start, end (inclusive frame indices), input_size,
  depth_width, depth_height (unpadded), align_scale, align_shift} - the per-shot LSQ/EMA fit that mapped raw VDA-S
  relative output to MoGe-2 metric depth before inversion (audit trail).
- Derivation: raw VDA-S output is relative disparity-like (bigger = nearer).
  Per shot it is fit to MoGe-2 metric depth by LSQ scale/shift
  (align.ShotAligner, per-frame fit, EMA 0.9 within shot, hard reset at cuts),
  then inverted and scaled by D.

## 2. FoV track JSON

Per film: `<cache_root>/<cache_key>/fov_track.json`:

  {"fps": 24.0,
   "shots": [{"start_pts": 0.0, "end_pts": 3.458,
              "hfov_deg": 44.7, "confidence": 0.93,
              "keyframe_values": [[pts, hfov_deg], ...]}, ...]}

- hfov_deg: median of the shot's MoGe-2 keyframe fov_x estimates.
- keyframe_values: [pts, fov_x_deg] per probed keyframe (stride 12 frames).
- confidence: 1 - min(1, stdev(keyframe fovs) / 15 deg); 0 when fewer than 2
  keyframes succeeded. (Measured jitter is ~12 deg p-p on static shots, so a
  spread above ~15 deg means the estimate is not trustworthy.)

## 3. Cache layout and key

As in CACHE-FORMAT.md (same directory): root injected by the app; entry dir
= cache_key = sha256 hex of (absolute path, byte size, mtime, head/tail
content sample) — see cache.py `cache_key`. Marker file `.gor-cache-entry`.
Files: progress.json, cuts.json, meta.json, fov_track.json,
depth_shot_NNNNN.mp4 + depth_shot_NNNNN.json + source_shot_NNNNN.mp4
(source proxy, below). Eviction marker-only, oldest
mtime first, cap from the
app. Readers tolerate ENOENT between pointer read and file open (re-read the
pointer, fall back to "not prepared").

## 4. Render seam E-G <-> H-K (what the menu/OSD reads and sets)

Reads (H-K from the analysis cache):
- `<cache_root>/current-film.json` (fixed path, atomic): {"progress_path",
  "n_frames", "cache_key"} for the film open in 3D mode.
- progress.json {"prepared": [[first,last], ...]} inclusive frame ranges.
- OSD text: "3D prepared: N/TOTAL frames" / "3D prepared: full film"
  (PrepareFilm.status() computes; H-K may recompute identically from
  progress.json + n_frames).
- Mode availability: SBS and VR180 menu entries are enabled for a frame range
  iff that range is inside a prepared range; before anything is prepared the
  entries show "preparing...".

Sets (H-K writes, E-G reads, atomic tmp+rename, fixed path):
- `<cache_root>/render-prefs.json`:
  {"mode": "off" | "sbs" | "vr180",
   "depth_scale": 1.0,        # user strength, multiplies disparity
   "ipd_m": 0.063,            # interpupillary distance, VR180 eye offset
   "convergence_m": null,     # null = screen at infinity focus distance
   "screen_deg": 75,
   "surround": "soft"}        # optional "soft" (default; blurred edge fill outside the film) or "off" (black); part of the render key
                              # screen_deg: optional; film width on the VR180 canvas in degrees, default 75, valid 20-150, 0 = legacy shot fov; reader lenient
  E-G re-reads on change (mtime check per open/play); absent file = defaults
  above. E-G never writes this file; H-K never writes the analysis cache.

## 5. Learned Tier 1 (licence route) and exclusions

Tier 1 synthesis is iw3's LEARNED backward-warp + inpaint:
`mlbw_l2_inpaint_video` from upstream nunif (github.com/nagadomi/nunif, MIT).
Licence route (verified in-repo): the stereo weights
(iw3_mlbw_l2_d1..d3_20250627.pth, iw3_mask_mlbw_l2_d1_20250903.pth) are
distributed by the author as release assets of the same MIT-licensed
repository (releases/download/0.0.0/). nunif's explicit CC-BY-NC carve-outs
cover ONLY named third-party DEPTH checkpoints (Any_V2_B/L, Distill_Any_*,
Ultimate_DAV2_*, DepthPro-adjacent) - row_flow_v3 and mlbw are nunif-original
models (v3 trained on synthetic data from nunif's own forward_fill), with no
NC tag in README/NOTICE. My earlier caution came from resolve-iw3's NOTICE
covering only row_flow_v2 - that scope limits enoky's DERIVATIVE repackaging,
not upstream distribution. If the architect wants an explicit weights
licence statement beyond this, the exact blocker is: nunif has no
per-weight licence file; route = upstream issue asking nagadomi to state the
iw3 weight licence (no other blocker found).
The procedural DIBR (dibr_golden.py) remains the golden test harness and
the fallback tier only; it is NOT Tier 1.
Local measurement (190v, gated wrapper synth_learned.py, anim bench shot,
8 frames 640x360, divergence 2.5 both paths): DIBR coverage 99.96% mean,
zero unfilled holes in both (DIBR fills procedurally, mlbw inpaints);
runtime 0.06 s/frame DIBR vs 0.43 s/frame mlbw steady-state on this weak
sandbox CPU (first frame 1.85 s incl. warm-up). Visible difference is at
occlusion borders: DIBR shows slight horizontal streaking, mlbw stays
clean. The wrapper is hard-gated: GOR_NUNIF_LOCAL=1 + local weights
required, nothing in the build path imports it.
Occlusion-band streak metric (disocclusion bands from disparity steps,
R = mean|dI/dx|/mean|dI/dy| vs source, lower delta = more natural fill):
at default 2.5% divergence the tiers are a wash (|delta| 0.126 DIBR vs
0.123 mlbw); at 4x disparity (10% max, i.e. user depth_scale 4) mlbw is
32% closer to source statistics (0.148 vs 0.218). The learned tier earns
its cost exactly where the procedural fill degrades: wide disocclusions
from high user strength.
Temporal stability (static-region consecutive-frame diff, normalised to
the source feed, same 8 frames at 10% max disparity; only 2 frame pairs
qualify as static on this moving shot): DIBR 1.59x source, mlbw 1.56x -
no temporal advantage either way; both inherit depth jitter.
Current status: the architect ruling is IN (190w W1, 2026-11-09, relayed
by Main): the upstream-sourced row_flow_v3 + mlbw weights are approved for
the owner's private Mac build ONLY and enter the build via models.lock.tsv
with sha256 pins; distribution beyond the owner's Mac stays a go-live gate.
Until the pinned rows ship, dibr_golden remains the shipped tier with the
gap stated. The named CC-BY-NC depth checkpoints stay excluded.

## 6b. Source proxy (render picture feed)

source_shot_NNNNN.mp4 per shot, next to the depth mp4: the Metal renderer
needs the source picture as an rgba8 texture and AVFoundation is the only
in-app decoder. Native source resolution (never a thumbnail, always >= the
render output size), HEVC Main 10 yuv420p10le, x265 CRF 10 (visually
lossless; measured transparent: max abs 10, mean 0.30 on real footage in
the YUV domain - VT decodes source and proxy through the same converter).
Colour tags pass through from the source; an untagged source yields an
untagged proxy (same player convention, no colour shift). Container packet
PTS base identical to the depth mp4 (frame s at s/fps): proxy frame i pairs
with depth frame i by PTS. Odd HxW padded black bottom-right; sidecar
source_width/source_height carry the unpadded size. find_shot_at_pts
returns it as "source_mp4". Resume: a shot missing only the proxy is
refilled WITHOUT re-running the depth models.

## 7. Lookup by PTS (E-G/delivery call sites)

tools/depth_analysis/prepare_film.find_shot_at_pts(entry_dir, pts) resolves a
film PTS (seconds) to its depth file: reads cuts.json + fov_track.json (fps),
returns {"shot", "mp4", "frame", "frame_in_shot", "shot_start_pts",
"shot_end_pts"} or None when the shot is unknown or not yet prepared. Frame
ranges inclusive; inside an mp4, decode order = film order and frame `start`
carries container PTS start/fps. Seek priority: work_chunk(playhead_frame=N)
prepares nearest-playhead-first so a seek lands on prepared depth soonest;
writes are atomic (.tmp + os.replace) so an interrupted chunk never leaves a
partial depth file.

## 8. Render-ready sidecar (Swift render coordinator polls this)

`<cache_root>/<cache_key>/render-ready.json`, rewritten atomically after
every per-shot mutation (prepare_film.write_render_ready):

  {"shots": [{"shot": i, "start": s, "end": e,           # inclusive frames
              "depth_ready": bool, "source_ready": bool,
              "ready": bool,          # depth AND source present
              "failed": bool,         # last attempt raised; retried next chunk
              "error": string|null}], # failure detail when failed
   "n_shots": N, "n_ready": R, "n_failed": F, "updated_at": epoch}

A shot appears in progress.json prepared ranges only when ready. A failed
shot is never marked prepared and is retried by the next work_chunk; the
failure clears on success. PrepareFilm.drive(video_path, fps, n_frames,
start_pts) runs the whole film ahead-of-playhead from start_pts and returns
(done, total, this_doc).

## 9. Pluggable encoder (depth + source proxy)

Writers take encoder=... (prepare_film.write_depth_hevc / write_source_hevc);
libx265 is the Linux/reference encoder. On the Mac an AVAssetWriter /
VideoToolbox encoder MAY produce the files instead, but the OBSERVABLE output
must equal the x265 output (prepare_film.vt_encode_spec() pins it; the
consistency test asserts the x265 output matches the spec):
- depth file: HEVC Main 10 4:2:0 (yuv420p10le) in mp4, full range (VUI
  video_full_range_flag=1 in the bitstream + colr pc, bt709 tags), container
  packet PTS of frame s = s/fps, odd HxW edge-padded to even.
- source proxy: same codec/profile/pix_fmt/container/PTS base; colour tags
  pass through from the source (untagged source -> untagged proxy).
VT guidance (Mac lane verifies on device): kCMVideoCodecType_HEVC with
HEVC_Main10_AutoLevel, input kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
AVVideoColorPropertiesKey bt709/bt709/bt709 + full range for the depth file.

## 10. Per-stage bench (real footage, VDA Small / MoGe-2 only)

Measured with tools/depth_analysis/bench_prepare.py on a 10 s slice of a
live-action clip (640x360 @ 24 fps, bench shot = 207 frames, input_size
252). Host: sandbox CPU (weak x86, 1 GB RAM) - absolute times are
host-relative; the owner's Mac will be much faster. The RATIO between
stages and the cache size are the transferable numbers.

Per stage, per minute of film (steady state):
- frame decode:            5.1 s
- VDA Small depth:      1201.5 s  (0.834 s/frame - 71% of total)
- MoGe-2 FoV keyframes:  194.4 s  (stride 12 -> 120 keyframes/min)
- depth HEVC encode:     175.6 s  (x265 lossless=1)
- source proxy encode:   105.4 s  (x265 CRF 10)
- total:                1682.0 s per minute of film (~28x realtime here)
One-time model loads: VDA 0.34 s, MoGe 1.24 s (negligible).

Cache footprint: 122.6 MiB per minute of film at 640x360 (depth mp4
lossless + source proxy + sidecars). Scales with pixel count: at 720p
expect ~4x; at 1080p ~9x.

Quality on the bench slice: MoGe-2 median hfov 51.19 deg, keyframe spread
(std) 5.55 deg over 18 keyframes -> shot confidence 0.63 by the section-5
formula. Cut detect found both real boundaries ([7, 214]).

Note: write_depth_hevc quantises per frame (streaming) - whole-shot
float64 upcast OOMed a 207-frame shot on a 1 GB host; the streaming writer
keeps peak RAM at one frame.

## 11. Swift renderer parity procedure (Mac lane)

tools/depth_analysis/golden/render_bench_live.json holds the Python
reference output for one real prepared shot (8 frames, params in the file:
ipd, depth_scale, screen_deg, convergence_m, swap_eyes, eye_n, theta_h_deg,
start_pts). theta_h comes from the virtual screen rule (s4 screen_deg,
ported as reference_render.theta_h_for == RenderPrefsValue.thetaH; default
75 deg) and depth enters via effectiveIPD = ipd_m * depth_scale. Output
geometry = the Mac defaults: square eyeN x eyeN eyes (eyeN =
max(256, min(4096, even floor of source height)), ported as
reference_render.eye_n_for) and swapEyes = true (RenderedShotPlan default).
Parity check:
1. Reproduce the SAME entry inputs on the Mac: depth mp4 is x265 lossless
   so any correct decode gives identical w10; the SOURCE proxy is CRF10
   lossy, so either copy the bench proxy bytes to the Mac or accept that
   RGB input differences change the hashes (decode-domain diff then, not
   hash parity).
2. Run the Swift Stereo3DRenderer with the recorded params over the same
   depth+source frames (thetaH via prefs.thetaH(shotThetaH, aspect), ipd =
   effectiveIPD); pack SBS with the first sign in the LEFT half.
3. Compare per-frame and sequence sha256 against the manifest. Any
   mismatch: first check the VT depth decode (MSB-aligned 10-bit -> w10 =
   luma >> 6), then the conv term sign, then fill direction.
Known benign-mismatch classes (desk-checked against Stereo3DKernel.swift,
RenderShotWriter.swift, RenderedShotPlan.swift, 190v 06:38); when the
strict hash fails, quantify with per-pixel diffs and require every
mismatch to fall in one of these:
   a) equal-z ties: Swift zmin+resolve keeps any source pixel whose z bits
      equal the per-pixel min; two distinct source pixels with identical
      metric z at the same output texel race (GPU order undefined). The
      Python reference deterministically keeps the last in scan order.
      Bounded by tie frequency, colours from the same depth plane.
   b) leading/trailing runs and fully empty rows: s3d_fill writes only
      covered pixels and gaps, so uncovered texels of the result texture
      are Metal-undefined (zero-filled on Apple GPUs in practice); the
      Python reference writes black. Diff must be confined to pixels
      outside [first,last] covered column per row.
   c) decoder rounding: VT bgra8 vs ffmpeg rgb24 colour conversion of the
      proxy can differ by +/-1 LSB uniformly; this shifts bytes without
      changing geometry. Geometry errors (conv sign, eye order, fill
      direction) instead produce LARGE structured diffs, which no
      tolerance must hide.
Surround (s3d_surround, E-G ef1581d2, prefs key surround off|soft,
DEFAULT SOFT): canvas pixels outside the film footprint (direction with
conv removed, eye offset ignored, not landing in the source frustum) get
the edge-clamped 5x5 source mean, tap step max(1, max(W,H)/64) px, int
truncation. The Python reference implements this vectorised
(_surround_soft_vec, default surround="soft") and is pinned BYTE-
IDENTICAL against E-G's loop reference (tools/vr180_render_ref.
surround_soft) in the unit tests. Parity tolerance with the Metal build:
inside the footprint the render must be BYTE-IDENTICAL to surround off
(surround never touches inside pixels); outside the footprint a +-1 LSB
per-channel GPU tolerance applies (5x5 mean accumulation order is
Metal-undefined), nothing larger. Golden manifests record the surround
mode; both goldens rebuilt with soft (current r4 seqs in s28:
entry_mini 7627de7115e9ac65, render_bench_live e19eb72fec77fcc0).
The Python reference is tools/depth_analysis/reference_render.py
(render_shot_sbs / golden_manifest); unit parity of the math itself is
pinned in Tests/DepthAnalysis/test_reference_render.py (crafted-input
golden 814bbb1dd4ed..., deterministic without any model weights;
thetaH mapping, eyeN rule and disparity direction pinned against the
Swift constants).

## 12. Alignment finite-masking (regression, 190v)

MoGe-2 emits +inf metric depth at sky. ShotAligner.update now fits only on
finite pairs (min 16) and skips a keyframe whose fit is non-finite, keeping
the running estimate; before the mask, one sky keyframe poisoned the EMA
and whole shots rendered black (anim clip: inv decoded all-zero). Pinned in
Tests/DepthAnalysis/test_align.py (inf-sky regression). Live footage with
sky got a finite but WRONG scale (-2.566 vs correct -2.224) - any golden or
cache built before this fix must be rebuilt.

Render coverage note: a shot with median hfov theta fills exactly
(theta/180) x (vfov/180) of the 180 deg equirect canvas - for the 51.2 deg
bench shot that is 4.8% (measured 4.70%). A small central patch is the
geometrically faithful VR180 placement, not a warp/fill bug; the analytic
plane tests in test_reference_render.py pin disparity magnitude/direction
and angular extent.

## 13. Mac runtime for prepare (190t gap) - measured comparison

The Mac has no python/torch and prepare has no launcher. Three routes
researched and measured on Linux (2026-11-09), VDA Small + MoGe-2 only.

Kit delivery (DECIDED 2026-11-09, Main 09:02): packages are FETCHED,
not converted on the Mac. Two archives, release assets on
goreda/gorav (private build repo), tag gor-kit-2026-11-09:
- gor-kit-vda-35376fef.tar (71,475,200 B, sha256 2b9f4e08f5bc61ba...
  full pin in models.lock.tsv): VDA-S CoreML fp16, Apache-2.0, lock row
  vda-coreml-kit status=usable (LIVE).
- gor-kit-moge-46d0ef03.tar (429,864,960 B, sha256 79e8ebbd1d251b5a...
  full pin in models.lock.tsv): MoGe-2 CoreML 518x294+518x518 fp16+fp32,
  lock row moge2-coreml-kit status=blocked (sha-pinned, LICENCE-GATED
  OFF until the architect rules on the MoGe-2 weights licence; 3D stays
  unavailable without it and the OSD must say so plainly).
Each archive carries its .mlpackage dirs + a filtered kit_manifest.json
(content_sha256 + size_bytes per package) + README.md; the delivery
lane verifies downloads against the archive sha256, then each extracted
package against the manifest (ThreeDModels.swift/gor-fetch-models.sh,
delivery lane's edit). Compiled .mlmodelc cache under
<models>/kit-compiled keyed by manifest sha: accepted (delivery lane).
Upload route: token-authed release-asset API from this lane; the Mac
fetch of the PRIVATE release needs the owner's gh login route -
delivery lane confirms (their item b).
content_sha256 algorithm (CANONICAL, delivery lane 09:12): sha256 over
the stream built from all regular files under the .mlpackage,
recursive - path relative to the package root, UTF-8, '/'-separated,
no leading './', sorted BYTEWISE - feeding per file in order:
path_bytes + NUL + file_bytes + NUL. Symlinks forbidden (build
fails); dotfiles are ordinary files (none expected). Reference
implementation + verifier: tools/depth_analysis/kit_hash.py
(--verify <unpacked kit dir> checks every package against
kit_manifest.json content_sha256 + size_bytes). Both archives
confirmed FLAT (*.mlpackage dirs + kit_manifest.json + README.md at
tar root). The first upload carried ad-hoc hashes; both assets were
REBUILT and re-uploaded 09:14 with canonical-hashed manifests,
then again 09:19 with a refreshed README (enumerated MoGe package
names; retired square-only pair; repo build paths). Round-trip
download sha verified both times; sizes unchanged; current tar shas
in models.lock.tsv. Consumers recompute after unpack and refuse to load
on mismatch.

(a) CoreML (coremltools 9.0, converted on Linux; EXECUTION unmeasured,
needs the owner Mac):
- VDA-S streaming, 3 fp16 packages (encoder 42MB + bootstrap 14MB +
  stream 14MB = 70MB), I/O contract in kit/build/coreml/README.md.
  fp16 deviation MEASURED on real frames (full streaming pipeline,
  ONNX-fp16 runtime vs torch-fp32 reference): anim 60f mean rel 0.156%
  p95 0.218% max 0.225% 1-corr 3e-5; live 60f (sky content) mean 0.040%
  p95 0.058% max 0.079% 1-corr 2e-5 (measure_fp16_dev.py vda). Matches the 0.15%
  synthetic parity baseline. Known unmeasured substitution: DINOv2
  pos-embed interpolation traced bilinear (coremltools lacks
  upsample_bicubic2d); effect bundled into the Mac verification run.
- MoGe-2: aspect-correct enumerated packages per (c3) -
  moge2_vits_518x294_{fp16,fp32} (16:9, 777 tokens) and
  moge2_vits_518x518_{fp16,fp32} (VR180 per-eye, 1369 tokens); the
  original square-only pair was retired (forward() boundary:
  image [1,3,H,W] -> points/normal/mask/metric_scale).
  infer() does NOT convert (utils3d meshgrid unsupported, patched via
  expand; then concat-0-values inside recover_focal_shift). Focal
  recovery, projection and metric-scale application stay OUT of the
  package - they port to Swift (least squares + grid math; removes the
  utils3d dependency from the Mac entirely).
  fp16 robustness MEASURED at torch level (full-fp16 weights+activations
  vs fp32, real anim frame, measure_fp16_dev.py moge): depth rel dev
  0.028%, corr 0.999992, metric_scale dev 0.611%. The third-party ExecuTorch fp16 worst-corr
  0.43-0.54 (mlboydaisuke/MoGe-2-ViT-S-ExecuTorch) does NOT reproduce at
  torch level - the model is not intrinsically fp16-fragile; that failure
  was backend-lowering-specific. CoreML lowering must still be verified
  on the Mac before quality claims.
- Licences: VDA-S code+weights Apache-2.0 (commercial OK). MoGe-2 code
  MIT (DINOv2 parts Apache-2.0); WEIGHTS licence never stated by the
  authors - HF card says MIT but upstream issue microsoft/MoGe#98 asking
  exactly this has been open since 2025-07, unanswered as of 2026-09.
  Commercial-use risk: low but UNRESOLVED; architect's call.

(b) Bundled python venv (build.sh-produced, offline wheels; measured
PyPI macOS arm64 wheel sizes 2026-11-09): torch 138.9 + torchvision 1.8 +
numpy 12.1 + opencv-headless 48.3 + scipy 29.2 + pillow 4.9 + small
pure-py deps ~ 236MB of wheels + python-build-standalone ~ 45MB =
~281MB compressed payload, ~0.9-1.1GB installed. opencv+scipy droppable
(-77MB) if resize moves to ffmpeg/PIL and focal recovery to Swift (same
port as (a)). Speed unknowns: torch CPU on M-series for the VDA-S
streaming loop (this Linux box: 201ms/frame fp32 at 154x266; ONNX fp16
CPU 179ms) and MPS support for the cache-indexing ops (unverified; may
silently fall back to CPU). Preserves exact fp32 numerics: Tier 1 by
construction, zero conversion risk.

(c1) Square-input stretch bias (E-G risk, measured 2026-11-09,
torch fp32, real frames): the 518x518 package stretches 16:9 content,
breaking the isotropic-pixel assumption. Stretch vs aspect-correct
(518x294, 777 tokens): anim hfov 40.3 vs 48.5 deg (-8.3), metric_scale
-12.8%; live hfov 40.8 vs 46.8 (-5.9), metric_scale -11.6%. Correcting
the uv grid at recovery does NOT fix it (anim 21.6 deg, live 40.6) -
the bias is in the network's reading of anisotropic content, not just
the solve. Letterbox (518-wide, 292 content rows, recover on content
region only, single package shape) lands near the aspect-correct arm:
hfov 49.7/50.3 (+1.2/+3.5), metric_scale +5.6%/+16%. Fix options:
aspect-aware enumerated input shapes (cleanest, more package variants)
or letterbox (one shape, jittery metric_scale on live). DECIDED in
(c3): aspect-aware enumerated shapes; 518-square-only packages are
retired (were calibration-only).

(c2) recover_focal_shift stall (E-G report: upstream scipy lm x0=0
ftol=1e-3 stalls near shift 0 on exact-geometry 175-180 deg scenes).
CLOSED 2026-11-09 (Main): reproduced and fixed by the multistart
recovery (s15): least_squares lm from starts {0,.5,1,2,4}, min-cost
selection; stall-class scenes (large shift/z ratio) recover, pinned by
the moge_recovery.json fixture. This lane's local repro attempts (flat
plane, varying z, true shift 0/0.01/0.1, fp64/fp32, hfov 175/179) had
not reproduced the stall; the multistart covers the class either way.

(c3) Enumerated aspect shapes (decision 2026-11-09): aspect-aware
packages, no letterbox (metric_scale jitter). moge2_vits_518x518 (VR180
per-eye, 1369 tokens) and moge2_vits_518x294 (16:9, 777 tokens), each
fp16 + fp32 fallback; the runner picks by source aspect. The old
square-only package was retired (was calibration-only). Non-square
grids trace DINOv2 pos-embed bicubic->bilinear (coremltools gap), same
UNVERIFIED-DEVIATION class as VDA-S. fp16 deviation at 518x294 MEASURED
(torch full-fp16 vs fp32, real frames): anim depth rel 0.024% corr
0.999998 metric_scale 0.051%; live 0.014% corr 0.999986 ms 0.098% -
same robust class as square. Stretch fix validated: aspect-correct
input removes the -8.3/-5.9 deg hfov and -12.8%/-11.6% metric_scale
bias of (c1).

(c) Recommendation: CoreML-first. VDA-S CoreML for the hot streaming
loop (70MB, measured-small deviation, ANE/GPU offload, no python on the
Mac); MoGe-2 CoreML fp16 for the keyframe anchor pending the Mac numeric
check, with an fp32 build (~140MB) as the cheap fallback since keyframes
are rare and speed is uncritical there. The venv is the contingency if
Mac verification fails either model; it costs ~4x the payload and
carries the MPS/CPU speed unknown. Neither route lowers Tier 1 quality:
(a) is measured within 0.23% of the fp32 reference, (b) is bit-identical
by construction. Architect decides.

## 16. Lossless depth cache container (.dzc) - replaces depth HEVC on the Mac path

VideoToolbox lossless HEVC is the risk this removes: the depth cache goes
lossless without VT. Source proxy stays HEVC (s6b/s9 unchanged - the
VT-vs-x265 equivalence note below applies to the proxy only).

Format (little-endian, executable spec = tools/depth_analysis/
depth_container.py + Tests/DepthAnalysis/test_depth_container.py):
- header 64B: magic "GORDZ001" | u16 version=1 | u16 codec(1=lzfse) |
  u32 flags | u32 shot | u32 fps_num | u32 fps_den | u64 start_frame |
  u32 width/height (padded, even) | u32 depth_width/depth_height
  (unpadded, sidecar semantics) | u32 n_frames | u32 plane_bytes
  (= width*height*2).
- per frame: u32 payload_len | u32 crc32(uncompressed plane) | payload,
  where payload = lzfse.compress(plane) and plane = width*height uint16 LE,
  w10 = clip(rint(v/1024*1023),0,1023), v = 256/z - the SAME quantisation
  as s1/write_depth_hevc. No chroma, no VUI, no colour tags: the values
  ARE the depth.
- index: n_frames x u64 absolute offsets; trailer magic "GORDZEND".
- PTS: frame i pts = (start_frame + i) / (fps_num/fps_den) s; pairing with
  the source proxy stays by PTS (s7 lookup shape unchanged, "depth_dzc"
  replaces "depth_mp4").
Resume-safe: index+trailer are written last, so their presence certifies
completeness. A truncated/interrupted file is scannable - readers accept
the leading crc-valid prefix; writers truncate after it and continue
(depth_container.resume_write). This replaces the s6 frame-count probe.
Swift writer (E-G): any valid LZFSE stream is accepted - decoders must not
require byte-identical encodes (Apple Compression may differ from the
reference encoder). Golden fixture Tests/DepthAnalysis/parity/
dzc_golden.{dzc,json,planes.npz}: decode must equal the pinned planes
exactly (lossless round-trip), header fields pinned in dzc_golden.json.
Size measured (anim bench shot 0, 720x1280, 24 fps, real MoGe-2 depth,
median frame): 53 KiB/frame -> ~75 MiB/min (raw planes 2.5 GiB/min;
legacy lossy HEVC depth ~99 MiB/min). Lossless AND smaller than x265
because it skips chroma and bitstream overhead. Live re-measure (regenerated 2026-11-09, 207 f 720x1280 24 fps,
real footage, verified bit-exact on f0/103/206): dzc 27.9 MiB ->
194 MiB/min; legacy x265-lossless mp4 12.0 MiB -> 83 MiB/min (x265 wins
on live: temporal prediction beats per-frame LZFSE on jittery depth;
anim was the reverse. dzc stays the Mac-path default per above - lossless
guarantee without VT, not size, is the driver).
Delivery adapts DepthFrameReader to .dzc (read path: scan header, seek
index, lzfse-decompress, map w10 -> inv as s1); prepare_film gains
write_depth_dzc (follow-up), HEVC depth stays as the reference encoder
for the consistency test only.

## 17. VT-vs-x265 equivalence (source proxy)

Applies to source_shot_NNNNN.mp4 ONLY (s16 takes depth off HEVC).
Must match (observable, asserted by the consistency test):
- codec tags: hvc1, HEVC Main 10 (profile_idc 2 / Main10), yuv420p10le,
  full range (VUI video_full_range_flag=1 + colr nclx 1/1/1 full),
  bt709 primaries/transfer/matrix.
- container: mp4, packet PTS of frame s = s/fps (same timebase as the
  sidecar fps), edit list absent or identity, one sample per frame,
  no B-frame reorder visible at the packet level (PTS monotonic).
- geometry: padded even HxW identical to the x265 output; unpadded size
  only in the sidecar.
May differ (bytes, not semantics): SPS/PPS/VPS byte layout, SEI, GOP
structure, level tag, bitrate, encoder version string, mp4 box order
(moov position), colour box order. Decoded pixels must match the x265
reference within the s11 proxy tolerance (max abs 10, mean 0.30, YUV
domain) - CRF-10-class visually lossless either way.

## 15. Focal/shift recovery: multistart is REQUIRED

Upstream solve_optimal_focal_shift (scipy least_squares lm, x0=0, ftol=1e-3)
stalls on exact-geometry scenes with large shift/z: returns shift ~0 with
cost ~1.3e3 while truth costs ~1e-20. Confirmed via E-G's repro scenes
(hfov 60/90/38, shift 1.3/0.4/2.5; Tests/DepthPrepareMath/
moge_stall_scene.py). Small-shift real content (production anim/live)
converges identically from every start - the risk class is exact-geometry
CG, which includes synthetic VR180 renders.
Normative: recovery = multistart over x0 in {0, .5, 1, 2, 4}, same upstream
LM solver per start, pick min cost; focal closed-form after (upstream
formula). tools/depth_analysis/moge_recovery.py is the reference;
moge_fov.patch_moge() routes MoGeModel.infer through it. Swift ports MUST
implement the multistart selection; single-start is non-conformant even if
it converges on the dev clip.
Parity fixture: Tests/DepthAnalysis/parity/moge_recovery.json pins E-G's
three stall scenes + one small-shift scene with truth and tolerances
(shift abs 0.02, focal rel 1%). Scenes regenerate deterministically from
(h, w, hfov, shift) - no stored grids.

## 18. Shot-cut detection (E-G/delivery port spec)

Reference: tools/depth_analysis/cuts.py. Detector: ffmpeg
-vf scdet=threshold=12.0, parse lavfi.scd.time; threshold 12.0 measured to
separate hard cuts on ToS/Caminandes; fades stay uncut BY DESIGN. A Mac
port using another detector (e.g. VT/Metal histogram diff) must reproduce
these boundaries on the calibration clips - it is NOT required to
reproduce scdet internals. Hard semantics:
- time->frame: frame = int(t*fps + 0.5), dedup, sort.
- ranges: bounds = [0] + cuts(0 < c < n) + [n]; shot i = frames
  (bounds[i], bounds[i+1]-1), inclusive; cuts at frame 0 or >= n are
  dropped (edge cases pinned in the fixture).
- per-shot state (aligner EMA, MoGe keyframe state) resets at cuts.
Fixture: Tests/DepthAnalysis/parity/cut_detect.json pins the threshold,
rounding, range derivation and both edge cases.

## 19. Thermal budget and duty cycle (93C finding, delivery lane)

Prepare must never push the device into thermal throttling; it is a
background batch job, not a render deadline. Design target: sustained
operation at thermalState < serious on fanless M1/M2.

Op-count budget (analytical, ViT-S/14 d=384 L=12 + DPT head; measured
package shapes from the kit):
- VDA-S stream @518x294 (777 tokens): backbone 44.1 + temporal DPT head
  ~30 + temporal modules ~5 = ~79 GFLOP/frame. Every frame at 24 fps:
  1440 f/min -> ~114 TFLOP/min, 1.90 TFLOPS sustained.
- MoGe-2 keyframes, stride 12 (120 kf/min): @518x294 ~74 GFLOP/kf
  -> 0.15 TFLOPS; VR180 per-eye @518x518 (1369 tokens, both eyes)
  ~148 GFLOP/kf -> 0.59 TFLOPS.
- Total worst case (VR180 per-eye): ~2.5 TFLOPS sustained.
- CPU side is negligible: multistart recovery ~6 MFLOP/keyframe (LM on a
  64x64 grid x5 starts), LZFSE encode ~6-12 ms/frame (~0.2-0.4 core at
  24 fps), VT decodes the source in hardware.

Unit split estimate (CoreML .all, fp16 packages): ANE takes the conv/
MatMul bulk (~75% of FLOPs), GPU takes temporal-cache/gather/elementwise
spill (~20%), CPU <5%. ANE at ~15-20% of an M1's 11 TOPS is the cool
path; the GPU spill is the heat driver on fanless units. Do NOT force
.cpuOnly (20-40x slower, still hot) or .cpuAndGPU (hotter than .all).

Duty-cycle policy (normative for the delivery lane):
1. Serialization: VDA-S stream and MoGe keyframes NEVER run concurrently;
   one CoreML request queue, one model at a time. This alone caps peak
   package power roughly in half vs overlapped execution.
2. Thermal watch: subscribe to thermalStateDidChange AND poll
   ProcessInfo.thermalState once per frame boundary (free).
3. Suspend: when state >= .fair, finish the current frame, checkpoint
   (VDA WindowState + per-shot .dzc resume prefix, s16), and suspend.
   Prefer shot boundaries; frame boundary is legal (state is
   serializable). Minimum suspend 60 s to avoid flapping.
4. Resume: only when state < .fair AND it has held for a 30 s dwell.
   Resume exactly from the checkpoint - no recomputation (s16 resume
   semantics; the fov/align sidecar keys make MoGe shots idempotent).
5. QoS: .utility everywhere; no userInteractive work in prepare.
6. Expected duty on fanless M1/M2 at the worst-case 2.5 TFLOPS:
   ~50-70% effective (wall time 1.4-2x the compute-bound estimate).
   A sustained-run Mac measurement refines this; until then the policy
   above is the contract, not the number.
Verification (Mac lane): run prepare on a 5 min clip, log thermalState
transitions + suspend/resume counts; PASS = zero serious/critical
transitions and bit-identical output vs an unsuspended run (resume
correctness, s16 test covers the container half).

93C audit (2026-11-09, derived from this budget ONLY - the owner gor
thermal log is not available to this lane, and the owner's 93 C event
predates the in-app prepare path: this is a budget BOUND for the new
path, not a diagnosis of that event; executable model:
tools/depth_analysis/thermal_budget.py, pins:
Tests/DepthAnalysis/test_thermal_budget.py). Power anchors are coarse
fanless-M1 estimates; the LOAD multiples are the analytical op counts
above and are the hard part of the audit.
- s19-compliant config (stride 12, serialized, fp16 .all): 2.49 TFLOPS
  sustained, ~3.5W package est - about HALF the estimated serious
  onset (~6W). A compliant prepare cannot produce 93 C.
- 93 C (past serious, toward critical) requires >= ~2x the worst case:
  the consistent configs are MoGe running EVERY FRAME per eye (stride
  1, VR180: 9.0 TFLOPS, ~10W est) and/or an fp32 or .cpuAndGPU build
  (~2x energy per FLOP, ~19W est). A 16:9 stride-1 violation (3.7
  TFLOPS, ~4.7W est) alone does NOT explain 93 C.
- Conclusion and SCOPE: the owner's 93 C event came from a BUILD run
  before any prepare path existed in the app (Main 08:58) - this audit
  is a budget BOUND for the new prepare path, not a cause of that
  event. Within that scope: a compliant prepare (serialized, stride 12,
  fp16 .all, suspend-at-fair) sits at ~half the serious onset, and the
  configs that would exceed it (per-frame keyframes, fp32/.cpuAndGPU)
  are rejected at config time: thermal_budget.validate_config
  (over-budget load or stride < 12 = reject) is normative for the
  delivery lane.

## 20. Distort audit + disocclusion fill + surround r3 (190v item 4)

Root causes found on the CG VR180 golden (Mac defaults, 75 deg screen):
1. Tear: a disocclusion strip running to the FRUSTUM boundary had no
   covered pixel on its outer side; the s3d_fill pair pass only bridges
   gaps with coverage on both sides, leaving a vertical black line in
   both eyes. Fix (reference_render edge-run fill, s3d_fill r2): after
   the pair pass, fill each row's leading/trailing run INSIDE the source
   frustum with the sole adjacent endpoint (the far side in canonical
   disocclusion geometry). Outside-frustum pixels are untouched.
2. Streaks: the old soft surround (5x5 mean of edge-CLAMPED taps)
   replicated the boundary row/column into the surround: vertical stripe
   bands at the poles and cone smears at depth edges. Fix (s3d_surround
   r2, superseded): normalised pre-blur + nearest-footprint extension +
   fixed-radius (24) box blur distance-blended over 16 px.
3. Horizontal smear (r2 residual, Main 08:31): the r2 blend kept the
   raw Voronoi extension near the boundary, and the extension holds the
   boundary row's colour constant along its run direction - horizontal
   haze bands beside the footprint (worst at the red/blue sphere
   edges). Fix (s3d_surround r3, current): normalised pre-blur of the
   footprint content (32x 3x3, outside = missing), nearest-footprint
   extension (fixed 8-neighbour scan order), then a DISTANCE-DEPENDENT
   multi-radius box blur from ONE integral image: R=16 at the boundary,
   blended to R=96 over 1..40 px out and to R=256 over 40..120 px out,
   so far surround trends to the global average. Blend in lerp form
   (a + (b-a)*t) so constant fields stay exact. Deterministic float64,
   single uint8 truncation. Cost note for the Metal port: one integral
   image + three box reads per pixel, no iteration.
Pins (Tests/DepthAnalysis/test_cg_vr180_golden.py): black pixels inside
the footprint == 0 per eye; surround top-band horizontal streak energy
gx < 1.0 LSB per eye (measured ~4 pre-fix, 0.11 post-r3); side-band
vertical streak energy gy < 1.0 LSB per band per eye (measured ~2.7
pre-r3, 0.86 worst post-r3). Live bench golden pinned in
Tests/DepthAnalysis/test_live_bench_golden.py (manifest consistency
ungated; hash-locked 8-frame re-render gated on the bench entry,
GOR_LIVE_ENTRY). Goldens re-locked under r4 (s28): entry_mini seq
7627de7115e9ac65, entry_cg_vr180 seq 11f9400d45074945,
render_bench_live seq e19eb72fec77fcc0 (8 frames, 720^2 eyes per
eye_n_for(720); the superseded 360^2 manifest was rendered from the
stale 640x360 entry), test_reference_render crafted hash ccdc34cf5d40.
read_depth_hevc/_read_source_frames now take max_frames for a lean
decode (whole-file decode OOMed the 207-frame live shot on a small
host). E-G must port the edge-run fill AND surround r3 to
Stereo3DKernel before its Swift golden can match; s11 inside-footprint
byte-identity now INCLUDES the edge-run fill.

Postage-stamp arithmetic (Main 09:01: footage ~35% of eye width on the
75 deg screen - confirmed correct, not a bug). Horizontal: the screen
spans 75 deg of the 180 deg eye FOV, so the footage occupies
75/180 = 41.7% of the eye width (measured ~35-40%, within the gnomonic
foreshortening at the pole-side edges). Vertical: the source is 16:9,
so the screen's vertical extent on the gnomonic plane is
2*atan(tan(75/2 deg) * (9/16)) = 46.7 deg, i.e. 46.7/180 = 25.9% of
the eye height (measured 25.8% on the live f0 left eye). A VR180 eye
canvas is square by construction (eye_n_for = even source height), so
a 16:9 source on a 75 deg screen MUST leave the rest of the canvas to
the surround; filling more of it would either stretch the source or
exceed its real FOV. Halo: the surround ring 1-8 px outside the
footprint boundary stays within ~1.4 LSB of the boundary luma on live
content (source edges are genuinely dark: top 64.5, bottom 34.2,
left/right ~16.4 vs centre 72.3); the pre-blur + nearest extension
neither darkens nor brightens the ring; on the saturated CG content
the multi-radius blur pulls the ring up to 5.95 LSB toward the global
average (the intended r3 behaviour). Pinned per side < 10 LSB in
test_cg_vr180_golden.py.

## 21. Temporal stability / flicker (190v item 1)

Metric (tools/depth_analysis/flicker.py): second-difference jitter,
which cancels constant and linear motion. depth_jitter = median
|z[t-1] - 2 z[t] + z[t+1]| over valid triples, normalised by the
median inverse depth (relative); disparity_jitter = the same on the
RENDERED disparity field d = B*cos(theta)/(2 z), sampled on the eye
canvas pixel grid from the exact forward map of render_frame_sbs (the
warp conv terms cancel in the second difference, so the field samples
the unrendered disparity directly). 0.5 px disparity is the
visible-flicker line at headset DPI.

Measured (Main 08:58 order):
- CG golden entry (48 f, 360 px canvas): depth 0.44% rel (median; the
  10-bit mp4 quantisation floor: 1 LSB / median inv), disparity
  0.018 px median / 0.026 px p95. Ground-truth z_true baseline:
  0.026% / 0.0001 px - the model+quantisation stack adds nothing
  above the quant floor on smooth synthetic content.
- Live bench entry (207 f, 720 px canvas): depth 1.6% rel median /
  4.8% p95, disparity 0.081 px median / 0.249 px p95. Real-content
  VDA stream temporal noise is the dominant residual; worst frame
  stays half a visible pixel.
EMA (align.py ema=0.9) is adequate: disparity jitter is sub-pixel on
both goldens, so no keyframe-blending change. align.json carries one
converged (scale, shift) per shot; a future per-keyframe series would
be measured with the same metric.

Pins (Tests/DepthAnalysis/test_flicker.py): CG tier ungated - depth
median <= 0.6%, disparity median <= 0.03 px, p95 <= 0.04 px. Live
tier gated on the bench entry (GOR_LIVE_ENTRY) - depth median <= 2%,
p95 <= 6%, disparity median <= 0.12 px, p95 <= 0.35 px. Thresholds
are ~25-40% headroom over measured and 2-4x below visibility.

## 22. VDA 154x266 stream aspect policy (190v item 2)

vda_stream_common.preprocess was a plain cv2.resize stretch to the
266x154 stream canvas - no aspect policy for non-16:9 sources.
Measured on the CG clip through the real ONNX fp16 stream
(tools/depth_analysis/aspect_bias.py, 24 frames, post-warmup
medians):
- square (1:1) source stretched: median inverse-depth ratio 0.859 vs
  the 16:9 control (-14%), and SPATIALLY NON-UNIFORM: 3x3 grid
  medians 0.78 (center) .. 1.01 (corner), log-ratio std 0.10 - a
  depth-curvature distortion that per-shot align scale/shift cannot
  absorb.
- square letterboxed into the 16:9 canvas: ratio 1.040, log-depth
  r 0.977 - near-neutral; the residual +4% is uniform scale, absorbed
  by per-shot alignment.
- 2.39:1 stretched: ratio 1.017 (mild, the horizontal squish barely
  moves depth); letterboxed: 1.057, r 0.982.
Policy (kit manifest vda_aspect_rule): runners MUST letterbox any
non-16:9 source into the 154x266 canvas preserving aspect (black
bars, uniform scale) - vda_stream_common.preprocess_aspect is the
reference; preprocess stays the byte-exact baseline for parity
fixtures against the upstream export. MoGe-2 already uses
aspect-correct enumerated packages (aspect_rule, s13 c3). Delivery
lane: the Mac runner's resize stage must match preprocess_aspect.
Pins: Tests/DepthAnalysis/test_aspect_bias.py (GOR_MODELS=1).

## 23. Mac self-test receiving side (architect-inbox comparator)

tools/depth_analysis/selftest_check.py reads the owner's gor log,
parses `gor3d-selftest v1` lines (Python port of E-G's
PrepareTelemetry.parse, same substring + unescape semantics; multiple
runs in one log are split at each begin and evaluated separately) and
checks each run against tools/depth_analysis/selftest_expected.json:
- stage budgets (v1 first-run bounds for the 36-frame synthetic clip,
  to be tightened from the first real good log): clip_write 60 s,
  prepare_total 300 s, render_shot 180 s
- thermal peak <= 1 (fair) per s19 policy
- moge precision: fp16_used>=1 OR fp32_used>=1 (fp32 is the sanctioned
  fallback); fp16_rejected>0 is a finding, no weights at all fails
- depth sanity: nan=0, inf=0, min>0, max<1e6, count derived
  from the clip note's declared aspect: frames * box.nw * box.nh
  with box = VDAStream.letterbox(clip W x H) (s22/ce1ab092 crops the
  stream depth to the letterbox picture; 640x360 -> 266x150, so the
  self-test count is 1436400, not the full 266x154 canvas). No clip
  note -> full-canvas fallback with a finding (pre-letterbox build)
- first_3d_frame_sha256: presence + 64-hex only. BIT-EXACT IS NOT
  EXPECTED cross-machine/build: the hash covers an HEVC encode of a
  Metal render fed by CoreML fp16 - three varying layers. A recorded
  reference (expect field) pins only same-machine same-build reruns;
  DIFFERS is a warning, never a fail
- every error line verbatim, bucketed gh / kit / coreml_load /
  compute_plan / other (regexes in the expected file, first match wins)
Output: short English finding list (architect inbox takes it as-is).
CLI exit 0 PASS / 1 FAIL / 2 no self-test lines in the log.
Unit-tested with synthetic good/bad logs:
Tests/DepthAnalysis/test_selftest_check.py (ungated).

## 24. Depth box -> source-size upsample (190v, delivery ca3e50cb)

The native prepare stores depth at the letterbox box (s22, e.g.
266x150 for 640x360); the renderer needs source-size depth.
CANONICAL OPERATOR (confirmed this lane, delivery's choice):
inverse-plane (v = 256/Z) bilinear, half-pixel centres, edge clamp
(cv2.INTER_LINEAR / torch align_corners=False), invalid tap (Z <= 0)
counts as v = 0 (far), back-conversion v <= 0 -> Z = 0. Interpolating
disparity (inverse depth) is the perspective-correct quantity.
numpy reference: tools/depth_analysis/depth_upsample.py (upsample);
verified == cv2.INTER_LINEAR on the inverse plane within fp32
rounding (1.4e-6 max rel). reference_render.render_shot_sbs applies
it whenever sidecar depth size != source size (compatible(): same
aspect within 2%, never larger - port of DepthUpsampleKernel).
Parity fixture: Tests/DepthAnalysis/parity/depth_upsample.json (5x7
box with a step + invalid holes -> 13x11, exact values).
Letterboxed render golden: golden/entry_cg_letterbox (CG source,
depth downsampled to 266x150 via inverse-plane INTER_AREA emulating
the box-grid model output; 8 frames, seq ff59ee1f1005c2ff) pinned in
Tests/DepthAnalysis/test_depth_upsample.py.

Operator judgment (live shot f0/103/206, box 266x150 -> 1280x720,
inverse-depth rel error median / edge-band (top-decile |grad v|)
median / rendered SBS mean abs diff vs the full-res-depth render):
- inverse-bilinear (canonical): 0.0013 / 0.0058 / 0.49-0.86 LSB
- Z-bilinear:                     0.0013 / 0.0057 / 0.49-0.87
- inverse-bicubic:                0.0011 / 0.0050 / 0.43-0.83
- guided (joint bilateral, source luma guide, r=2 sigma 12):
                                  0.0013 / 0.0065 / 0.47-0.89
ALL sub-LSB; the differences are noise-class. Bicubic wins the depth
metrics marginally but overshoots at invalid/far transitions and
costs 16 taps; the guided filter is WORST at edges here - the model's
box-depth edges do not coincide with source-luma edges, so the guide
amplifies mislocation rather than correcting it. Decision: KEEP
inverse-plane bilinear; the box resolution, not the operator, bounds
edge fidelity. No change requested of the delivery lane.

## 25. 3D comfort: disparity budgets + convergence/clamp defaults

Screen disparity (screen-centre approximation, exact on-axis):
disp_deg(z) = deg(2*atan(B/2z) - 2*atan(B/2z_c)); + crossed / - uncrossed.
Budgets: <= 2 deg crossed, <= 1 deg uncrossed (divergence is the hard
limit). DEFAULT POLICY (tools/depth_analysis/comfort.py, shot_comfort),
all per shot, constant within the shot:
- convergence z_c = shot MEDIAN depth (typical surface at screen
  depth). Per-frame convergence would pump; steps only at cuts.
- effective baseline B_eff = min(IPD, 2*z_c*tan(0.5 deg)) via
  depth_scale, so infinity sits exactly at the 1 deg divergence
  budget: shots nearer than 3.61 m (= 63mm/(2 tan 0.5 deg)) get a
  shrunk baseline instead of far overflow.
- near clamp z_eff = max(z, z_near), z_near from the 2 deg crossed
  budget (near_clamp). Both budgets hold BY CONSTRUCTION.
Measured: CG 16:9 z_c 1.14 m scale 0.31 -> [-0.17, +0.92] deg;
2.39:1 and square crops likewise; live z_c 2.58 m scale 0.72 ->
[-0.70, +2.00] deg with 2.8% of pixels clamped (nearest content
0.51 m -> 0.86 m). Current renderer default (conv=0, full IPD) puts
that object at 6.95 deg crossed - 3.5x over budget; the goldens pin
renderer MECHANICS with explicit params, the comfort policy is a
separate opt-in parameter set, so golden hashes are unchanged.
Mac adoption: RenderPrefs defaults should become z_c=shot median +
depth_scale=B_eff/IPD + z_near clamp (E-G port note).
Pinned: Tests/DepthAnalysis/test_comfort.py (arithmetic exact pins,
by-construction invariant at 5 scales, CG bands, live gated).

## 26. Shot-cut behaviour (CG two-shot clip)

Two-shot clip derived from the CG golden (shot 1 = shot 0 with depth
x2, different fov hfov): (a) align EMA state resets at cuts - pinned
in test_align.py ("reset at cut"); (b) convergence constant within
each shot, steps at the cut (1.14 -> 2.26 m; the cut masks the step);
(c) fov_track is per-shot constant - in screen mode (75 deg) the
canvas is the constant screen angle for every shot, shot hfov only
sizes the film in legacy screen_deg=0 mode, so there is nothing to
blend and nothing pumps across cuts. Pinned in
Tests/DepthAnalysis/test_comfort.py shot-cut tier.

## 27. End-to-end comfort pipeline + overlay depth audit

tools/depth_analysis/comfort_e2e.py runs the full reference chain
(depth -> shot comfort -> surround r3 -> SBS) under default
(conv=0, full IPD, no clamp) vs comfort (s25 shot_comfort) params and
compares: disocclusion fill area (render_frame_sbs stats= out-param:
pair/edge-run fill px inside the footprint; instrumentation only,
output bytes unchanged), s20 halo ring metric (per-eye conv-corrected
footprint), s21 disparity jitter at the mode's own parameters.
Measured (CG 6f / live 6f):
- fill area:  0.0117 -> 0.0023 (CG), 3.6e-4 -> 6e-6 (live)
- footprint black px: 0 both modes both clips
- halo: 5.95 -> 5.47 LSB (CG); live top-side ~23 LSB BOTH modes -
  bright top boundary vs the r3 global-average far surround trend;
  content-driven, NOT a comfort regression (comfort <= default + 0.5)
- disparity jitter: 0.0185 -> 0.0059 px (CG), 0.056 -> 0.041 px (live)
Letterboxed 2.39:1 (entry_cg_letterbox): fill 0.0116 -> 0.0022,
halo 5.86 -> 5.48. Comfort improves or holds every metric.
OVERLAY/SUBTITLE RULE: overlays composite POST-render at identical
equirect canvas coords in both eyes. Zero angular disparity = the
element sits at the convergence plane (screen depth) by construction;
the depth map, near clamp and convergence never touch it (it is not
scene input). comfort_e2e.overlay_stamp is the canonical recipe;
pinned: measured L/R shift exactly 0 px, per-eye bytes identical,
stamp bytes identical across render modes.
Pins: Tests/DepthAnalysis/test_comfort_e2e.py (CG ungated 6f, overlay
ungated, live gated on GOR_LIVE_ENTRY, GOR_E2E_LIVE_FRAMES to trim).

## 28. Surround r4: boundary-level correction + side-local far trend + per-content halo bound

Root cause of the live top-side halo (~23 LSB, Main 10:22): the live
shot has a THIN bright glow band hugging the top film edge (1-3 px
inside, luma ~160). r3's 32-pass pre-blur (the extension source)
attenuates thin edge features, so the Voronoi extension carried a
dimmer colour outward (ring mean 116 vs strip 137). Additionally the
r3 far trend (R=256 square box on a 360-720 canvas) read most of the
canvas, i.e. trended to the GLOBAL average. Structural floor: even an
IDEAL nearest-true-boundary extension scores 15.0 LSB on this content
(the strip catches the glow at full strength just inside the edge) -
the flat 10 LSB pin was unattainable on live.
r4 fixes (reference_render._surround_soft_vec):
1. Boundary-level correction: after the Voronoi extension, add back
   per outside pixel (true - blurred) colour of its NEAREST footprint
   pixel (edt return_indices), fading over 24 px. Keeps r3's smooth
   spatial blending - a sharp-source Voronoi instead splits the ring
   into hard colour zones (measured 16.8 LSB on CG sides, rejected).
2. work's INSIDE values are restored to true film content after the
   extension (they only feed the blur windows; output writes only
   outside pixels), so near-ring windows mix true interior with the
   corrected extension - the populations the halo metric compares.
3. Side-local far trend: two anisotropic integral-image windows
   (wide-short above/below, tall-narrow left/right, radial half-width
   64) replace the R=256 square, so far surround trends to the SAME
   SIDE's extended edge colour, not the global average.
Measured (f0): CG halo 5.95 -> 6.19 (ideal 2.91), letterbox 5.86 ->
6.32, live top 23.5 -> 22.4 with the apex band 10.2 -> 8.3; streak
energies gx 0.26 / gy 0.88 (pins hold), tear 0 everywhere.
Halo pin is now PER-CONTENT, derived from boundary luminance:
bound = max(8, 1.3*ideal + 6) where ideal is the nearest-true-boundary
extension delta (test_cg_vr180_golden.py). Goldens re-locked:
entry_mini 7627de7115e9ac65, entry_cg_vr180 11f9400d45074945,
entry_cg_letterbox ff59ee1f1005c2ff, render_bench_live e19eb72fec77fcc0,
test_reference_render crafted hash ccdc34cf5d40.
E-G PORT NOTES (surround r4, supersedes r3): after the Voronoi
extension pass, (a) compute nearest-footprint index per outside pixel
(EDT), add (true - preblur32) colour at that index, weight
max(0, 1 - d/24); (b) use true film content inside the footprint for
the blur windows; (c) far trend: two rectangular integral-image
reads, radial half-width 64, tangential 256, chosen by whether the
pixel is above/below vs left/right of the footprint centroid. All
float64; single uint8 truncation at the end, as r3.

### s28b (2026-11-09) BFS nearest-index + golden relock

The s28 r4 correction's nearest-footprint index switched from scipy
edt (Euclidean) to a slice-shift BFS (L1, fixed 4-neighbour scan
order) so the vectorised renderer and E-G's loop reference
(tools/vr180_render_ref.surround_soft) share one deterministic
algorithm (Metal port: jump-flood or the same BFS in tiles - no scipy
dependency). Byte-level output changed vs the edt variant; goldens
re-locked to the BFS bytes: entry_mini seq 7627de7115e9ac65,
entry_cg_vr180 seq 11f9400d45074945 (48f), entry_cg_letterbox seq
ff59ee1f1005c2ff, render_bench_live seq e19eb72fec77fcc0, crafted
hash e86723ada4bd4c66. Suites green: test_reference_render (surround
parity <=1 LSB, entry_mini fixture, crafted hash), test_golden,
test_cg_vr180_golden (halo 6.01 vs per-content bound), test_golden,
test_depth_upsample, test_live_bench_golden, test_flicker,
test_comfort.

### s29 (2026-11-09) long-clip temporal soak

Test: Tests/DepthAnalysis/test_temporal_soak.py - 336 frames over 3
shots (112 each, per-shot depth scale 1x/2x/0.5x, distinct hfovs),
tiled from the CG golden, full render_shot_sbs path at 96px eyes.
Pinned numbers (this box):
- memory: warm-phase RSS slope 0.00 kB/frame (pin < 64), half-run
  growth 0.0 MB, shot-boundary RSS 349/350/350 MB - no per-frame or
  per-shot leak on the reference path;
- cache keys: cache.cache_key (sha256 over size+mtime+first/last 1MB)
  byte-stable across repeated opens (8fe7e5591822...), prepared range
  survives a fresh Cache instance, single-byte content flip changes
  the key;
- thermal duty-cycle gate: thermal_budget.validate_config() clean for
  the contract config; sustained 2.49 TFLOPS (~3.5 W est, below the
  serious-onset anchor); shot-aware MoGe keyframe schedule = cut frame
  + every 12 within a shot: 30 keyframes / 336 frames (duty 0.0893),
  max gap 12, never denser than stride.

### s30 (2026-11-09) keyframe-boundary depth pops + causal eased alignment

Question (Main 10:54): if VDA relative depth is re-aligned to MoGe
metric PER KEYFRAME (stride 12, cuts), how large is the scale/shift
jump in rendered disparity, does it breach the comfort band, and what
smoothing keeps it invisible?

Measurement (real VDA-S rel depth + real MoGe-2 fits, finite-masked
LSQ per keyframe; disparity at the 75 deg screen, CG eye 360 / live
eye 720):
- CG (4 keyframes): per-keyframe scale jumps med 21% / max 65%; switch-
  at-keyframe boundary pop p95 max 7.10 px = 1.73 deg.
- Live (18 keyframes): scale jumps med 23% / max 320%; boundary pop
  p95 med 1.03 px = 0.125 deg, max 21.6 px = 2.64 deg (kf12).
- Comfort budgets are 2 deg crossed / 1 deg divergence: a raw
  per-keyframe switch EXCEEDS the band on both contents -> smoothing
  required.

Fix (reference, align.apply_align_track + prepare_film): per-keyframe
EMA (0.9, finite-masked, skip-on-degenerate, reset at cuts - unchanged
ShotAligner semantics), but APPLIED eased: frame f in [k_i, k_{i+1})
lerps linearly from k_(i-1)'s EMA value to k_i's over the stride
(hold at the first keyframe and after the last). Continuous (no
boundary step), causal (no future keyframes), deterministic from the
shot's keyframe fits. The per-shot depth json now stores align_track
[[k, scale, shift]] (align_scale/align_shift kept = final EMA, for
compat).

After easing, measured on the same data: boundary pop p95 max 0.018 deg
(CG) / 0.003 deg (live); s21 disparity jitter p95: CG 0.30 -> 0.012 px,
live 0.21 -> 0.008 px (24-26x). Pins: Tests/DepthAnalysis/
test_keyframe_align.py (synthetic known-jump + CG fixture
golden/align_fixture: step 1.7487 deg / eased 0.0179 deg / jitter
0.3007 -> 0.0122 px; eased must stay < 0.05 deg).

Fast-seek: applied params at frame f depend only on track entries at
keyframes <= f (causal EMA + ease window), so a mid-shot landing with
no prior keyframe state reconstructs identical depth from the stored
align_track - pinned exact in the reference test. Runtime (Mac): same
rule - on seek, read the shot's align_track and ease from the
surrounding entries; no playback-history state.

E-G port notes: (1) keep ShotAligner EMA + finite masking as-is;
(2) replace the single per-shot affine application with the eased
track (lerp previous->current EMA over the 12 frames after each
keyframe); (3) persist align_track per shot next to align_scale/
align_shift; (4) on seek, initialize from the stored track, never
from playback history; (5) pop budget: boundary p95 < 0.05 deg at the
75 deg screen, comfort budgets and the s21 flicker metric must stay
green.

### s31 (2026-11-09) real-time budget audit, Mac path (fanless M1 Air)

Executable model: tools/depth_analysis/rt_budget.py; pins:
Tests/DepthAnalysis/test_rt_budget.py. NOTHING here is a Mac
measurement - loads are analytical (s19 op counts + kit package shapes
+ s24/s28 stage definitions), M1 anchors are stated estimates (ANE 11
TOPS fp16 at 35% sustained util, GPU 2.6 TFLOPS fp16 at 40%, DRAM
68.25 GB/s, VT on dedicated silicon, CoreML .all split 75/20 ANE/GPU,
serious thermal onset ~6W est). VDA-S stream FLOPs are the s19 79
GFLOP @518x294 scaled to the actual 154x266 stream export (209
tokens): ~21.2 GFLOP/frame (proportional-scaling assumption; attention
at 209 tokens negligible).

Per-frame ms (VR180 worst): VDA 8.2, MoGe amortized (stride 12) 9.6,
post (upsample + surround r4 + render) 0.4, VT ~2.
- 2D->VR180 (MoGe 16:9 74 GFLOP/kf): 11.0 ms/frame -> FITS 24/30/60
  as-is; ~3.2W at 60 fps. Sensitivity: holds down to ~18% ANE util;
  below that the fixes below are the margin.
- Native VR180 (per-eye 148 GFLOP/kf): 18.1 ms -> FITS 24/30, BREAKS
  60 fps (16.7 ms budget); ~4.3W at 60 fps (below the ~6W onset but
  the hottest compliant config).
- BREAKING STAGE: the model pair (VDA every frame + per-eye MoGe),
  not IO or post. Separately, the MoGe KEYFRAME BURST (28.6 ms 16:9,
  114.6 ms VR180) exceeds a frame at every rate: serialized on the
  playback thread it drops frames at any fps -> pipelining is
  mandatory, not optional.

Cheapest fixes that never lower Tier 1 quality (all reschedule or
skip compute; no quality knob):
1. Depth at half rate (fps/2) with the s30 eased-alignment hold
   between runs: depth is low-temporal-frequency and the s30 causal
   ease already pins boundary pops < 0.02 deg; a cut still forces an
   immediate run (state reset, s26).
2. MoGe keyframes pipelined off the render thread (ANE while GPU
   renders) and applied a stride late - the s30 causal ease tolerates
   late application by construction; prepare-ahead (work_chunk
   playhead-first) means the models never run on the playback thread
   for prepared content at all. Pin: prepare window >= 10 s ahead of
   the playhead at 24 fps.
3. Surround r4 port: pre-blur restricted to the footprint + 32 px
   margin and the multi-radius blur off one integral image
   (0.90 -> 0.57 GFLOP/eye; 0.36 -> 0.23 ms post).
With (1)+(3): VR180 60 fps 18.1 -> 9.1 ms (fits), ~2.9W; 2D->VR180
60 fps 11.0 -> 5.5 ms, ~2.4W.

E-G/delivery port notes: (a) schedule VDA on ANE, never GPU-forced
config (fp32/.cpuAndGPU = ~2x energy, s19 audit); (b) run the MoGe
keyframe as a detached ANE task at frame k, apply its EMA update at
k+12 via the s30 eased track; (c) half-rate depth uses the s30 eased
hold verbatim - no new state; (d) surround kernel: footprint mask +
32 px margin for the 32-pass pre-blur, single integral image for the
b1/b2/b3 windows; (e) keep HEVC proxy encode/decode on VideoToolbox;
(f) 60 fps native VR180 ships only with fixes 1+3; 2D->VR180 ships
as-is at all rates.

### s32 (2026-11-09) self-diagnosing Mac run: rtstage log contract

The first real Mac run must diagnose itself against the s31 model.
New self-test log lines (E-G + delivery lane emit these inside the
existing `gor3d-selftest v1 ` prefix):

    note key=rt_config value=fps=24.0 vr180=false depth_rate=24.0 surround_opt=false
    rtstage name=<stage> ms=<float> n=<int> [max_ms=<float>]

Stages (all required, in emit order): vda (per-frame VDA-S stream),
moge (per-KEYFRAME wall ms, n = keyframes), upsample, surround,
render, vt_decode, vt_encode. rt_config declares the run config;
absent rt_config + no rtstage lines = a pre-s32 build (the comparator
skips the verdict). Once any rtstage/rt_config appears, EVERY stage
line is required - a missing line FAILS loudly (never a silent skip).

Comparator: selftest_check.py parses rtstage into the run, builds the
rt_budget.expected_stage_ms model for the declared config, and prints
the verdict table (stage, modelled ms, measured ms, ratio, ok/REVISE)
plus the thermal readings (peak, transitions, series). Ratio window
[0.25, 4.0]: the model's M1 util anchors are stated estimates; a stage
outside the window names the assumption to revise (rt_budget
RT_ASSUMPTION: vda -> ANE util/compute plan, moge -> GFLOP-per-keyframe
or package shape, upsample/surround/render -> GPU util, vt_* -> VT
offload). Fixture pair: golden/selftest_fixture/rt_pass.log (all ok,
exit 0) and rt_fail.log (surround missing -> exit 1; moge ratio 12.22
-> REVISE names the MoGe assumption). Pins:
Tests/DepthAnalysis/test_selftest_rt.py.

### s33 (2026-11-09) render cache key state matrix

Reviewed ThreeDRenderCoordinator.key (v2) against every user-visible
3D setting: mode (off/sbs/vr180), strength, comfort toggle, explicit
convergence_m, screen_deg, surround, over_budget + ipd_m (prefs-file
keys), quality + osdLine (UserDefaults), subtitles (mpv overlay).
Test: Tests/DepthAnalysis/test_render_key_matrix.py (Python mirror of
the Swift key + pixel semantics; 12 rows).

Correct today: mode, strength on the menu path (over_budget follows
strength > 1), comfort toggle, convergence, screenDeg on wide content,
surround; osdLine/subtitles/quality correctly absent from the key
(OSD/overlay/prepare-side respectively - but see F3).

Gaps found (pinned in the test; E-G key fix flips the pinned asserts):
- F1 collision (correctness): comfort-CAPPED regime (depth_scale > 1
  with over_budget = false - file-only, the menu ties over_budget to
  strength > 1): the rendered ipd is ipdM * c.depthScale (strength
  clamped), so ipdM matters beyond effectiveIPD = ipdM*depthScale, but
  the key carries only effectiveIPD. (ipdM .063, ds 2) and
  (ipdM .126, ds 1) share a key with different pixels -> stale render
  reuse.
- F2 churn: same regime, strength 2 -> 3 changes the key (via
  effectiveIPD) but not the pixels (strengthFactor clamps to 1).
- F3 collision via content (structural): the menu 'quality' setting
  steers the PREPARE config (depth content); the render key has no
  depth-version component, so depth re-prepared under a new quality
  reuses a stale render_shot file.
- Accepted (documented, no action): screenDeg past the portrait
  vertical cap shares one thetaH (churn, portrait only); mode sbs
  renders as vr180 today (churn while no sbs-specific output exists).

Recommended v3 key (E-G): when comfortActive, key on ipdM and
strengthFactor(depthScale, overBudget) instead of effectiveIPD + the
over_budget flag (fixes F1 + F2: ipdM always changes pixels, sf never
changes key without changing pixels); keep effectiveIPD for the fixed
path; add a depth-version component (e.g. the depth mp4's
size+mtime or the entry's prepare config stamp) to the sidecar key
(fixes F3).

## s34. Colour/format audit: source -> proxy -> depth -> render -> display

Per-dimension: what the code did before s34, what breaks, the fix shipped
here (reference + `Tests/DepthAnalysis/test_colorprobe.py`), and the Mac
port notes. Probe facts come from `tools/depth_analysis/colorprobe.py`
(one ffprobe read; verdicts ok/note/warn/fix/refuse). Mac equivalent:
AVAssetTrack formatDescriptions + `kCMFormatDescriptionExtension_*`
colour attachments + preferredTransform.

| dimension | before s34 | what breaks | fix |
|---|---|---|---|
| 8/10-bit | Mac: FrameReader reads the source at `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` for BOTH the proxy feed (NativePrepareRunner:201) and scdet luma (:140); widen10 shifts 8->10. Reference: proxy `format=yuv420p10le` keeps 10-bit; VDA input cv2 8-bit (model input, colour-noise only) | 10-bit SDR sources (phones) lose 2 bits -> gradient banding baked into the proxy; HDR10/HLG sources (iPhone default HDR) get crushed into 8-bit video range | Reference keeps 10-bit end-to-end (test: 10-bit gradient roundtrip, steps <= 1 code). Mac: read 10-bit sources as `420YpCbCr10BiPlanar{Video,Full}Range` matching the source range (VTShotEncoder already accepts 10-bit buffers) |
| limited vs full range | Mac: always video-range reads + untagged video-range proxy write (beginSource called WITHOUT sourceFullRange/sourceColor - NativePrepareRunner:202) | full-range sources get range-squashed by the VT conversion, or misread if VT passes samples through; either way the proxy lies about its content | Reference passes source tags through to the proxy (pinned: full-range tags survive). Mac: read the source's `kCMFormatDescriptionExtension_ContentLightLevelInfo`/range attachment, pass sourceFullRange + sourceColor into beginSource (the parameters already exist) |
| BT.709/2020/P3 primaries | Both lanes convert matrix-only; wide-gamut colours clip at rgba8 | P3 SDR slightly desaturates (acceptable); BT.2020 primaries + SDR transfer converts with the 2020 matrix (correct) | Note-only. Render output stays SDR sRGB for now |
| HDR10/HLG/Dolby Vision | Nothing gated: preflight is machine-only, prepare ran anything | Silent tone-clip at the first 8-bit video-range read (Mac) or the rgb24 render read (both lanes) | REFUSE in `PrepareFilm.probe_film` (open_film raises; play 2D). HDR is never silently tone-clipped. Mac: same verdicts from colour attachments in ThreeDMenu/prepare start; message the user, keep playback 2D |
| 4:2:0 chroma | Source-bleed baked in; swscale/VT upsample unpinned | Chroma edge mis-sited vs luma -> colour fringes on DIBR edges | Pinned: swscale upsample sites the chroma edge within 1px of the luma edge (test 10). Mac parity: verify VT's 4:2:0->BGRA conversion sites the same (<=1px) on the same synthetic clip; if not, add a half-sample chroma offset in the BGRA blit or decode proxy frames as 4:2:0 textures and upsample in the kernel |
| odd sizes | proxy black-pad bottom-right + sidecar unpadded size; depth edge-pad | none found | unchanged; test pins 97x63 -> 98x64 |
| anamorphic (SAR) | Mac: naturalSize = storage pixels, no SAR. Reference: cv2 storage pixels for depth; proxy storage pixels | depth+render geometry squeezed; hfov wrong; disparity scaled by SAR | normalize to square display pixels BEFORE depth and proxy (scale w*sar, setsar=1; test: sar 2:1 -> 128x64 in both). Mac: apply `track.formatDescriptions`/`cleanAperture` + SAR to a normalized display size and use it for FrameReader.size, the proxy writer and the depth input |
| rotated/portrait | Mac: naturalSize ignores preferredTransform; VT sample buffers are storage-orientation. Reference: ffmpeg autorotates the proxy but cv2 does NOT rotate the depth input | Mac: sideways depth+render with swapped dims. Reference: rotated proxy paired with UNROTATED depth - total misalignment | depth input switches to `read_shot_frames_normalized` (ffmpeg pipe, autorotate + same normalize as proxy) when the probe sees rotation/SAR (test: 96x64 rotate=90 -> 64x96 everywhere). Mac: apply preferredTransform to size and to every sampled buffer (or VTImageRotationSession) |
| VFR | Mac FrameReader seeks (k-0.5)/fps and reads sequentially; reference cv2 POS_FRAMES | frame index != content on VFR -> depth/proxy/render all misaligned, cuts at wrong frames | REFUSE (r_frame_rate vs avg_frame_rate > 0.2%): transcode to CFR first or play 2D. Mac: same check from nominalFrameRate vs minFrameDuration statistics |
| scdet input | Mac: 8-bit video-range luma; reference: native bit depth (10-bit source -> 10-bit scores) | scdet scores scale with bit depth: threshold 12 misses cuts on 10-bit sources | reference inserts `format=yuv420p` before scdet (test: 10-bit concat clip still cuts at frame 8). Mac: unchanged (already 8-bit) |
| untagged sources | swscale default bt470bg for ALL sizes; VT/mpv assume 709 for HD | untagged HD: reference rendered 601 while Mac/mpv showed 709 -> parity break + wrong colours | explicit size rule (>=1280 wide or >576 tall -> bt709 else bt470bg) pinned in reference decodes (SD = swscale default, so existing goldens do not drift) |

New module: `tools/depth_analysis/colorprobe.py` (probe / verdicts /
matrix_for / normalized_size / refuse_reasons / rgb_decode_scale).
open_film writes `color.json` (probe + verdicts + matrix + normalized
size) into the cache entry for the render lane and audit.

Render-lane notes: RenderShotWriter reads the proxy as 32BGRA (VT honours
the proxy tags) and writes the rendered mp4 UNTAGGED. Current content is
SDR BT.709 limited, which untagged players assume by size; when HDR
support arrives the writer MUST tag (or mpv will misrender). Until then
untagged is deliberate: a forced tag would break the same convention on
SD/601 sources.

## s35. Depth failure-mode robustness (real VDA-S + MoGe-2)

Harness: `tools/depth_analysis/failure_probes.py` (8 synthetic probe clips
x baseline/guarded, production-shaped: VDA fp16 ONNX stream (production
checkpoint) -> MoGe-2 keyframes -> LSQ/EMA align -> eased track -> metric
z -> comfort policy). Guards: `tools/depth_analysis/depth_guards.py`
(pure numpy, no-op outside their failure mode). Pins:
`Tests/DepthAnalysis/test_failure_guards.py`.

Measured (16f 160x90 probes, baseline -> guarded). Guarded numbers are
with the EMA fed the SAME texture weights as the residual fit
(ShotAligner.update(weights=...)); the unweighted-EMA run differed only
in jitter: glass 0.0020 -> 0.0007, overlay 0.0029 -> 0.0037, rest < 4%
(E-G a1cb3fb5 flag, fixed and re-measured):

| probe | finding | guard |
|---|---|---|
| sky | MoGe-2 54.8% non-finite (sky = +inf, known); VDA relative depth put sky AT the shot median depth (sky_leak 0.99) on flat synthetic skies - an inv-only sky detector cannot see it, the MoGe invalid mask is the reliable signal | sky_far_clamp(moge_finite=...): clamp MoGe-invalid + low-texture top-region pixels to the far plane (5th pct). On the real live bench clip MoGe invalid = 0.0% (no sky content) so the guard is a true no-op there |
| glass/reflections | double-motion did not destabilise the fit (resid 0.97, jitter 0.0007 with weighted EMA); VDA picks the dominant layer | none needed |
| fast pan + motion blur | resid 0.98 (fit poor on texture-only clips) but jitter 0.045 and comfort band holds | none needed |
| dark/noisy | jitter 0.246 (25% median inv change per frame) - the one real instability measured; VDA stream is already the temporal smoother, extra smoothing would cost Tier 1 detail | none shipped; monitor: report jitter_rel in selftest when the Mac bench lands |
| burned-in overlay (subtitles+logo+bars) | overlay pixels inherit scene depth while static on screen -> in 3D they slide | static_overlay_flatten: screen-space-static pixels (24.4% of the probe frame) set to the convergence plane + excluded from the fit; static scenes never masked |
| fade to black | VDA stream depth FREEZES through the fade (jitter 0.000) - already stable; depth during black frames is stale but invisible | fade_flatten kept as belt-and-braces (blend toward per-pixel temporal median by fade amount; bright frames byte-identical) |
| screen-in-screen | no instability (jitter 0.015); inner screen gets its own depth, which is correct | none needed |
| tiny faces | no instability (jitter 0.020) | none needed |

Align fit: fit_scale_shift_weighted (WLS; weights=None == the old LSQ
bit-for-bit) + texture_weights - broken regions (sky/noise) can't drag
the shot scale (pin: broken top band moves weighted scale error under
0.05 where unweighted is worse). The weights go into BOTH the residual
fit AND the ShotAligner EMA (update(weights=...)); feeding only the
residual fit leaves the rendered track on the unweighted fit (found by
E-G a1cb3fb5; the Swift port feeds weights into the EMA - keep parity).
s45 quality bar: whole-frame low texture (night/noise, mean local-std
<< hi) starves the weighted fit, so texture_weights blends toward
uniform by the frame's mean texture, w' = 1 + a(w - 1), a = min(1,
mean(tex)/hi) - dark e2 clip jitter p95 0.0819 -> 0.0776 (unweighted
floor 0.0773), live/cg unchanged (a = 1). Swift DepthGuards.swift
textureWeights mirrors the blend. Pins: Tests/DepthAnalysis/
test_failure_guards.py (item 5), test_quality_bar.py (e2 regression).

Port notes for E-G (Mac):
- sky: use the MoGe keyframe's non-finite mask (nearest keyframe, nearest-
  neighbour resize to depth res) + local luma std <= 3 + top half; clamp
  to the 5th percentile of valid inverse depth. Pure vImage/Accelerate.
- overlays: per-pixel temporal luma std < 2 with mean scene motion >= 4
  over the shot -> set to z_c and exclude from the align fit.
- fades: a = 1 - mean_luma/running_max, active at a >= 0.5; blend inv
  toward the per-pixel temporal median by a.
- align: weight LSQ pairs by clip(local_luma_std/8, 0.125, 1).
- All guards must be no-ops on healthy shots (pinned); never apply to
  brighten the depth signal itself (Tier 1 rule).

## s36. Output modes

Module `tools/depth_analysis/output_modes.py`; pins
`Tests/DepthAnalysis/test_output_modes.py` + `golden/mode_fixture/`
(synthetic 96x54, depth ramp + centre bump; relock: --relock). One eye
renderer (three projections, z-buffer nearest-wins, far-side row fill +
edge-run fill) + five packers.

| mode | canvas (WxH, source wxh) | projection | notes |
|---|---|---|---|
| full_sbs | 2w x h | perspective, 75 deg screen at source size | FLAT-DISPLAY DEFAULT: per-eye full resolution, direct mpv/3D-TV playback |
| half_sbs | w x h | same, each eye squeezed 2:1 | SAR 2:1 stretch on playback; horizontal sampling per eye IS halved (smaller files/decodes) - never claim "no resolution loss" |
| over_under | w x 2h | same, stacked L over R | full per-eye resolution; for OU displays/players |
| anaglyph | w x h | same, Dubois red/cyan combine | any display + red-cyan glasses; Dubois matrices cut retinal rivalry vs naive red/cyan; same geometry, crosstalk is a display property |
| vr180 | 2N x N, N = eye_n_for(h) | equirect 180x180 per eye | HEADSET DEFAULT: adds the s28 surround outside the film footprint + Spherical Video V2 metadata |
| eye-swap | any | any | swap=True exchanges L/R at render time (cross-eye, cable fixes) - not a re-encode |

Comfort/surround/overlay rules:
- Comfort (s25) is identical across modes: the per-eye depth content is
  the same, so shot-median convergence + baseline shrink + near clamp
  apply unchanged. half_sbs halves PIXEL disparity; the player's stretch
  restores identical ANGULAR disparity.
- Surround exists only in vr180 (canvas outside the film footprint);
  flat modes fill the frame with the film.
- Overlays (subtitles) sit at the convergence plane in every mode; vr180
  places them in angular UI space (s27), packed flat modes at zero
  disparity.

Player frame-packing metadata (MODE_METADATA in output_modes.py):
full/half sbs -> mpv stereo mode sbsl (+SAR 2:1 for half); over_under ->
abl; anaglyph -> none (ordinary 2D); vr180 -> sbsl + Spherical Video V2
(stereo left-right, projection equirect, 180x180 bounds). On the
container: tag via StereoMode/spherical metadata, not codec SEI.

Defaults: flat display -> full_sbs (full per-eye resolution, universal
player support; half_sbs only when decode/bandwidth-constrained).
Headset -> vr180 (immersion + surround + standard metadata).

Why this fixes the known gap: the previous "sbs" ran the vr180 equirect
path (film on a curved canvas region); flat modes now perspective-project
the virtual screen at the source size. equirect180 eye == legacy eye on
covered pixels (pinned), so existing vr180 goldens are unaffected.

Port notes for E-G/delivery:
- Metal kernel: add the perspective projection branch (u = f*px/pz,
  v = f*py/pz after the toe-in rotation) - the eye loop, z-buffer and
  fill passes are unchanged; packers are blits except anaglyph (one
  3x3-matrix pass, DUBOIS_L/DUBOIS_R in output_modes.py, gamma-coded).
- Half-sbs squeeze = INTER_AREA box average (pinned within 1 code).
- eye_n_for / surround: reuse the existing vr180 path as-is.
- Menu: default full_sbs on flat, vr180 when a headset route exists;
  expose eye-swap per mode. s33 v3 key: the mode component already
  covers these; the swap bit already exists.

## s37. Stereo-source handling (never run 2D->3D on 3D sources)

Module: `tools/depth_analysis/stereo_probe.py`. Pins:
`Tests/DepthAnalysis/test_stereo_probe.py` (synthetic stereo clips built
from the s36 fixture ground truth, tagged + untagged + real 2D films).

Detection runs in three layers, cheapest first; the first verdict wins:

1. **Container/metadata (authoritative).** ffprobe stream side_data
   "Stereo 3D" (MKV StereoMode: left_right/right_left with inverted=1 ->
   eye swap, top_bottom, row_interleaved) and MP4/MOV spherical stereo
   (Spherical Video V2 stereo_mode) and MV-HEVC (hvc1 Multiview profile).
   Verified empirically on ffmpeg 4.4: MKV `-metadata:s:v stereo_mode=`
   surfaces as side_data; h264 frame-packing SEI does NOT surface in
   ffprobe at all - so an h264 frame-packed file falls through to layer 3.
2. **Filename hints (weak only).** `.sbs.` / `_3d_sbs` / `vr180` etc.
   produce a CANDIDATE layout, never a verdict: they only preselect the
   split shape tested by layer 3. Filename alone never routes.
3. **Pixel confirm (the gate).** Split per candidate layout (SBS +
   over-under are both tried when there is no candidate), then NCC over
   horizontal shifts on HIGH-PASSED grey halves (grey minus sigma-3
   blur). High-passing is the false-positive discriminator: adjacent
   halves of a smooth 2D frame correlate strongly in raw grey (up to
   0.61 on the real 2D bench clips) but their edge content is
   independent (hp NCC <= 0.04), while true stereo keeps matching edges
   at the disparity shift (0.95 on the fixture). Confirm threshold
   hp_ncc >= 0.4. Measured false-positive rate: 0/6 on the real 2D
   bench clips (live/anim/dark, SBS and OU splits) + synthetic
   split-screen. Duplicated-half fake SBS (L == R) also confirms and
   routes to passthrough - harmless, it has no depth to lose; the
   asymmetry that matters is never feeding real stereo into 2D->3D.

Passthrough (no depth stage, no quality loss): eyes are split per the
detected layout and repacked into any s36 output mode
(`passthrough()`): full/half SBS and over-under are lossless repacks;
anaglyph re-encodes colour (inherent); eye-swap is a transpose of the
pack order (or the metadata inverted flag); vr180 output places
perspective eyes on the equirect180 canvas at the convergence plane;
vr180 sources reproject to flat modes via `vr180_to_perspective`.
MV-HEVC is detected and reported but NOT decoded here (needs the Mac
VideoToolbox path) - it falls back to the menu with a "native 3D
source" note.

Warn-only comfort check of baked-in disparity: `measure_disparity()`
does per-block shift-NCC (32 px blocks, +-W/8 search, high-passed grey,
MAD outlier rejection of isolated block mislocks), upscaling small
sources first, and reports px + degree percentiles under an assumed 90
deg per-eye hfov (the bake's fov is unknowable; degrees are indicative)
plus the fraction over the 2 deg budget. On the synthetic bake the
median lands on the analytic disparity exactly (0.38 px vs 0.38 px);
the 96 px smooth-gradient fixture tail runs ~3x, on real-resolution
textured content the tail tightens. A warn NEVER blocks the passthrough
- it is a menu note ("baked disparity exceeds the comfort budget").

Misdetect -> menu override: the user can force 2D->3D (treat as flat)
or force a specific stereo format from the prepare-film menu; the
override wins over all three layers and is logged in the render
manifest. Wrong-SBS-detected-as-2D is the only silent failure left
(metadata absent AND hp NCC < 0.4, e.g. near-zero-disparity broadcasts);
the override is the documented recovery.

Port notes for E-G (Mac):
- Layer 1: AVAsset track formatDescriptions (kCMFormatDescriptionExtension_StereoViewInterpretation
  for MV-HEVC) + container atoms; MKV via the same ffprobe side_data.
- Layer 3: downsample to <= 512 wide before the hp-NCC scan; threshold
  0.4 at that scale (pinned by the synthetic tests here).
- measure_disparity: same block-NCC algorithm (no cv2 StereoBM - it
  scattered 10x past ground truth on weak texture).
- Passthrough repacks are memory ops; vr180 placement reuses the s36
  Metal perspective->equirect branch.

## s38. Graceful-degradation state machine (3D path)

Module: `tools/depth_analysis/degrade_fsm.py` (pure transition table, no
I/O / clocks / mpv objects). Pins: `Tests/DepthAnalysis/test_degrade_fsm.py`
- TOTAL: all 7 states x 22 events pinned (154 pairs, unlisted pairs are
logged no-op self-loops), no dead ends (every state reaches
READY_STEREO), mpv-lifecycle invariant, one golden log line.

States: INIT / UNAVAILABLE_FLAT / PREPARING_FLAT / READY_STEREO /
LGD_HOLD / FLAT_DEGRADED / PREP_BLOCKED.

Invariants (owner rules, pinned):
- Playback never interrupted. No action in any transition restarts mpv,
  seeks, pauses, or touches audio (the test asserts the forbidden-action
  list over every pair). 3D<->2D switches swap ONLY the render
  pipeline's depth input, so a/v sync cannot break.
- Tier 1 never lowered: failure falls back to 2D or last-good depth,
  never to cheaper depth. MoGe licence-gated off = 3D unavailable (no
  VDA-only fallback depth).
- HDR refused for 3D plays as UNTOUCHED native 2D HDR (s34: never
  silently tone-clipped).
- Every failure surfaces: badge while degraded, menu note when
  persistent, one short OSD line on stereo<->flat switches, never an
  audio cue.

Failure/limit behaviours (state walk):
- kit missing / hash mismatch: UNAVAILABLE_FLAT, menu note; bad hash =
  treat as tampered, never run; retry on kit_ok (download = owner-Mac).
- MoGe licence-gated off: UNAVAILABLE_FLAT, menu note, retry on
  re-probe.
- prepare throws on a shot: retry with backoff; 3rd consecutive failure
  marks the shot failed - its range plays flat, the rest of the film
  plays stereo (coverage events drive the switch).
- HDR / VFR refusal at probe: UNAVAILABLE_FLAT with menu note.
- thermal gate trips mid-play: PREPARE pauses, badge; playback of the
  prepared range continues in 3D; auto-resume on thermal_clear. If the
  playhead outruns the prepared range the normal uncovered walk below
  applies.
- depth not ready at playhead (incl. decode hitch): LGD_HOLD - hold the
  last good depth frame up to 500 ms, pipeline untouched; recovered ->
  stereo, the user saw nothing; timeout -> FLAT_DEGRADED (2D + OSD),
  never stall a frame.
- disk full for .dzc: prepare pauses, badge; playback unaffected (stereo
  if covered); auto-resume on disk_freed.
- seek beyond prepared range: same uncovered walk (LGD_HOLD ->
  FLAT_DEGRADED -> READY_STEREO when caught up).
- source change / re-prepare: from ANY state -> INIT, prepare aborted,
  new playback starts flat immediately, never waits for depth.
- app quit mid-prepare: persist; relaunch re-probes; cache survives,
  at most the in-flight shot is lost (s-existing .dzc resume contract).
- resume: relaunch -> INIT -> probe_ok -> PREPARING_FLAT -> covered ->
  READY_STEREO.

Log line per transition (selftest greps; act field is space-free):
  3dfsm from=<STATE> ev=<event> to=<STATE> act=<a1|a2|-> note=<reason>
Golden pin:
  3dfsm from=READY_STEREO ev=playhead_uncovered to=LGD_HOLD act=act_hold_lgd note=...

Port notes for E-G/delivery:
- The Mac player owns clocks: lgd_timeout = 500 ms after EV_UNCOVERED
  without EV_COVERED; shot_error_limit = 3 consecutive per shot.
- Events come from existing hooks: coverage from the .dzc index /
  progress.json the OSD already reads; disk_full from the .dzc writer
  ENOSPC; thermal from the thermalState observer (s19); kit/licence/
  HDR/VFR from the probe at source open (s34 colorprobe, kit_hash).
- Every transition's log line goes to the selftest log verbatim; the
  selftest scenario suite drives the synthetic event walks pinned in
  test_degrade_fsm.py and diffs the log lines.
- Render side: act_play_flat / act_play_stereo / act_hold_lgd are
  uniform/texture swaps on the existing Metal path (s36) - never an
  AVPlayer/mpv item rebuild.

## s39. Dress rehearsal (reference) + first-Mac-run pass checklist

`tools/depth_analysis/rehearsal.py` produces, from the reference on
Linux, the exact artefact set the first Mac run must produce for the
live and CG clips (36f @ 24 fps, 640x360 proxy), and runs
`selftest_check.py` against the logs end to end (exit 0 = PASS).
Pin: `Tests/DepthAnalysis/test_rehearsal.py` (12f; both clips).

Artefacts per clip: gor3d-selftest.log (v1 format), shot0.dzc,
align_track.json (weighted-EMA track, kf stride 12), render_full_sbs.mp4,
render_vr180.mp4, render_key_v3.txt, plus out-root
rehearsal_expected.json + manifest.json (sha256 of every artefact).

Rehearsal log vs the real Mac log: only measured-vs-modelled values may
differ (stage ms, rtstage ms, thermal series, depth values, hashes,
jitter_rel, track numbers). The rehearsal log flags itself:
begin header carries `reference-linux\nrehearsal\nSYNTHETIC-TIMING`,
note key=rehearsal, note key=thermal_source value=synthetic (the Linux
box has no thermalState), note key=precision_source (reference runs the
fp32 torch export -> fp32_used; the Mac must show fp16_used>=1).
Rehearsal stage budgets live in rehearsal_expected.json (slow CPU box);
the Mac is checked against selftest_expected.json, never this file.

FIRST MAC RUN PASS CHECKLIST - the log must contain, per clip:
 1. `gor3d-selftest v1 begin ...` and a closing `end errors=0`
 2. `note key=clip value=<W>x<H> <N>f @<fps> ...`
 3. `stage name=clip_write|prepare_total|render_shot ms=... n=1 ...`
    within the selftest_expected.json budgets
 4. all 7 `rtstage name=` lines (vda, moge, upsample, surround, render,
    vt_decode, vt_encode) - a missing line FAILS; a ratio outside
    [0.25, 4] vs rt_budget is a REVISE finding naming the assumption
 5. `note key=rt_config value=fps=.. vr180=.. depth_rate=.. surround_opt=..`
 6. `thermal ...` series + `thermal_peak level=<0|1> transitions=...`
    (peak <= 1 per the s19 policy)
 7. `note key=moge_precision value=fp16_used>=1 ...` (or the fp32
    fallback); fp16_rejected>0 is a finding
 8. `depth min=... max=... nan=0 inf=0 count=N` with N = frames x
    letterbox(clip W x H) picture (266x150 for 640x360), min > 0,
    max < 1e6 (millimetres)
 9. `note key=first_3d_frame_sha256 value=<64 lowercase hex>`
    (mismatch vs a recorded reference is a warning, never a fail)
10. `note key=jitter_rel value=<f>` (s35 metric; healthy < 0.05,
    dark/noisy 0.25 is the known instability)
11. `note key=render_key_v4 value=v4|<method>|...` matching the 190w W3
    v4 format (method | comfort|ipd..|sf.. | mode | conv | eye_n | codec
    | swap | screen_deg | surround | depthStamp). 190w W3 tiers:
    T1 mlbw_l2_inpaint_video > T2 mlbw_l2_inpaint > T3 row_flow_v3, with
    dibr_golden the last-resort fallback, LABELLED "fallback" wherever
    the method surfaces. The method field sits directly after the
    version: a method/tier change re-prepares every cached stand-in
    render, and the v3->v4 bump itself invalidates all v3-keyed caches
    (existing marker-only eviction, below). Swift edit owned by E-G
    from the 190v spec; Python mirror rehearsal.render_key_v4 +
    test_render_key_matrix key_v4 pin it.
12. `3dfsm from=... ev=... to=... act=... note=...` transition lines
    (s38) for the scripted degradation walk, format pinned by
    test_degrade_fsm.py's golden line
13. any `error i=... msg=...` lines bucket cleanly
    (gh/kit/coreml_load/compute_plan/other) and fail the run

And on disk: shot0.dzc (contract container), align_track.json
(weighted EMA track), render_<mode>.mp4 for full_sbs + vr180,
render_key_v3.txt.

Port notes for E-G/delivery: diff the Mac log against the rehearsal log
line FAMILY by line family; any line family absent on either side is a
format bug to fix before reading numbers.
