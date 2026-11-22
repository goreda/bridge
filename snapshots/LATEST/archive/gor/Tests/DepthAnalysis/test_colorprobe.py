#!/usr/bin/env python3
"""s34: colour/format audit tests (CONTRACT-190v s34).

Synthetic clips pin the probe verdicts and the measurable chain fixes:
range tag pass-through, untagged-matrix size rule, HDR/DV/VFR refusal,
rotation + anamorphic normalization (proxy and depth input share display
geometry), odd-size padding, 4:2:0 chroma siting, 10-bit roundtrip, and
8-bit luma for scdet on 10-bit sources.
"""
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))
import colorprobe  # noqa: E402
import cuts as cuts_mod  # noqa: E402
import prepare_film as pf  # noqa: E402
import vda_windowed  # noqa: E402

TMP = tempfile.mkdtemp(prefix="s34_")


def mk(name, vf, enc=("-c:v", "libx264", "-crf", "18"), extra=(), size="96x64", n=12, rate=8):
    out = os.path.join(TMP, name)
    subprocess.run(["ffmpeg", "-y", "-v", "error",
                    "-f", "lavfi", "-i", f"testsrc2=size={size}:rate={rate}:duration={n / rate}",
                    "-vf", vf, *enc, *extra, out], check=True)
    return out


def fields(mp4):
    pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                         "-show_entries",
                         "stream=width,height,pix_fmt,color_range,color_space,"
                         "color_transfer,color_primaries,r_frame_rate,avg_frame_rate",
                         "-of", "json", mp4], capture_output=True, text=True, check=True)
    return json.loads(pr.stdout)["streams"][0]


def verdict(p, dim):
    return {d: (s, t) for d, s, t in colorprobe.verdicts(p)}[dim]


# 1. baseline 8-bit limited bt709: everything ok/note, no refuse/fix
c709 = mk("c709.mp4", "format=yuv420p",
          extra=("-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv"))
p = colorprobe.probe(c709)
assert p["bit_depth"] == 8 and p["color_range"] == "tv", p
assert verdict(p, "matrix")[0] == "ok" and verdict(p, "sar")[0] == "ok" and verdict(p, "rotation")[0] == "ok"
assert colorprobe.refuse_reasons(p) == [] and colorprobe.normalized_size(p) == (96, 64)
print("PASS 8bit-limited-709 baseline")

# 2. full range: note + tags pass through to the proxy
cfull = mk("cfull.mp4", "format=yuv420p",
           extra=("-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "pc"))
p = colorprobe.probe(cfull)
assert p["color_range"] == "pc" and verdict(p, "range")[0] == "note", p
prox = os.path.join(TMP, "proxy_full.mp4")
pf.write_source_hevc(prox, cfull, 0, 3, 8)
f = fields(prox)
assert f["color_range"] == "pc", f   # pass-through, not forced tv
print("PASS full-range tags pass through to proxy")

# 3. HDR10 (PQ) and HLG: refuse; Dolby Vision: refuse (unit-level, no DV encoder here)
cpq = mk("cpq.mp4", "format=yuv420p10le", enc=("-c:v", "libx265", "-crf", "20"),
         extra=("-colorspace", "bt2020nc", "-color_primaries", "bt2020", "-color_trc", "smpte2084", "-tag:v", "hvc1"))
p = colorprobe.probe(cpq)
assert p["bit_depth"] == 10 and verdict(p, "hdr_transfer")[0] == "refuse", p
assert any("never silently tone-clipped" in r for r in colorprobe.refuse_reasons(p))
try:
    pf.PrepareFilm(None, None).probe_film(cpq)
    raise SystemExit("PQ source was not refused")
except RuntimeError as ex:
    assert "refused" in str(ex), ex
chlg = mk("chlg.mp4", "format=yuv420p10le", enc=("-c:v", "libx265", "-crf", "20"),
          extra=("-colorspace", "bt2020nc", "-color_primaries", "bt2020", "-color_trc", "arib-std-b67", "-tag:v", "hvc1"))
assert verdict(colorprobe.probe(chlg), "hdr_transfer")[0] == "refuse"
fake_dv = dict(p, dolby_vision=True, codec_tag_string="dvh1")
assert verdict(fake_dv, "dolby_vision")[0] == "refuse"
print("PASS HDR10/HLG/Dolby Vision refused, never silently tone-clipped")

# 4. untagged matrix size rule: SD -> bt470bg, HD -> bt709
csd = mk("csd.mp4", "format=yuv420p", size="320x240")
chd = mk("chd.mp4", "format=yuv420p", size="1280x96")
assert colorprobe.matrix_for(colorprobe.probe(csd)) == "bt470bg"
assert colorprobe.matrix_for(colorprobe.probe(chd)) == "bt709"
assert colorprobe.rgb_decode_scale(colorprobe.probe(csd)) == "scale=in_color_matrix=bt470bg"
print("PASS untagged-matrix size rule (SD 601 / HD 709)")

# 5. rotation: proxy and depth input both present display geometry
# (ffmpeg 4.4 only writes the display matrix on a -c copy remux pass)
crot0 = mk("crot0.mp4", "format=yuv420p", size="96x64")
crot = os.path.join(TMP, "crot.mp4")
subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", crot0, "-c", "copy",
                "-metadata:s:v", "rotate=90", crot], check=True)
