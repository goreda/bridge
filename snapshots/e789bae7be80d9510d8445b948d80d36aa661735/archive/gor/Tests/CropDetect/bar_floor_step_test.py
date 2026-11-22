#!/usr/bin/env python3
"""Fix B (arch-199ai): a bar row is near-black over the measured floor; the bound lands exactly at the step.

Delivered-3973842 numbers (owner session 261120-120833, 3840x2160 10-bit HDR): true bars 0/0 8-bit-eq over
black; dark picture rows mean ~30, max ~61 8-bit-eq over black; native black = 64 (10-bit tv), levelUnit = 4.
Old behaviour passed speck=0: one encode-noise pixel above the +2-level margin made a whole bar row content.
The fix passes speck = max(1, w/512) so a row is content only when any pixel exceeds the +12-level strong
margin or more than ~0.2% of the row exceeds the +2-level margin. The Python mirror reproduces
SourcePixelBounds.scan row logic; the fixture uses the log's geometry (bars 0/0, step at rows 272/1886)."""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
SP_ALL = (ROOT / 'Sources/gor/Stereo/Source.swift').read_text()
SP = SP_ALL[SP_ALL.index('// BEGIN relocated SourcePixelCrop.swift '):SP_ALL.index('// END relocated SourcePixelCrop.swift\n')]
fails = []
def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok: fails.append(name)

# -- static ----------------------------------------------------------------------------------------------------------
check("call site tolerates ~0.2% specks per row", "let speckTolerance = max(1, w / 512)" in SP)
check("scan is called with the speck and strong margins", "SourcePixelBounds.scan(decoded.0,width:w,height:h,threshold:threshold,speck:speckTolerance,strong:strongThreshold)" in SP)
check("row content rule: any strong pixel wins", "if v > strong { return true }" in SP)
check("row content rule: more than speck pixels above threshold", "if v > threshold { n += 1; if n > speck { return true } }" in SP)
check("threshold stays black + 2 levels, strong black + 12 (8-bit-eq at any depth)",
      "let threshold=UInt16(min(65535,(black+2*levelUnit)*(1 << max(0,16-bits))))" in SP
      and "let strongThreshold=UInt16(min(65535,(black+12*levelUnit)*(1 << max(0,16-bits))))" in SP)

# -- python mirror of scan() row logic (16-bit buffer codes, 10-bit tv: black=64, levelUnit=4) ------------------------
BITS, BLACK, UNIT = 10, 64, 4
SHIFT = 16 - BITS
THR = (BLACK + 2 * UNIT) << SHIFT
STRONG = (BLACK + 12 * UNIT) << SHIFT
W, H = 3840, 2160
SPECK = max(1, W // 512)
def code(level):  # 8-bit-eq level over black -> 16-bit buffer code
    return (BLACK + level * UNIT) << SHIFT
def row_is_content(vals, speck=SPECK):
    n = 0
    for v in vals:
        if v > STRONG: return True
        if v > THR:
            n += 1
            if n > speck: return True
    return False
def scan(rows):  # rows: list of row pixel lists; returns (x0, y0, x1, y1) like SourcePixelBounds.scan
    top = -1
    for y in range(H):
        if row_is_content(rows[y]): top = y; break
    if top < 0: return None
    bottom = top
    for y in range(H - 1, top, -1):
        if row_is_content(rows[y]): bottom = y; break
    return (0, top, W, bottom + 1)
def bar_row(noise=0):
    r = [code(0)] * W
    for i in range(noise): r[(i * 997) % W] = code(5)   # +5-level specks: above +2 margin, below +12 strong
    return r
def picture_row():
    r = [code(30)] * W                                    # log mean ~30 over black
    r[0] = code(61)                                       # log max ~61
    return r

# Fixture from the log: bars at floor 0 (rows 0..271 and 1886..2159), picture 272..1885 (step at 272 and 1886).
rows = [bar_row() for _ in range(272)] + [picture_row() for _ in range(1886 - 272)] + [bar_row() for _ in range(H - 1886)]
b = scan(rows)
check("letterbox fixture: bounds exactly at the step (y0=272, y1=1886)", b == (0, 272, W, 1886))

# Same fixture with encode noise in the bars: <= speck specks per bar row must not move the bound.
rows_n = [bar_row(noise=SPECK) for _ in range(272)] + [picture_row() for _ in range(1886 - 272)] + [bar_row(noise=SPECK) for _ in range(H - 1886)]
b2 = scan(rows_n)
check("noisy bars: bounds still exactly at the step", b2 == (0, 272, W, 1886))
check("old one-pixel veto treats a single speck as content (the bound would move)", row_is_content(bar_row(noise=1), speck=0))

# Dark HDR opening frame: every row mean ~30 / max ~61 over black -> full frame is content, nothing is bar.
dark = [picture_row() for _ in range(H)]
bd = scan(dark)
check("HDR dark picture is never a bar: full-frame bounds (no crop)", bd == (0, 0, W, H))

# A row whose picture is only specks above the margin but none strong is still a bar beyond the speck budget.
check("specks beyond the row budget are content (margin respected)", row_is_content(bar_row(noise=SPECK + 2)))

print("FAILURES: %d" % len(fails))
sys.exit(1 if fails else 0)
