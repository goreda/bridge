"""Independent-parser inspection hook. Authored NOT_RUN, fontTools not installed/pinned here.
Not a build/run permission and not a native editor/render acceptance test.
Usage after explicit execution permission: python verify_cff_font.py caller.otf
"""
import argparse
import json
from pathlib import Path


def verify_container_bytes(path):
    import struct
    data = Path(path).read_bytes()
    def checksum(chunk):
        padded = chunk + bytes((-len(chunk)) % 4)
        return sum(struct.unpack(">" + "I" * (len(padded) // 4), padded)) & 0xffffffff
    assert data[:4] == b"OTTO"
    assert len(data) >= 12
    count, search_range, selector, shift = struct.unpack(">HHHH", data[4:12])
    assert count and len(data) >= 12 + count * 16
    power = 1 << (count.bit_length() - 1)
    assert (search_range, selector, shift) == (16 * power, count.bit_length() - 1, 16 * (count - power))
    tags = []
    ranges = []
    for i in range(count):
        tag, expected, offset, size = struct.unpack(">4sIII", data[12 + i * 16:28 + i * 16])
        assert offset % 4 == 0 and offset >= 12 + count * 16
        assert offset + size <= len(data)
        chunk = data[offset:offset + size]
        if tag == b"head":
            assert size == 54
            chunk = chunk[:8] + bytes(4) + chunk[12:]
        assert checksum(chunk) == expected, tag
        tags.append(tag)
        ranges.append((offset, offset + (size + 3) // 4 * 4))
    assert tags == sorted(set(tags))
    ranges.sort()
    assert all(a[1] <= b[0] for a, b in zip(ranges, ranges[1:]))
    assert checksum(data) == 0xb1b0afba
    return {"tables": [tag.decode("ascii") for tag in tags], "byte_length": len(data), "checksums": "verified"}

def inspect(path):
    container = verify_container_bytes(path)
    from fontTools.ttLib import TTFont
    from fontTools.pens.recordingPen import RecordingPen
    font = TTFont(path, checkChecksums=2, lazy=False)
    required = {"CFF ", "cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post"}
    assert required.issubset(font.keys())
    assert font.sfntVersion == "OTTO"
    assert font["head"].unitsPerEm == 1000
    assert font["maxp"].tableVersion == 0.5
    order = font.getGlyphOrder()
    assert order[0] == ".notdef"
    assert font["maxp"].numGlyphs == len(order)
    assert font["hhea"].numberOfHMetrics == len(order)
    glyph_set = font.getGlyphSet()
    result = {}
    for name in order:
        pen = RecordingPen()
        glyph_set[name].draw(pen)
        result[name] = {"outline": pen.value, "metrics": font["hmtx"].metrics[name]}
    # Return observations for input/control comparison, never auto-label a match.
    return {"container": container, "glyph_order": order, "glyphs": result, "cmap": font.getBestCmap(), "parser": "fontTools", "render": "NOT_RUN"}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("font", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.font), indent=2))
