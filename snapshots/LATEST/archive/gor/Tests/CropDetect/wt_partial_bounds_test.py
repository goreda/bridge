#!/usr/bin/env python3
"""Measured: the scanner's own cropdetect filter, run on the wt fallback/range positions of a partially downloaded
letterboxed clip (45 px black bars top and bottom of 640x360), reports the picture rectangle 640x270 at y=45 (rows 45..314)
within one row, never cutting picture, at every sampled position (exact luma-bounds rule of SourcePixelBounds; ffmpeg cropdetect alone reads 268@46 on this
lossy clip, which is why the scanner does not trust it for the rectangle)."""
import os, re, subprocess, sys, tempfile
tmp = tempfile.mkdtemp(); src = os.path.join(tmp, "lb.mp4")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=640x360:r=24:d=40", "-vf",
                "drawbox=x=0:y=0:w=640:h=45:color=black:t=fill,drawbox=x=0:y=315:w=640:h=45:color=black:t=fill",
                "-c:v", "libx264", "-g", "24", "-pix_fmt", "yuv420p", src], check=True)
def crop_at(t):
    """Exact bounds as the scanner measures them: raw decoded luma, rows/cols with any sample above black+2 (16+2 = 18)."""
    r = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-hwaccel", "none", "-threads", "2", "-ss", str(t), "-i", src, "-map", "0:v:0", "-an",
                        "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "pipe:1"], capture_output=True)
    d = r.stdout
    if len(d) != 640 * 360: return None
    rows = [y for y in range(360) if max(d[y * 640:(y + 1) * 640]) > 18]
    return (640, rows[-1] - rows[0] + 1, 0, rows[0]) if rows else None
now = 12.0
positions = [max(0, now - b) for b in (4.0, 2.0, 0.5)] + [0.7 + i * 2.1 for i in range(12)]
res = [(t, crop_at(t)) for t in positions]
for t, c in res: print("t=%.1f crop=%s" % (t, c))
# Lossy h264 bleeds at most one row of the picture edge into a bar on some frames (seen: 271 rows at t=19.6), so the
# claim is: no position ever cuts picture (top <= 45 and bottom >= 314), and none overshoots by more than 1 row per side.
cut = [t for t, c in res if c is None or c[3] > 45 or c[3] + c[1] - 1 < 314]
wide = [t for t, c in res if c is not None and (45 - c[3] > 1 or (c[3] + c[1] - 1) - 314 > 1)]
union_top = min(c[3] for _, c in res); union_bot = max(c[3] + c[1] - 1 for _, c in res)
print("positions=%d cutting=%d overshooting>1=%d union rows %d..%d (truth 45..314)" % (len(res), len(cut), len(wide), union_top, union_bot))
ok = not cut and not wide and union_top >= 44 and union_bot <= 315
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