p = colorprobe.probe(crot)
assert p["rotation"] in (90, 270), p
assert colorprobe.normalized_size(p) == (64, 96)
assert verdict(p, "rotation")[0] == "fix"
prox = os.path.join(TMP, "proxy_rot.mp4")
pf.write_source_hevc(prox, crot, 0, 3, 8, normalize=colorprobe.normalized_size(p))
f = fields(prox)
assert (int(f["width"]), int(f["height"])) == (64, 96), f   # autorotated + padded even
fr = vda_windowed.read_shot_frames_normalized(crot, 0, 4, p)
assert fr.shape == (4, 96, 64, 3), fr.shape   # same display geometry as proxy
print("PASS rotation: proxy + depth input share display geometry")

# 6. anamorphic: sar 2:1 normalized to square display pixels
csar = mk("csar.mp4", "format=yuv420p,setsar=2/1", size="64x64")
p = colorprobe.probe(csar)
assert abs(p["sar"] - 2.0) < 1e-3 and verdict(p, "sar")[0] == "fix", p
assert colorprobe.normalized_size(p) == (128, 64)
prox = os.path.join(TMP, "proxy_sar.mp4")
pf.write_source_hevc(prox, csar, 0, 3, 8, normalize=colorprobe.normalized_size(p))
f = fields(prox)
assert (int(f["width"]), int(f["height"])) == (128, 64), f
fr = vda_windowed.read_shot_frames_normalized(csar, 0, 4, p)
assert fr.shape == (4, 64, 128, 3), fr.shape
print("PASS anamorphic: square-pixel normalization in proxy + depth input")

# 7. VFR: refuse
cvfr = mk("cvfr.mp4", "select='not(mod(n,3))',format=yuv420p,settb=AVTB", n=24,
          extra=("-vsync", "passthrough"))
p = colorprobe.probe(cvfr)
assert p["vfr"] and verdict(p, "vfr")[0] == "refuse", (p["r_fps"], p["avg_fps"])
print("PASS VFR refused")

# 8. odd size: note + black pad to even, unpadded size recoverable
# (H.264 rounds odd lavfi sizes at encode; ffv1/mkv keeps a true odd size)
codd = os.path.join(TMP, "codd.mkv")
subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                "testsrc2=size=98x64:rate=8:duration=1.5",
                "-vf", "format=yuv444p,crop=97:63", "-c:v", "ffv1", codd], check=True)
p = colorprobe.probe(codd)
assert (p["width"], p["height"]) == (97, 63), p
assert verdict(p, "odd_size")[0] == "note"
prox = os.path.join(TMP, "proxy_odd.mp4")
pf.write_source_hevc(prox, codd, 0, 3, 8)
f = fields(prox)
assert (int(f["width"]), int(f["height"])) == (98, 64), f
print("PASS odd size padded to even")

