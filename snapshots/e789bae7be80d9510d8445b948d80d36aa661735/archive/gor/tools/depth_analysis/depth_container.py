"""Lossless per-shot depth container (.dzc), contract s16.

Replaces the depth HEVC mp4 for the Mac path: VideoToolbox lossless HEVC
is the risk this removes. Payloads are LZFSE (Apple Compression decodes
natively; the python `lzfse` wheel binds the same reference format).
Source proxy stays HEVC (s9 unchanged).

Layout (all little-endian):
  header 64B: magic "GORDZ001" | u16 version=1 | u16 codec(1=lzfse)
    | u32 flags | u32 shot | u32 fps_num | u32 fps_den | u64 start_frame
    | u32 width | u32 height            (padded, even)
    | u32 depth_width | u32 depth_height (unpadded, sidecar semantics)
    | u32 n_frames | u32 plane_bytes (= width*height*2) | reserved to 64
  per frame i: u32 payload_len | u32 crc32(uncompressed plane) | payload
    payload = lzfse.compress(plane) where plane = width*height uint16 LE,
    w10 = clip(rint(v/1024*1023),0,1023), v = 256/z  (same quantisation as
    write_depth_hevc; chroma does not exist here)
  index: n_frames x u64 absolute offsets of each frame record
  trailer: magic "GORDZEND"

Resume-safe: a file without index+trailer is INCOMPLETE but scannable -
read_frames stops at the first short/crc-mismatching record; a writer can
truncate there and continue (resume_write). Index and trailer are written
last, so their presence certifies completeness.
PTS: frame i's pts = (start_frame + i) / (fps_num/fps_den) seconds.
"""
import os
import struct
import zlib

import numpy as np

MAGIC = b"GORDZ001"
TRAILER = b"GORDZEND"
VERSION = 1
CODEC_LZFSE = 1
HEADER = struct.Struct("<8sHHIIIIQIIIIII")  # 60 bytes; padded to 64 on disk
HEADER_SIZE = 64
FREC = struct.Struct("<II")  # payload_len, crc32

from prepare_film import D_SCALE, V_INV_MAX  # noqa: E402


def quantise(z):
    """z metres [H,W] -> padded uint16 w10 plane (edge-padded to even)."""
    z = np.asarray(z)
    h, w = z.shape
    hp, wp = h + (h & 1), w + (w & 1)
    v = np.where(z > 1e-3, D_SCALE / np.maximum(z, 1e-3), 0.0).astype(np.float32)
    q = np.clip(np.rint(v / np.float32(V_INV_MAX) * np.float32(1023.0)),
                0, 1023).astype(np.uint16)
    if (hp, wp) != (h, w):
        p = np.zeros((hp, wp), np.uint16)
        p[:h, :w] = q
        p[:h, w:] = q[:, -1:]
        p[h:, :] = p[h - 1:h, :]
        q = p
    return q


def dequantise(plane, size=None):
    """uint16 w10 plane -> float32 inverse depth v [T-less H,W]; 0 = masked."""
    y = plane.astype(np.float32) / 1023.0 * V_INV_MAX
    if size is not None:
        y = y[:size[0], :size[1]]
    return y


def _write_header(f, meta):
    blob = HEADER.pack(MAGIC, VERSION, CODEC_LZFSE, 0, meta["shot"],
                       meta["fps_num"], meta["fps_den"], meta["start_frame"],
                       meta["width"], meta["height"], meta["depth_width"],
                       meta["depth_height"], meta["n_frames"],
                       meta["plane_bytes"])
    f.write(blob.ljust(HEADER_SIZE, b"\0"))


def _read_header(f):
    blob = f.read(HEADER_SIZE)
    (magic, ver, codec, _flags, shot, fps_num, fps_den, start_frame,
     w, h, dw, dh, n, plane_bytes) = HEADER.unpack(blob[:HEADER.size])
    if magic != MAGIC:
        raise ValueError("not a GORDZ file")
    if ver != VERSION or codec != CODEC_LZFSE:
        raise ValueError(f"unsupported version/codec {ver}/{codec}")
    return {"shot": shot, "fps_num": fps_num, "fps_den": fps_den,
            "start_frame": start_frame, "width": w, "height": h,
            "depth_width": dw, "depth_height": dh, "n_frames": n,
            "plane_bytes": plane_bytes}


