# 3D analysis cache format (190t/190u) - read contract for the native stereo lane

Cache root: ~/Library/Application Support/gor/depth-cache (FIXED; H-K lane's DepthCachePaths, bb2dc675; cache.DEFAULT_CACHE_ROOT).
The film currently open in 3D mode is always pointed to by the FIXED path
`<cache_root>/current-film.json`:
  {"progress_path": "<abs path to progress.json>", "n_frames": N, "cache_key": "<key>"}
Swift reads this pointer and MUST NOT reimplement cache_key. The pointer is
rewritten atomically (tmp + rename) on every film open in 3D mode.

Per-film entry: `<cache_root>/<cache_key>/` (cache_key = sha256 of
path+size+mtime+content-sample, see cache.py; marker file .gor-cache-entry).
Files:
- depth_shot_NNNNN.dzc  Mac-path depth container, superseding depth HEVC
                  under CONTRACT-190v.md section 16. Lossless LZFSE planes
                  of little-endian uint16 w10, without chroma or colour tags.
                  Header GORDZ001; per-frame payload length and CRC32;
                  offset index and GORDZEND trailer certify completeness.
                  Readers may accept the leading CRC-valid prefix for resume.
                  Decode v = w10/1023*1024, Z = 256/v; zero remains masked.
                  Pair frames with the unchanged source proxy by film PTS.
                  Executable format: depth_container.py and its golden tests.
                  The entries below for depth HEVC document the legacy
                  reference encoder, not the Mac-path default.
- progress.json   {"prepared": [[first,last], ...]}  inclusive frame ranges,
                  always Tier 1 (windowed, per-shot reset). OSD text:
                  "3D prepared: N/TOTAL frames" / "3D prepared: full film".
- cuts.json       {"cuts": [f...], "shots": [[first,last], ...]} inclusive.
- render-ready.json  per-shot ready flags + failures for the Swift render
                  coordinator (CONTRACT-190v section 8): shots[] {shot, start,
                  end, depth_ready, source_ready, ready, failed, error},
                  n_shots, n_ready, n_failed, updated_at. Atomic rewrites.
- meta.json       model, checkpoint, window=32, mode, fps, frames.
- depth_shot_NNNNN.mp4  per shot: 10-bit HEVC lossless (x265 lossless=1),
                  Main 10 4:2:0 yuv420p10le - depth on luma, chroma neutral;
                  VT/AVFoundation-decodable (gray10le/Rext is not). Full-range
                  tagged (VUI video_full_range_flag=1, colr pc, bt709): VT
                  returns stored luma unscaled as 420YpCbCr10BiPlanarFullRange. Edge-padded
                  to even HxW; container packet PTS in film seconds. Luma w10 ->
                  inverse depth v = w10/1023*1024, Z = 256/v metres; w10 == 0 =
                  masked/infinity. Decode on Mac via AVFoundation/VideoToolbox;
                  the vendored gorav ffmpeg has no HEVC (--disable-everything).
- depth_shot_NNNNN.json per shot: start, end (inclusive), input_size,
                  depth_width, depth_height (unpadded), align_scale, align_shift,
                  source_width, source_height (unpadded proxy size).
- source_shot_NNNNN.mp4  per shot: source-picture proxy for the renderer's
                  rgba8 texture feed (AVFoundation is the only in-app decoder).
                  HEVC Main 10 yuv420p10le, x265 CRF 10 (visually lossless),
                  native source resolution (never a thumbnail), colour tags
                  passed through from the source (untagged source -> untagged
                  proxy). Same PTS base as the depth mp4: proxy frame i pairs
                  with depth frame i by PTS.

Legacy HEVC depth semantics (load-bearing for the Metal kernel; identical to
CONTRACT-190v.md section 1): each stored luma sample is a 10-bit code
w10 -> inverse depth v = w10/1023*1024 (inverse metres after D scale),
Z = 256/v metres along the optical axis; w10 == 0 = masked/infinity,
rendered at infinity. In the VT planar format the 10-bit code is
LEFT-aligned in 16-bit words (w10 << 6); the decoder shifts back 6 bits.
Values derive from raw VDA-S relative output aligned per shot to MoGe-2
metric depth (align.py LSQ+EMA, reset at cuts), keyed by container packet
PTS in film seconds. FoV comes from fov_track.json (per-shot median
hfov + confidence + keyframe values). Geometry contract: native lane's
tools/vr180_ortho_ref.py (commit 237d1adf). dibr_golden.py is the
pixel-level golden harness for the flat-SBS path (coverage metric included).

Eviction: marker-only, oldest-mtime-first under cap_bytes; Swift must treat
every entry file as possibly disappearing between open and read (re-read the
pointer, tolerate ENOENT, fall back to "not prepared").

Weights: row_flow_v3 + mlbw weights are approved for the owner's private
Mac build ONLY (architect 190w W1, 2026-11-09, relayed by Main; iw3
training code uses an Apple Depth Pro fork so training-data provenance is
unconfirmed; distribution beyond the owner's Mac = go-live gate). They
ship as gor-kit-nunif-4743841e.tar (gorav release gor-kit-2026-11-09,
sha256 4743841e...e648) via the models.lock.tsv owner-private-mac row. The named CC-BY-NC depth checkpoints (Any_V2_*, Distill_Any_*,
Ultimate_DAV2_*) stay excluded permanently. No model weights are vendored
in this repo (models.lock.tsv pins sha256 + licence class).
