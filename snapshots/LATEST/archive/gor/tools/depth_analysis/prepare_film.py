"""190u third analysis mode: "Prepare film" orchestration (analysis lane),
190v contract format (CONTRACT-190v.md, same directory).

Whole-file background Tier-1 analysis into the content-keyed cache:
  open -> detect/cached cuts -> per shot: VDA-S windowed depth + MoGe-2
  metric/FoV on keyframes + per-shot LSQ/EMA alignment -> npz in contract
  format (fp16 inverse depth, D=256, PTS-keyed) + fov_track.json.
  Work happens in small time-budgeted chunks so the gor app can run this at
  LOW priority (idle-time / background thread, nice>0) without touching
  interactive playback. Fully resumable: a killed run loses at most the
  in-flight shot. The OSD reads status() / progress.json for the prepared
  range; the prepared range is always Tier 1. Tier-1 quality is never
  lowered for heat (owner rule via 190t/190u); heat logic is out of scope.

OSD text format is coordinated with the delivery lane
(agent-01M6V74P025QE8PEY7VH904TQN); status() returns the raw ranges and a
ready-made short string so both lanes render the same thing.
"""
import json
import os
import time

import numpy as np

import align as align_mod
import colorprobe
import cuts as cuts_mod
import moge_fov
import vda_windowed

D_SCALE = 256.0  # contract: stored v = D_SCALE / Z (metres); CONTRACT-190v.md
FOV_KEYFRAME_STRIDE = 12
FOV_CONF_SPREAD_DEG = 15.0
V_INV_MAX = 1024.0  # 10-bit normalization: w10 = 1023 * (v / V_INV_MAX)
# v in [0, 1024] inverse metres -> Z in [0.25 m, inf); w10 == 0 = masked/infinity


def vt_encode_spec():
    """CONTRACT-190v section 9: the observable tags ANY depth/source encoder
    must produce. libx265 (below) is the Linux/reference encoder; on the Mac
    an AVAssetWriter/VideoToolbox encoder must produce files with these exact
    probe-visible properties. The test pins x265 output == this spec; a Mac
    encoder test pins its output the same way."""
    common = {"codec_name": "hevc", "profile_contains": "Main 10",
              "pix_fmt": "yuv420p10le", "container": "mp4",
              "pts_base": "start_frame/fps (film seconds, container packet PTS)"}
    return {
        "depth": dict(common, color_range="pc", color_space="bt709",
                      color_transfer="bt709", color_primaries="bt709",
                      vui="video_full_range_flag=1 in the HEVC bitstream, not only colr"),
        # source proxy: same codec/container/PTS base, but colour tags PASS
        # THROUGH from the source (untagged source -> untagged proxy; forcing
        # bt709 shifts colours on SD/untagged content).
        "source": dict(common, color_tags="pass through from source; no forcing"),
        "vt_guidance": {
            "codec": "kCMVideoCodecType_HEVC, profile HEVC_Main10_AutoLevel",
            "pixel_buffer": "kCVPixelFormatType_420YpCbCr10BiPlanarFullRange",
            "color_props": "AVVideoColorPropertiesKey bt709/bt709/bt709, full range (depth file only)",
            "note": "Mac lane verifies which VT key sets the VUI flag on device"}}


def _check_encoder(encoder):
    if encoder != "x265":
        raise RuntimeError(f"encoder {encoder!r} not available on this platform "
                           "(only 'x265' here; on macOS the VT encoder must "
                           "produce CONTRACT-190v section 9 tags)")


def _pad_even(a):
    """Pad [T,H,W] to even H/W by edge replication (4:2:0 needs even dims)."""
    t, h, w = a.shape
    hp, wp = h + (h & 1), w + (w & 1)
    if (hp, wp) == (h, w):
        return a, h, w
    out = np.empty((t, hp, wp), dtype=a.dtype)
    out[:, :h, :w] = a
    out[:, h:, :] = out[:, h - 1:h, :]
    out[:, :, w:] = out[:, :, w - 1:w]
    return out, h, w


