"""190y X2 goreda lane: regression gate for the independent iw3 ToS reproduction.

Checks, dependency-free (pure python + numpy), Linux-runnable:
1. T2 image bit-parity: goreda reproduction vs A-D reference PNG, decoded with an
   inline PNG reader (8-bit RGB, filters 0-4). Bar: max abs diff <= 1, PSNR >= 60 dB
   (measured 2026-11-09: max 1, PSNR 61.65).
2. x2_repro_diff_vs_ad.json: recorded T2 max <= 1 and T1/T3 PSNR >= 34 dB.
3. nunif-coreml-192x384-manifest.json: 4 packages, shapes multiples of 96, hash formats.
4. models/models.lock.tsv: the 7 nunif iw3 rows keep repo/revision/sha256/bytes binding.
"""
import json
import struct
import zlib
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / "tools/depth_analysis/kit"


def png_decode(path):
    d = path.read_bytes()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", path
    pos = 8
    w = h = None
    idat = b""
    while pos < len(d):
        (ln,) = struct.unpack(">I", d[pos:pos + 4])
        typ = d[pos + 4:pos + 8]
        data = d[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, bitdepth, ctype = struct.unpack(">IIBB", data[:10])
            assert bitdepth == 8 and ctype == 2, (bitdepth, ctype)
        elif typ == b"IDAT":
            idat += data
        elif typ == b"IEND":
            break
    raw = zlib.decompress(idat)
    stride = w * 3
    out = np.zeros((h, stride), np.uint8)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        row = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(3, stride):
                row[i] = (row[i] + row[i - 3]) & 255
        elif f == 2:
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = row[i - 3] if i >= 3 else 0
                row[i] = (row[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = row[i - 3] if i >= 3 else 0
                b = prev[i]
                c = prev[i - 3] if i >= 3 else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row[i] = (row[i] + pr) & 255
        else:
            assert f == 0, f
        out[y] = np.frombuffer(bytes(row), np.uint8)
        prev = row
    return out.reshape(h, w, 3)


def test_t2_bit_parity():
    ref = png_decode(KIT / "x2_tos_reference/tos_t2_mlbw_l2_inpaint_image.png")
    got = png_decode(KIT / "x2_tos_repro/tos_t2_mlbw_l2_inpaint_image_goreda.png")
    assert ref.shape == got.shape == (180, 640, 3)
    d = np.abs(ref.astype(np.int16) - got.astype(np.int16))
    assert int(d.max()) <= 1, f"T2 max abs diff {d.max()} > 1"
    mse = float(((ref.astype(np.float64) - got.astype(np.float64)) ** 2).mean())
    psnr = 10 * np.log10(255 ** 2 / mse) if mse > 0 else 99.0
    assert psnr >= 60.0, f"T2 PSNR {psnr:.2f} < 60"
    print(f"PASS T2 bit-parity: max={int(d.max())} psnr={psnr:.2f}")


def test_repro_diff_record():
    j = json.loads((KIT / "x2_tos_repro/x2_repro_diff_vs_ad.json").read_text())
    assert j["t2_mlbw_l2_inpaint_image"]["max"] <= 1
    for t in ("t1_mlbw_l2_inpaint_video", "t3_row_flow_v3"):
        assert j[t]["psnr_db"] >= 34.0, (t, j[t]["psnr_db"])
        assert j[t]["frames"] == 48
    print("PASS repro diff record thresholds")


def test_manifest_192x384():
    m = json.loads((KIT / "nunif-coreml-192x384-manifest.json").read_text())
    assert len(m["packages"]) == 4
    hexdig = lambda s: len(s) == 64 and all(c in "0123456789abcdef" for c in s)
    for name, pkg in m["packages"].items():
        assert name.endswith(".mlpackage")
        for io in list(pkg["inputs"].values()) + list(pkg["outputs"].values()):
            assert io[-2] % 96 == 0 and io[-1] % 96 == 0, (name, io)
        assert hexdig(pkg["content_files_sha256"]) and hexdig(pkg["fixture_sha256"])
    assert hexdig(m["tar"]["sha256"]) and m["tar"]["bytes"] > 0
    print("PASS 192x384 manifest consistency")


def test_models_lock_iw3_rows():
    rows = [l.split("\t") for l in (ROOT / "models/models.lock.tsv").read_text().splitlines()
            if l.startswith("iw3-") and ".pth" in l]
    assert len(rows) == 7, len(rows)
    for r in rows:
        assert r[3] == "https://github.com/nagadomi/nunif" and r[4] == "0.0.0", r[0]
        assert len(r[6]) == 64 and int(r[7]) > 0, r[0]
    print("PASS models.lock 7 iw3 rows bound (repo, revision 0.0.0, sha256, bytes)")


if __name__ == "__main__":
    test_t2_bit_parity()
    test_repro_diff_record()
    test_manifest_192x384()
    test_models_lock_iw3_rows()
    print("x2_tos_repro: 0 failure(s)")