def write(path, z_seq, shot, fps, start_frame):
    """Write a complete container from a z sequence [T,H,W] (metres)."""
    import lzfse
    fps_num, fps_den = _fps_pair(fps)
    t, h, w = z_seq.shape
    meta = None
    offsets = []
    with open(path, "wb") as f:
        planes = [quantise(z_seq[i]) for i in range(t)]
        meta = {"shot": shot, "fps_num": fps_num, "fps_den": fps_den,
                "start_frame": int(start_frame),
                "width": planes[0].shape[1], "height": planes[0].shape[0],
                "depth_width": w, "depth_height": h, "n_frames": t,
                "plane_bytes": planes[0].size * 2}
        _write_header(f, meta)
        for p in planes:
            raw = p.astype("<u2").tobytes()
            comp = lzfse.compress(raw)
            offsets.append(f.tell())
            f.write(FREC.pack(len(comp), zlib.crc32(raw) & 0xFFFFFFFF))
            f.write(comp)
        for off in offsets:
            f.write(struct.pack("<Q", off))
        f.write(TRAILER)
    return meta


def read_info(path):
    with open(path, "rb") as f:
        return _read_header(f)


def scan_valid_frames(path):
    """Count of leading frames whose record parses and crc matches."""
    import lzfse
    with open(path, "rb") as f:
        meta = _read_header(f)
        n = 0
        while True:
            rec = f.read(FREC.size)
            if len(rec) < FREC.size:
                break
            plen, crc = FREC.unpack(rec)
            comp = f.read(plen)
            if len(comp) < plen:
                break
            try:
                raw = lzfse.decompress(comp)
            except Exception:
                break
            if len(raw) != meta["plane_bytes"] or \
                    (zlib.crc32(raw) & 0xFFFFFFFF) != crc:
                break
            n += 1
        return n, meta


def read(path, start=0, count=None):
    """-> (inv float32 [T,depth_h,depth_w], meta, start_pts seconds)."""
    import lzfse
    with open(path, "rb") as f:
        meta = _read_header(f)
        valid, _ = scan_valid_frames(path)
        n = min(meta["n_frames"], valid)
        if start >= n:
            raise ValueError("start beyond valid frames")
        t = min(count if count is not None else n - start, n - start)
        f.seek(HEADER_SIZE)
        offs = []
        for _ in range(n):
            offs.append(f.tell())
            (plen,) = struct.unpack("<I", f.read(4))
            f.seek(4 + plen, os.SEEK_CUR)
        planes = []
        for i in range(start, start + t):
            f.seek(offs[i])
            plen, _crc = FREC.unpack(f.read(FREC.size))
            raw = lzfse.decompress(f.read(plen))
            planes.append(np.frombuffer(raw, "<u2").reshape(meta["height"],
                                                           meta["width"]))
        inv = np.stack([dequantise(p) for p in planes])
        inv = inv[:, :meta["depth_height"], :meta["depth_width"]]
        fps = meta["fps_num"] / meta["fps_den"]
        start_pts = (meta["start_frame"] + start) / fps
        return inv, meta, start_pts


def resume_write(path, z_seq, shot, fps, start_frame):
    """Append/resume: keeps leading valid frames already on disk."""
    valid, meta = scan_valid_frames(path)
    fps_num, fps_den = _fps_pair(fps)
    if valid:
        assert meta["shot"] == shot and meta["fps_num"] == fps_num
    import lzfse
    t, h, w = z_seq.shape
    planes = [quantise(z_seq[i]) for i in range(valid, t)]
    with open(path, "r+b") as f:
        if valid:
            # truncate after the valid prefix
            offs = []
            f.seek(HEADER_SIZE)
            for _ in range(valid):
                offs.append(f.tell())
                (plen,) = struct.unpack("<I", f.read(4))
                f.seek(4 + plen, os.SEEK_CUR)
            f.truncate(f.tell())
        else:
            meta = {"shot": shot, "fps_num": fps_num, "fps_den": fps_den,
                    "start_frame": int(start_frame),
                    "width": planes[0].shape[1] if planes else w + (w & 1),
                    "height": planes[0].shape[0] if planes else h + (h & 1),
                    "depth_width": w, "depth_height": h, "n_frames": t,
                    "plane_bytes": (w + (w & 1)) * (h + (h & 1)) * 2}
            _write_header(f, meta)
            offs = []
        f.seek(0, os.SEEK_END)
        for p in planes:
            raw = p.astype("<u2").tobytes()
            comp = lzfse.compress(raw)
            offs.append(f.tell())
            f.write(FREC.pack(len(comp), zlib.crc32(raw) & 0xFFFFFFFF))
            f.write(comp)
        for off in offs:
            f.write(struct.pack("<Q", off))
        f.write(TRAILER)


def _fps_pair(fps):
    if float(fps).is_integer():
        return int(fps), 1
    return int(round(fps * 1000)), 1000
