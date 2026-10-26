"""Exact integer-domain source/decoded comparison. Authored NOT_RUN.
Caller supplies JSON from independent parser and source expectation.
No rounding, tolerance, coordinate conversion or confidence annotations.
Expected glyphs map names to {outline: [[operator, [[x,y],...]],...], metrics:[advance,lsb]}.
RecordingPen closePath adds no segment here: source must include its explicit closing segment.
"""
import argparse
import json
from pathlib import Path

def compare(expected, decoded):
    # Include .notdef and all siblings; no silently omitted failures.
    expected_glyphs = expected["glyphs"]
    actual_glyphs = decoded["glyphs"]
    if expected["glyph_order"] != decoded["glyph_order"]:
        raise ValueError("Glyph order mismatch")
    if set(expected_glyphs) != set(actual_glyphs):
        raise ValueError("Glyph names/order coverage mismatch")
    if expected["cmap"] != decoded["cmap"]:
        raise ValueError("Cmap mismatch")
    for name, source in expected_glyphs.items():
        actual = actual_glyphs[name]
        if source["metrics"] != actual["metrics"]:
            raise ValueError("Metric mismatch: " + name)
        if source["outline"] != actual["outline"]:
            raise ValueError("Exact line/cubic/control/closure sequence mismatch: " + name)
    return {"glyph_count": len(expected_glyphs), "comparison": "exact input/decoded equality", "render": "NOT_RUN", "native_acceptance": "NOT_RUN"}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("expected", type=Path)
    parser.add_argument("decoded", type=Path)
    args = parser.parse_args()
    print(json.dumps(compare(json.loads(args.expected.read_text()), json.loads(args.decoded.read_text())), indent=2))