# 9. 10-bit limited gradient: proxy roundtrip keeps 10-bit precision (no 8-bit step banding)
grad = os.path.join(TMP, "grad.mp4")
import numpy as np
_gw, _gh, _gn = 256, 64, 6
_y = (np.arange(_gw, dtype=np.uint16)[None, :] + 64).repeat(_gh, 0)  # 64..319 video-range ramp
_c = np.full((_gh // 2, _gw // 2), 512, dtype=np.uint16)
_raw = b"".join((_y.tobytes() + _c.tobytes() + _c.tobytes()) for _ in range(_gn))
subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "yuv420p10le",
                "-s", f"{_gw}x{_gh}", "-r", "8", "-i", "-",
                "-c:v", "libx265", "-crf", "18",
                "-color_range", "tv", "-colorspace", "bt709", "-tag:v", "hvc1", grad],
               input=_raw, check=True)
p = colorprobe.probe(grad)
assert p["bit_depth"] == 10
prox = os.path.join(TMP, "proxy_grad.mp4")
pf.write_source_hevc(prox, grad, 0, 3, 8)
out = subprocess.run(["ffmpeg", "-v", "error", "-i", prox, "-frames:v", "1",
                      "-f", "rawvideo", "-pix_fmt", "yuv420p10le", "-"], capture_output=True, check=True)
raw = np.frombuffer(out.stdout, dtype=np.uint16)
y = raw[:256 * 64].reshape(64, 256) >> 6  # 10-bit luma
row = y[32]
steps = np.diff(row.astype(np.int32))
assert steps.max() <= 5 and steps.min() >= 0, (steps.min(), steps.max())  # monotone, no 4x banding steps
print("PASS 10-bit gradient roundtrip (no banding from an 8-bit hop)")

# 10. 4:2:0 chroma siting: sharp red|green edge; swscale upsample must land within 1px of the luma edge
edge = os.path.join(TMP, "edge.mp4")
subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                "color=red:size=64x64:rate=8:duration=0.5",
                "-vf", "drawbox=x=32:w=32:color=green:t=fill,format=yuv420p",
                "-c:v", "libx264", "-crf", "18", edge], check=True)
out = subprocess.run(["ffmpeg", "-v", "error", "-i", edge, "-frames:v", "1",
                      "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True)
rgb = np.frombuffer(out.stdout, dtype=np.uint8).reshape(64, 64, 3)
row = rgb[32].astype(np.int32)
luma = (row[:, 0] + row[:, 1] + row[:, 2]) / 3
lmid = int(np.argmax(np.abs(np.diff(luma))))          # luma edge column
gcross = int(np.argmax(np.abs(np.diff(row[:, 1]))))   # green-channel edge column
assert abs(gcross - lmid) <= 1, (lmid, gcross)        # chroma edge within 1px of luma edge
print(f"PASS 4:2:0 chroma siting (luma edge @{lmid}, chroma edge @{gcross})")

# 11. scdet on a 10-bit source: 8-bit luma normalization keeps threshold 12 working
cut8 = os.path.join(TMP, "cut8.mp4")
subprocess.run(["ffmpeg", "-y", "-v", "error",
                "-f", "lavfi", "-i", "testsrc2=size=96x64:rate=8:duration=1",
                "-f", "lavfi", "-i", "smptebars=size=96x64:rate=8:duration=1",
                "-filter_complex", "[0][1]concat=n=2:v=1,format=yuv420p10le[v]",
                "-map", "[v]", "-c:v", "libx265", "-crf", "20", "-tag:v", "hvc1", cut8], check=True)
got = cuts_mod.detect_cuts(cut8, fps=8)
assert 8 in got, got   # the concat boundary at frame 8, found at the 8-bit-calibrated threshold
print("PASS scdet 8-bit luma on 10-bit source")

print("PASS test_colorprobe")
