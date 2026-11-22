"""Verifier for the .dzc lossless depth container (contract s16).

Run: python3 Tests/DepthAnalysis/test_depth_container.py
Also serves E-G/delivery as the executable spec: a Swift writer must produce
files whose decode equals the golden planes; byte-identical encoding is NOT
required (any valid LZFSE stream is accepted).
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..",
                                "tools", "depth_analysis"))
import depth_container as dc  # noqa: E402

HERE = os.path.dirname(__file__)


def main():
    g = json.load(open(os.path.join(HERE, "parity", "dzc_golden.json")))
    planes = np.load(os.path.join(HERE, "parity",
                                  "dzc_golden_planes.npz"))["planes"]
    path = os.path.join(HERE, "parity", "dzc_golden.dzc")

    meta = dc.read_info(path)
    for k in ("shot", "fps_num", "fps_den", "start_frame", "width",
              "height", "depth_width", "depth_height", "n_frames"):
        assert meta[k] == g[k], (k, meta[k], g[k])

    # full decode must reproduce the golden planes exactly (lossless)
    with open(path, "rb") as f:
        f.seek(dc.HEADER_SIZE)
        import lzfse
        for i in range(meta["n_frames"]):
            plen, crc = dc.FREC.unpack(f.read(dc.FREC.size))
            raw = lzfse.decompress(f.read(plen))
            assert len(raw) == meta["plane_bytes"]
            assert (zlib_crc(raw)) == crc, f"frame {i} crc"
            p = np.frombuffer(raw, "<u2").reshape(meta["height"],
                                                  meta["width"])
            assert np.array_equal(p, planes[i]), f"frame {i} content"

    # partial read + pts semantics
    inv, meta2, pts = dc.read(path, start=3, count=2)
    assert inv.shape == (2, meta["depth_height"], meta["depth_width"])
    assert abs(pts - (g["start_frame"] + 3) / 24.0) < 1e-9

    # roundtrip + resume
    rng = np.random.default_rng(1)
    z = np.where(rng.random((5, 30, 41)) > .3,
                 rng.uniform(.5, 20, (5, 30, 41)), np.inf).astype(np.float32)
    tmp = os.path.join("/tmp", "dzc_test.dzc")
    dc.write(tmp, z, shot=0, fps=24, start_frame=0)
    ref = np.stack([dc.dequantise(dc.quantise(z[i]))[:30, :41]
                    for i in range(5)])
    inv, _, _ = dc.read(tmp)
    assert np.array_equal(inv, ref)
    raw = open(tmp, "rb").read()
    open(tmp, "wb").write(raw[:len(raw) * 2 // 3])
    n, _ = dc.scan_valid_frames(tmp)
    assert 0 < n < 5, n
    dc.resume_write(tmp, z, shot=0, fps=24, start_frame=0)
    inv, _, _ = dc.read(tmp)
    assert np.array_equal(inv, ref)
    os.remove(tmp)
    print("test_depth_container: PASS")


def zlib_crc(raw):
    import zlib
    return zlib.crc32(raw) & 0xFFFFFFFF


if __name__ == "__main__":
    main()