def write_depth_hevc(path, inv_depth, fps, start_frame, encoder="x265"):
    """Write one shot as 10-bit HEVC lossless (x265) in mp4, Main 10 4:2:0.

    inv_depth: float array [T,H,W], v = D_SCALE / Z. Quantized to 10 bits:
    w10 = round(1023 * v / V_INV_MAX). The 10-bit data rides the LUMA plane of
    a yuv420p10le stream with constant neutral chroma (512): gray10le encodes
    as HEVC Rext 4:0:0 which VideoToolbox does NOT decode; Main 10 4:2:0 is
    hardware-decoded by VT on every Apple-silicon Mac and readable by
    AVFoundation (mp4 container - mkv is not). x265 lossless=1 is bit-exact
    per plane, so luma roundtrips exactly (Tests/DepthAnalysis/test_depth_hevc.py).
    Odd H/W are edge-padded to even; the sidecar json records depth_width/
    depth_height (unpadded). Container PTS starts at start_frame / fps."""
    import subprocess

    _check_encoder(encoder)
    t, h, w = inv_depth.shape
    hp, wp = h + (h & 1), w + (w & 1)
    ch = np.full((hp // 2, wp // 2), 512, dtype=np.uint16)

    def frames():
        # stream per frame: quantising the whole shot at once costs 8x its
        # size in peak RAM (float64), which OOMs long shots on small hosts
        for i in range(t):
            q = np.clip(np.rint(inv_depth[i].astype(np.float32)
                                / V_INV_MAX * 1023.0),
                        0, 1023).astype(np.uint16)
            q, _, _ = _pad_even(q[None])
            yield np.concatenate([q[0].ravel(), ch.ravel(), ch.ravel()]).tobytes()
    # Full-range signalling (delivery lane): x265 range=full writes the VUI
    # video_full_range_flag in the HEVC stream; the -color_* flags tag the
    # container to match, so VideoToolbox returns stored luma unscaled when
    # read as kCVPixelFormatType_420YpCbCr10BiPlanarFullRange. Matrix tagged
    # bt709: a consumer converting YUV->RGB full-range gets gray == luma.
    cmd = ["ffmpeg", "-y", "-v", "error",
           "-f", "rawvideo", "-pix_fmt", "yuv420p10le", "-s", f"{wp}x{hp}",
           "-r", str(fps), "-i", "-",
           "-c:v", "libx265", "-x265-params", "lossless=1:range=full",
           "-pix_fmt", "yuv420p10le",
           "-color_range", "pc", "-colorspace", "bt709",
           "-color_primaries", "bt709", "-color_trc", "bt709",
           "-output_ts_offset", f"{start_frame / fps:.6f}",
           "-movflags", "+faststart", "-f", "mp4", path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    for fb in frames():
        proc.stdin.write(fb)
    _, err = proc.communicate()
    if proc.returncode != 0:
        raise RuntimeError("depth hevc encode failed: " + err.decode()[-400:])


def write_source_hevc(path, video_path, s, e, fps, encoder="x265", normalize=None):
    """Write the source-picture proxy for one shot: source_shot_NNNNN.mp4.

    The Metal renderer needs the source picture as an rgba8 texture and
    AVFoundation is the only in-app decoder, so each shot's source frames are
    re-encoded as a VT-readable HEVC mp4 next to depth_shot_NNNNN.mp4.
    Quality first: native source resolution (never a thumbnail), HEVC Main 10
    yuv420p10le CRF 12 (visually lossless for an rgba8 target), frames
    [s, e] inclusive, container PTS of frame s = s/fps (identical base as
    the depth mp4, so frame i of the proxy pairs with depth frame i by PTS).
    Odd HxW is padded (black, bottom-right) to even; the sidecar json's
    source_width/source_height carry the unpadded size.

    s34 normalize: optional (w, h) from colorprobe.normalized_size. Sources
    with non-square pixels or a display-matrix rotation are scaled to square
    display pixels (bicubic, setsar=1) so the proxy, the depth input and the
    render all share display geometry. Rotation itself is applied by
    ffmpeg's input autorotation (on by default); normalize only scales.
    None -> the filter chain is byte-identical to pre-s34."""
    import subprocess

    _check_encoder(encoder)
    # Pass through the source's own colour tags; when the source is untagged,
    # leave the proxy untagged too so the player applies the same convention
    # it would have applied to the source (a forced bt709 tag shifts colours
    # on SD/untagged content that players decode as bt601).
    pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                         "-show_entries",
                         "stream=color_range,color_space,color_transfer,color_primaries",
                         "-of", "json", video_path],
                        capture_output=True, text=True)
    tags = json.loads(pr.stdout)["streams"][0]
    color_flags = []
    for field, flag in (("color_range", "-color_range"), ("color_space", "-colorspace"),
                        ("color_transfer", "-color_trc"), ("color_primaries", "-color_primaries")):
        v = tags.get(field)
        if v and v not in ("unknown", "unspecified"):
            color_flags += [flag, v]

    norm = f"scale={normalize[0]}:{normalize[1]}:flags=bicubic,setsar=1," if normalize else ""
    vf = (f"select='between(n\\,{s}\\,{e})',setpts=PTS-STARTPTS," + norm +
          "pad=ceil(iw/2)*2:ceil(ih/2)*2:0:0:black,format=yuv420p10le")
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", video_path,
           "-vf", vf, "-frames:v", str(e - s + 1),
           "-vsync", "passthrough",
           "-c:v", "libx265", "-x265-params", "crf=10",
           "-pix_fmt", "yuv420p10le",
           *color_flags,
           "-output_ts_offset", f"{s / fps:.6f}",
           "-movflags", "+faststart", "-an", "-f", "mp4", path]
    proc = subprocess.run(cmd, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError("source proxy encode failed: " + proc.stderr.decode()[-400:])


def write_render_ready(entry, shots, failures=None):
    """Progress/ready sidecar the Swift render coordinator polls (contract 8):
    render-ready.json, one row per shot with ready flags + failure state.
    Written atomically after every per-shot mutation. A shot is failed when
    its last attempt raised; a failed shot is retried on the next chunk (it
    is never marked prepared), and the failure clears when it succeeds."""
    import time
    failures = failures or {}
    existing = set(os.listdir(entry.dir))
    rows = []
    for i, (s, e) in enumerate(shots):
        d = f"depth_shot_{i:05d}.mp4" in existing
        sp = f"source_shot_{i:05d}.mp4" in existing
        err = failures.get(str(i)) or failures.get(i)
        ready = d and sp
        rows.append({"shot": i, "start": s, "end": e,
                     "depth_ready": d, "source_ready": sp, "ready": ready,
                     "failed": (err is not None) and not ready,
                     "error": None if ready else err})
    doc = {"shots": rows, "n_shots": len(shots),
           "n_ready": sum(1 for r in rows if r["ready"]),
           "n_failed": sum(1 for r in rows if r["failed"]),
           "updated_at": time.time()}
    entry._write("render-ready.json", doc)
    return doc


def find_shot_at_pts(entry_dir, pts):
    """Film PTS (seconds) -> which depth mp4 holds that frame.

    E-G/delivery call-site helper (contract section 7): reads cuts.json and
    fov_track.json (fps) from a cache entry dir. Returns
    {"shot": i, "mp4": path, "frame": f, "frame_in_shot": f - s,
     "shot_start_pts": s / fps, "shot_end_pts": e / fps}
    or None when no prepared shot covers that PTS. Shot frame ranges are
    inclusive [start, end]; inside the mp4, frames are in decode order and
    the container PTS of frame `start` is start / fps, so a PTS-keyed
    reader can verify directly."""
    cuts = json.load(open(os.path.join(entry_dir, "cuts.json")))
    fps = json.load(open(os.path.join(entry_dir, "fov_track.json")))["fps"]
    f = int(round(pts * fps))
    for i, (s, e) in enumerate(cuts["shots"]):
        if s <= f <= e:
            mp4 = os.path.join(entry_dir, f"depth_shot_{i:05d}.mp4")
            if not os.path.exists(mp4):
                return None  # shot known but not prepared yet
            src = os.path.join(entry_dir, f"source_shot_{i:05d}.mp4")
            return {"shot": i, "mp4": mp4, "frame": f, "frame_in_shot": f - s,
                    "source_mp4": src if os.path.exists(src) else None,
                    "shot_start_pts": s / fps, "shot_end_pts": e / fps}
    return None


def read_depth_hevc(path, size=None, max_frames=None):
    """Decode a depth mp4 back to (float32 inverse depth [T,H,W], start pts).

    size: optional (h, w) to crop the edge padding (from the sidecar json's
    depth_height/depth_width); without it the padded luma is returned.
    max_frames: optional lean decode of only the first N frames (whole-file
    decode OOMs small hosts on long shots)."""
    import subprocess

    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "stream=width,height",
                          "-of", "json", path], capture_output=True, text=True)
    info = json.loads(out.stdout)["streams"][0]
    wp, hp = int(info["width"]), int(info["height"])
    pk = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                         "-show_entries", "packet=pts_time", "-of", "csv",
                         "-read_intervals", "%+#1", path],
                        capture_output=True, text=True).stdout
    start = float(pk.strip().splitlines()[0].split(",")[1]) if pk.strip() else 0.0
    cmd = ["ffmpeg", "-v", "error", "-i", path]
    if max_frames is not None:
        cmd += ["-frames:v", str(max_frames)]
    d = subprocess.run(cmd + ["-f", "rawvideo", "-pix_fmt", "yuv420p10le",
                              "-"], capture_output=True)
    raw = np.frombuffer(d.stdout, dtype=np.uint16)
    words = hp * wp + 2 * (hp // 2) * (wp // 2)
    n = raw.size // words
    y = np.empty((n, hp, wp), dtype=np.uint16)
    for i in range(n):
        y[i] = raw[i * words: i * words + hp * wp].reshape(hp, wp)
    if size is not None:
        y = y[:, :size[0], :size[1]]
    return y.astype(np.float32) / 1023.0 * V_INV_MAX, start


class PrepareFilm:
    def __init__(self, cache, checkpoint, input_size=518, chunk_seconds=20.0,
                 moge_checkpoint=None):
        self.cache = cache
        self.checkpoint = checkpoint
        self.input_size = input_size
        self.chunk_seconds = chunk_seconds
        self.moge_checkpoint = moge_checkpoint
        self._model = None
        self._moge = None
        self._probe = None  # s34 colorprobe dict for the open film

    def probe_film(self, video_path):
        """s34 colour/format gate (CONTRACT-190v s34). Probes the source,
        returns the colorprobe dict. Raises RuntimeError naming every refuse
        verdict (HDR/Dolby Vision are never silently tone-clipped; VFR
        breaks frame-indexed prepare). Cache entries store color.json so
        the render lane and the Mac port see the same facts."""
        p = colorprobe.probe(video_path)
        bad = colorprobe.refuse_reasons(p)
        if bad:
            raise RuntimeError("3d prepare refused (" + video_path + "): " + "; ".join(bad))
        return p

    def _cuts_for(self, entry, video_path, fps, n_frames):
        """Shot boundaries, cached in the entry (cuts.json) after first run."""
        cached = entry._read("cuts.json", None)
        if cached is not None:
            return [tuple(s) for s in cached["shots"]]
        cut_list = cuts_mod.detect_cuts(video_path, fps)
        shots = cuts_mod.shots_from_cuts(n_frames, cut_list)
        entry._write("cuts.json", {"cuts": list(cut_list), "shots": [list(s) for s in shots]})
        return shots

    def open_film(self, video_path, fps, n_frames):
        """Auto-start hook: call when a film is opened in 3D mode. Returns
        the shot list; the caller then schedules work_chunk() at low priority.

        Also writes the stable current-film pointer the delivery lane's OSD
        reads: <cache_root>/current-film.json (fixed path, always the film
        currently open in 3D). Swift reads that pointer and never
        reimplements cache_key."""
        self._probe = self.probe_film(video_path)
        entry = self.cache.entry(video_path, create=True)
        entry._write("color.json", {"probe": self._probe,
                                    "matrix": colorprobe.matrix_for(self._probe),
                                    "normalized_size": list(colorprobe.normalized_size(self._probe)),
                                    "verdicts": [[d, s, t] for d, s, t in colorprobe.verdicts(self._probe)]})
        shots = self._cuts_for(entry, video_path, fps, n_frames)
        entry.touch_meta(mode="prepare-film", fps=fps, frames=n_frames)
        self._write_current_film(video_path, n_frames)
        return shots

    def _norm_size(self):
        """s34: (w, h) the proxy must be normalized to, or None (square,
        unrotated source: no filter added, current output unchanged)."""
        p = self._probe
        if p is None or (not p["rotation"] and abs(p["sar"] - 1.0) <= 1e-3):
            return None
        return colorprobe.normalized_size(p)

    def _write_current_film(self, video_path, n_frames):
        from cache import cache_key
        key = cache_key(video_path)
        entry = self.cache.entry(video_path)
        pointer = {"progress_path": entry.path("progress.json"),
                   "n_frames": n_frames, "cache_key": key}
        tmp = os.path.join(self.cache.root, "current-film.json.tmp")
        with open(tmp, "w") as f:
            json.dump(pointer, f)
        os.replace(tmp, os.path.join(self.cache.root, "current-film.json"))

    def _analyze_shot(self, video_path, s, e, fps):
        """One shot -> (contract npz fields, fov_track entry)."""
        p = self._probe
        if p is not None and (p["rotation"] or abs(p["sar"] - 1.0) > 1e-3):
            # s34: rotated/anamorphic source - depth input must see the same
            # display geometry as the proxy (cv2 ignores both).
            frames = vda_windowed.read_shot_frames_normalized(video_path, s, e + 1, p)
        else:
            frames = vda_windowed.read_shot_frames(video_path, s, e + 1)  # inclusive last
        if len(frames) == 0:
            return None, None
        if self._model is None:
            self._model = vda_windowed.load_model(self.checkpoint)
        depth_rel = vda_windowed.infer_shot_depth(self._model, frames,
                                                  input_size=self.input_size)
        if self._moge is None:
            self._moge = moge_fov.load_moge(self.moge_checkpoint)
        kidx = list(range(0, len(frames), FOV_KEYFRAME_STRIDE))
        kf_fovs, kf_metric = [], []
        for k in kidx:
            md, fv = moge_fov.infer_frame(self._moge, frames[k], num_tokens=600,
                                          resolution_level=5)
            if fv is not None:
                kf_fovs.append(((s + k) / fps, fv))
            if md is not None:
                kf_metric.append((k, md))
        # per-shot LSQ scale/shift (EMA over keyframes): vda-relative -> metres
        al = align_mod.ShotAligner(ema=0.9)
        sub = np.s_[::8, ::8]
        kf_track = []
        for k, md in kf_metric:
            al.update(depth_rel[k][sub], md[sub])
            kf_track.append((k, al.scale, al.shift))
        scale = al.scale if al.scale is not None else 1.0
        shift = al.shift if al.shift is not None else 0.0
        # s30: causal eased per-keyframe application (contract s30; a raw
        # per-keyframe switch pops disparity past the comfort band)
        z_m = align_mod.apply_align_track(depth_rel, kf_track,
                                          default=(scale, shift))  # metres
        inv = np.where(z_m > 1e-3, D_SCALE / np.maximum(z_m, 1e-3), 0.0)
        pts = (s + np.arange(len(frames))) / fps
        fields = {"depth": inv.astype(np.float16), "pts": pts,
                  "start": s, "end": e, "input_size": self.input_size,
                  "align_scale": float(scale), "align_shift": float(shift),
                  "align_track": [[int(k),
                                   float(s if s is not None else 1.0),
                                   float(b if b is not None else 0.0)]
                                  for k, s, b in kf_track]}
        fovs = [f for _, f in kf_fovs]
        if len(fovs) >= 2:
            conf = 1.0 - min(1.0, float(np.std(fovs)) / FOV_CONF_SPREAD_DEG)
            hfov = float(np.median(fovs))
        elif fovs:
            conf, hfov = 0.0, float(fovs[0])
        else:
            conf, hfov = 0.0, None
        fov_entry = {"start_pts": s / fps, "end_pts": e / fps,
                     "hfov_deg": hfov, "confidence": conf,
                     "keyframe_values": [[round(p, 6), f] for p, f in kf_fovs]}
        return fields, fov_entry

    def work_chunk(self, video_path, shots, fps=24.0, playhead_frame=None):
        """Do at most chunk_seconds of depth work. Returns (done, total).

        Idempotent; safe to call repeatedly until done == total.

        playhead_frame: when set, pending shots run nearest-playhead-first
        (the shot containing the playhead, then expanding by distance, ties
        to the lower index) so a seek lands on prepared depth soonest.
        None = sequential. Resume-safe: shots with an existing mp4 are
        skipped; the mp4 lands atomically via .tmp + os.replace, so an
        interrupted chunk never leaves a partial depth file."""
        deadline = time.monotonic() + self.chunk_seconds
        entry = self.cache.entry(video_path, create=True)
        existing = set(os.listdir(entry.dir))
        done = 0
        fov_all = entry._read("fov_track.json", {"fps": fps, "shots": []})["shots"]
        prior = entry._read("render-ready.json", {"shots": []})
        failures = {r["shot"]: r["error"] for r in prior.get("shots", [])
                    if r.get("error")}
        pending = [i for i in range(len(shots))
                   if f"depth_shot_{i:05d}.mp4" not in existing
                   or f"source_shot_{i:05d}.mp4" not in existing]
        if playhead_frame is not None:
            def _dist(i):
                s, e = shots[i]
                return 0 if s <= playhead_frame <= e else \
                    min(abs(playhead_frame - s), abs(playhead_frame - e))
            pending.sort(key=lambda i: (_dist(i), i))
        done = len(shots) - len(pending)
        processed = 0  # shots analyzed in THIS call; budget break keys off this
        for i in pending:
            s, e = shots[i]
            name = f"depth_shot_{i:05d}.mp4"
            if time.monotonic() > deadline and processed > 0:
                break
            try:
                if name in existing:
                    # depth already prepared; only the source proxy is missing -
                    # no need to re-run the depth models for this shot.
                    stmp = entry.path(f"source_shot_{i:05d}.mp4.tmp.mp4")
                    write_source_hevc(stmp, video_path, s, e, fps, normalize=self._norm_size())
                    os.replace(stmp, entry.path(f"source_shot_{i:05d}.mp4"))
                    done += 1
                    processed += 1
                    failures.pop(i, None)
                    write_render_ready(entry, shots, failures)
                    continue
                fields, fov_entry = self._analyze_shot(video_path, s, e, fps)
                if fields is None:
                    done += 1
                    processed += 1
                    continue
                while len(fov_all) <= i:
                    fov_all.append(None)
                fov_all[i] = fov_entry
                dep = fields["depth"].astype(np.float32)
                tmp = entry.path(name + ".tmp.mp4")
                write_depth_hevc(tmp, dep, fps, s)
                os.replace(tmp, entry.path(name))
                stmp = entry.path(f"source_shot_{i:05d}.mp4.tmp.mp4")
                write_source_hevc(stmp, video_path, s, e, fps, normalize=self._norm_size())
                os.replace(stmp, entry.path(f"source_shot_{i:05d}.mp4"))
                entry._write(f"depth_shot_{i:05d}.json",
                             {"start": s, "end": e, "input_size": self.input_size,
                              "depth_height": int(dep.shape[1]),
                              "depth_width": int(dep.shape[2]),
                              "source_height": int(dep.shape[1]),
                              "source_width": int(dep.shape[2]),
                              "align_scale": fields["align_scale"],
                              "align_shift": fields["align_shift"],
                              "align_track": fields["align_track"]})
                entry._write("fov_track.json", {"fps": fps, "shots": fov_all})
                entry.mark_prepared(s, e)
                done += 1
                processed += 1
                failures.pop(i, None)
            except Exception as ex:
                failures[i] = f"{type(ex).__name__}: {ex}"[:300]
            write_render_ready(entry, shots, failures)
        write_render_ready(entry, shots, failures)
        entry.touch_meta(model="Video-Depth-Anything-Small (Apache-2.0) + MoGe-2 (MIT)",
                         mode="prepare-film", shots=len(shots),
                         depth_format="10-bit HEVC Main10 4:2:0 full-range mp4, inverse depth D=256 (CONTRACT-190v)")
        return done, len(shots)

    def drive(self, video_path, fps, n_frames, start_pts=0.0, max_chunks=1000):
        """End-to-end shot driver (190t): film -> cuts -> per-shot depth mp4 +
        source proxy, ahead-of-playhead ordering from start_pts, with the
        render-ready.json sidecar refreshed after every shot for the Swift
        render coordinator to poll. Resume-safe: existing shots are skipped,
        failed shots are retried. Returns (done, total, render_ready_doc).
        Runs until all shots are ready, the budget structure stops making
        progress (every remaining shot failed), or max_chunks is hit."""
        shots = self.open_film(video_path, fps, n_frames)
        playhead = int(round(start_pts * fps))
        prev_fail = None
        for _ in range(max_chunks):
            done, _ = self.work_chunk(video_path, shots, fps=fps,
                                      playhead_frame=playhead)
            entry = self.cache.entry(video_path)
            doc = entry._read("render-ready.json", {})
            if done == len(shots):
                return done, len(shots), doc
            failed = tuple(sorted(r["shot"] for r in doc.get("shots", [])
                                  if r.get("failed")))
            if failed and len(failed) + done == len(shots) and failed == prev_fail:
                break  # everything left is failing the same way; stop spinning
            prev_fail = failed
        entry = self.cache.entry(video_path)
        return done, len(shots), entry._read("render-ready.json", {})

    def status(self, video_path, n_frames):
        """OSD-facing status: (ranges, prepared_frames, total, short_text)."""
        entry = self.cache.entry(video_path)
        ranges = entry.prepared_ranges()
        prepared = sum(b - a + 1 for a, b in ranges)
        txt = (f"3D prepared: {prepared}/{n_frames} frames"
               if prepared < n_frames else "3D prepared: full film")
        return ranges, prepared, n_frames, txt
