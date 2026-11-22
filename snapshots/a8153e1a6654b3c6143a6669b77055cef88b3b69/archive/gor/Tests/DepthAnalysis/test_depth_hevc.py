"""Contract depth container test: 10-bit HEVC lossless roundtrip + PTS.

Container is mp4, codec HEVC Main 10 4:2:0 (yuv420p10le, depth on luma,
neutral chroma): VideoToolbox-decodable on Apple silicon, AVFoundation-
readable. gray10le/Rext was rejected for exactly that reason."""
import os
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))

from prepare_film import D_SCALE, V_INV_MAX, read_depth_hevc, write_depth_hevc

rng = np.random.default_rng(11)


def main():
    d = tempfile.mkdtemp()
    path = os.path.join(d, "depth_shot_00000.mp4")
    # realistic inverse depth: smooth field + masked pixels
    y, x = np.mgrid[0:96, 0:160].astype(np.float32)
    inv = 256.0 / (2.0 + 20.0 * (x / 160.0) + y / 96.0)  # Z ~2..22 m
    inv[10:20, 30:40] = 0.0  # masked
    frames = np.stack([np.where(inv > 0, inv + t * 0.5, 0.0) for t in range(4)]).astype(np.float32)
    write_depth_hevc(path, frames, fps=24.0, start_frame=48)
    back, start = read_depth_hevc(path)
    assert back.shape == frames.shape, (back.shape, frames.shape)
    assert abs(start - 2.0) < 0.01, start  # 48/24 = 2.0 s film-time PTS
    q_err = np.abs(back - frames) / V_INV_MAX * 1023.0
    assert q_err.max() <= 0.51, q_err.max()  # sub-LSB: quantization only
    # 0.5 LSB v error at 63mm IPD, f=1400px (90deg hfov, 1280w) = 0.18 px
    # worst-case systematic: sub-pixel, below perceptual threshold at 720p.
    disp_err_px = 0.063 * 1400 * (0.51 / 1023.0 * V_INV_MAX) / D_SCALE
    assert disp_err_px < 0.25, disp_err_px
    print(f"PASS hevc10 luma roundtrip: PTS ok, max quant {q_err.max():.2f} LSB, "
          f"disparity err {disp_err_px:.3f} px, bytes {os.path.getsize(path)}")

    # codec/container contract: Main 10 4:2:0 in mp4 (VT-decodable)
    import json as _json
    import subprocess
    pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                         "-show_entries", "stream=codec_name,profile,pix_fmt,color_range,color_space,color_transfer,color_primaries",
                         "-of", "json", path], capture_output=True, text=True)
    st = _json.loads(pr.stdout)["streams"][0]
    assert st["codec_name"] == "hevc" and "Main 10" in st["profile"], st
    assert st["pix_fmt"] == "yuv420p10le", st
    print(f"PASS container: hevc {st['profile']} {st['pix_fmt']} in mp4")
    # full-range signalling: VideoToolbox must return stored luma unscaled
    assert st["color_range"] == "pc", st
    assert st["color_space"] == "bt709", st
    assert st["color_transfer"] == "bt709" and st["color_primaries"] == "bt709", st
    # VUI flag inside the HEVC bitstream itself (x265 range=full), not just
    # the mp4 colr atom: demux to annexb and read the SPS VUI back.
    an = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-c", "copy",
                         "-bsf:v", "hevc_mp4toannexb", "-f", "hevc", "-"],
                        capture_output=True).stdout
    h = subprocess.run(["ffprobe", "-v", "error", "-f", "hevc",
                        "-show_entries", "stream=color_range", "-of", "json", "-"],
                       input=an, capture_output=True)
    assert _json.loads(h.stdout)["streams"][0]["color_range"] == "pc", h.stdout[:200]
    print(f"PASS full-range tags: colr=pc + bitstream VUI full_range, space={st['color_space']}")

    # pluggable-encoder spec (contract 9): x265 output == vt_encode_spec() depth tags
    from prepare_film import vt_encode_spec
    spec = vt_encode_spec()["depth"]
    assert st["codec_name"] == spec["codec_name"] and spec["profile_contains"] in st["profile"]
    assert st["pix_fmt"] == spec["pix_fmt"] and st["color_range"] == spec["color_range"]
    assert st["color_space"] == spec["color_space"] and st["color_transfer"] == spec["color_transfer"]
    assert st["color_primaries"] == spec["color_primaries"]
    print("PASS encoder spec: x265 output == vt_encode_spec() depth tags")
    # unknown encoder rejected on this platform
    try:
        write_depth_hevc(path, frames, fps=24.0, start_frame=0, encoder="vt")
        raise SystemExit("encoder='vt' must raise on Linux")
    except RuntimeError as ex:
        assert "section 9" in str(ex), ex
    print("PASS encoder dispatch: unknown encoder raises with contract pointer")

    # odd dims: edge padding + crop-back is lossless
    odd = frames[:, :95, :159]
    p2 = os.path.join(d, "depth_shot_00001.mp4")
    write_depth_hevc(p2, odd, fps=24.0, start_frame=0)
    back2, _ = read_depth_hevc(p2, size=(95, 159))
    assert back2.shape == odd.shape, back2.shape
    q2 = np.abs(back2 - odd) / V_INV_MAX * 1023.0
    assert q2.max() <= 0.51, q2.max()
    print(f"PASS odd-dims padding: 95x159 roundtrip, max quant {q2.max():.2f} LSB")


if __name__ == "__main__":
    main()
