#!/usr/bin/env python3
"""Paul New vertical-metrics check (kit gate).

Declared Paul New line metrics (see engine/pipeline/src/declared_convention.rs,
PAUL_NEW_* constants; photo-derived from the Rules of Hypergraphy book photos,
+-20-30 unit tolerance, no cap-height value): hhea.ascender +770, hhea.descender
-230, OS/2 sTypoAscender +770 / sTypoDescender -230, usWinAscent 770,
usWinDescent 230 on the 1000-unit em. Reads the shipped OTF tables directly;
refuses (exit 1) on any mismatch. Usage: paulnew_vertical_check.py <font.otf>
"""
import struct, sys

ASC, DESC = 770, -230

def table(data, tag):
    num = struct.unpack(">H", data[4:6])[0]
    for i in range(num):
        off = 12 + 16 * i
        if data[off:off + 4] == tag:
            toff, tlen = struct.unpack(">II", data[off + 8:off + 16])
            return data[toff:toff + tlen]
    raise SystemExit(f"missing table {tag.decode()}")

def main(path):
    data = open(path, "rb").read()
    hhea = table(data, b"hhea")
    asc, desc = struct.unpack(">hh", hhea[4:8])
    os2 = table(data, b"OS/2")
    typo_asc, typo_desc = struct.unpack(">hh", os2[68:72])
    win_asc, win_desc = struct.unpack(">HH", os2[74:78])
    got = {"hhea.ascender": asc, "hhea.descender": desc, "os2.typo_ascender": typo_asc,
           "os2.typo_descender": typo_desc, "os2.win_ascent": win_asc, "os2.win_descent": win_desc}
    want = {"hhea.ascender": ASC, "hhea.descender": DESC, "os2.typo_ascender": ASC,
            "os2.typo_descender": DESC, "os2.win_ascent": ASC, "os2.win_descent": -DESC}
    bad = {k: (got[k], want[k]) for k in want if got[k] != want[k]}
    if bad:
        print(f"PAUL NEW METRICS FAIL: {bad}")
        sys.exit(1)
    print(f"PAUL NEW METRICS OK: asc {asc} desc {desc} typo {typo_asc}/{typo_desc} win {win_asc}/{win_desc}")

if __name__ == "__main__":
    main(sys.argv[1])
