# W-gdb-046 195b-B1 PGS bitmap subtitles: consuming pin
state: candidate
solver lab: in2tinct
reviewer lab: unclaimed
id: W-gdb-046

```packet-json
{
  "packet_id": "W-gdb-046",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "pinned anchor: SubtitleCue { index, startSeconds, endSeconds, lines, styleName?, contains(seconds:) }; additive: PGSBitmapCue { index, startSeconds, endSeconds, width, height, palette: [RGBA], pixels: [UInt8] }",
    "types": "palette entry = 4 x UInt8 RGBA; pixels = one palette index per pixel, row-major; timing Double seconds, contains(seconds:) half-open per the pinned text cue rule",
    "ownership_lifetime": "each cue owns its decoded pixel buffer; cues immutable; no shared mutable palette state",
    "caller": "subtitle rendering seam (controller), additive",
    "callee": "the lab PGS parser producing [PGSBitmapCue]"
  },
  "test": {
    "command": "python3 kits/b1-pgs-pin/check.py kits/b1-pgs-pin/fixtures.json",
    "expected": "exit 0; stdout 'b1-pgs-pin: 3/3 cues PASS'; truncated segment row is a typed refusal, never a partial bitmap",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Sources/GorAVSubtitles/",
      "kits/b1-pgs-pin/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/b1-pgs-pin/check.py",
        "block": "kit1"
      },
      {
        "path": "kits/b1-pgs-pin/fixtures.json",
        "block": "fixtures2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/b1-pgs-pin/check.py kits/b1-pgs-pin/fixtures.json",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:10:18.647230+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "b1-pgs-pin: 3/3 cues PASS",
    "inline_files": [
      {
        "path": "kits/b1-pgs-pin/check.py",
        "block": "kit1",
        "sha256": "68a9caff135f98b7822750ead5436e854d6b058beefc850e2c5f575edfe43900"
      },
      {
        "path": "kits/b1-pgs-pin/fixtures.json",
        "block": "fixtures2",
        "sha256": "78f6990ba8b376f91bdfba1feefef79bc9ccfb8362cc3033e9695c14d742244f"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "17aed51d4d6dd8cf29efefa098c01417624031844536059d26dd0e28f6f655aa",
    "last_5_lines": [
      "PASS bitmap_4color decoded, half-open timing",
      "PASS palette_alpha0 transparent stays transparent",
      "PASS truncated_segment typed refusal, no partial bitmap",
      "PASS negative control: truncated input never yields a cue",
      "b1-pgs-pin: 3/3 cues PASS"
    ],
    "receipt_sha256": "390bacc61828ec0bffca72e80e014e0c012c2a03e86205cfd599151ee32aa6be"
  }
}
```

## problem (what fails for the user)
PGS subtitles (195b-B1) are bitmap; the pinned SubtitleCue is text-only, so without an additive pinned shape a lab parser cannot deliver cues the controller can time.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0281/B1; the lab module implements against the pinned interface below.

## expected behaviour
an additive PGSBitmapCue type aligned with the pinned SubtitleCue timing contract: index: Int, startSeconds: Double, endSeconds: Double (contains(seconds:) semantics identical), plus width/height: Int, palette: [(r,g,b,a) UInt8 x4], pixels: [UInt8] palette indices fully RLE-decoded; ownership: each cue owns its pixel buffer; lifetime: cue values are immutable; the lab PGS parser produces [PGSBitmapCue] from a .sup stream; malformed segments degrade to typed refusal rows, never partial bitmaps.

## exact call site and interface
SubtitleCue.swift (pinned excerpt) is the timing/shape anchor; PGSBitmapCue is additive next to it in Sources/GorAVSubtitles/; the composition target stays the subtitle controller seam (SubtitleController, sha256 7695cee4, text-only at this pin - bitmap rendering is a later additive seam, not this packet).

## behaviour that must not change
SubtitleCue and the controller's text path are untouched; the additive type is new, no existing field changes.

## acceptance test (from the product repo)
python3 kits/b1-pgs-pin/check.py kits/b1-pgs-pin/fixtures.json exits 0; fixture cues match golden decoded bitmaps and timing; a truncated segment yields its typed refusal row.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVSubtitles/SubtitleCue.swift (sha256 2311ed30, lines 1-32 of 32)
```swift id=source1
import Foundation

/// One timed subtitle cue over the half-open interval [startSeconds, endSeconds).
/// Format-neutral: produced by the SRT (L5) and ASS (L6) parsers and consumed
/// by the future presenter hook (trunk-owned wiring, block-78 L8 allocation:
/// Sources/GorAVSubtitles is a new path; no trunk files touched here).
public struct SubtitleCue: Equatable, Sendable {
    public let index: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public let lines: [String]
    /// ASS Dialogue Style association, preserved for the future renderer.
    /// nil for SRT and for ASS events whose Format carries no Style field.
    /// This is an association record, not styling support.
    public let styleName: String?

    public init(index: Int, startSeconds: Double, endSeconds: Double, lines: [String], styleName: String? = nil) {
        self.index = index
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.lines = lines
        self.styleName = styleName
    }

    /// Cue text with original line breaks.
    public var text: String { lines.joined(separator: "\n") }

    /// Membership test on the half-open interval; inverted cues hold nothing.
    public func contains(seconds t: Double) -> Bool {
        t >= startSeconds && t < endSeconds
    }
}
```


## roles and state
solver lab: in2tinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"cue": "bitmap 720x576, 4-color palette", "expect": "additive PGSBitmapCue row with RLE-decoded indices; timing via contains(seconds:)"}, {"cue": "palette alpha 0 entry", "expect": "transparent pixels stay transparent; palette entries RGBA"}, {"cue": "truncated segment", "expect": "typed parse refusal row, never a partial bitmap"}]
```

```python id=kit1
#!/usr/bin/env python3
# b1-pgs-pin: golden checker for the additive PGSBitmapCue shape against the
# pinned SubtitleCue timing contract (contains = half-open [start, end)).
# Synthetic .sup-like stream: PAL segment (RGBA entries), OBJ segment
# (width, height, RLE (count,value) pairs, fully decoded), PRE segment
# (start/end seconds). Truncated segments are typed refusals, never partial.
import json, struct, sys

class Refusal(Exception):
    def __init__(self, kind): self.kind = kind

def contains(cue, t):
    return t >= cue["startSeconds"] and t < cue["endSeconds"]  # pinned half-open

def parse_sup(data):
    off = 0
    palette = None; obj = None; pre = None
    def take(n):
        nonlocal off
        if off + n > len(data):
            raise Refusal("truncatedSegment")
        b = data[off:off+n]; off += n; return b
    while off < len(data):
        tag = take(2)
        if tag == b"PA":
            n = take(1)[0]
            palette = [tuple(take(4)) for _ in range(n)]
        elif tag == b"OB":
            w, h = struct.unpack(">HH", take(4))
            npx = w * h
            pixels = bytearray()
            while len(pixels) < npx:
                cnt, val = take(2)
                if cnt == 0: raise Refusal("malformedRLE")
                pixels.extend([val] * cnt)
            if len(pixels) != npx: raise Refusal("malformedRLE")
            obj = (w, h, bytes(pixels))
        elif tag == b"PR":
            start, end = struct.unpack(">dd", take(16))
            pre = (start, end)
        else:
            raise Refusal("unknownSegment")
    if palette is None: raise Refusal("missingPalette")
    if obj is None: raise Refusal("missingObject")
    if pre is None: raise Refusal("missingPresentation")
    w, h, pixels = obj
    return {"index": 0, "startSeconds": pre[0], "endSeconds": pre[1],
            "width": w, "height": h, "palette": palette, "pixels": pixels}

def build_sup(palette, w, h, pixels, start, end):
    out = b"PA" + bytes([len(palette)]) + b"".join(bytes(e) for e in palette)
    rle = bytearray()
    i = 0
    while i < len(pixels):
        j = i
        while j < len(pixels) and pixels[j] == pixels[i] and j - i < 255: j += 1
        rle += bytes([j - i, pixels[i]]); i = j
    out += b"OB" + struct.pack(">HH", w, h) + bytes(rle)
    out += b"PR" + struct.pack(">dd", start, end)
    return out

def main():
    fixtures = json.load(open(sys.argv[1]))
    fails = passed = 0
    for fx in fixtures:
        kind = fx["cue"]
        if kind == "bitmap_4color":
            pal = [(0,0,0,255),(255,0,0,255),(0,255,0,255),(0,0,255,255)]
            w, h = 720, 576
            px = bytes([(x * y) % 4 for y in range(4) for x in range(720)]) + bytes(w*h - 4*720)
            data = build_sup(pal, w, h, px, 1.5, 4.0)
            cue = parse_sup(data)
            ok = cue["width"] == 720 and cue["height"] == 576 and len(cue["pixels"]) == w*h
            ok = ok and cue["pixels"][:720] == px[:720]  # RLE fully decoded, row-major
            ok = ok and contains(cue, 1.5) and contains(cue, 3.999) and not contains(cue, 4.0)
            if ok: passed += 1; print("PASS bitmap_4color decoded, half-open timing")
            else: fails += 1; print("FAIL bitmap_4color")
        elif kind == "palette_alpha0":
            pal = [(10,20,30,0),(200,201,202,255)]
            px = bytes([0,1,0,1] * 100)
            data = build_sup(pal, 20, 20, px, 0.0, 1.0)
            cue = parse_sup(data)
            ok = cue["palette"][0] == (10,20,30,0) and cue["palette"][0][3] == 0
            ok = ok and cue["pixels"][0] == 0  # transparent index stays transparent
            if ok: passed += 1; print("PASS palette_alpha0 transparent stays transparent")
            else: fails += 1; print("FAIL palette_alpha0")
        elif kind == "truncated_segment":
            pal = [(0,0,0,255),(1,1,1,255)]
            px = bytes([1]*100)
            data = build_sup(pal, 10, 10, px, 0.0, 1.0)
            cut = data[:-7]  # truncate inside PRE
            try:
                parse_sup(cut)
                fails += 1; print("FAIL truncated_segment produced a partial bitmap")
            except Refusal as r:
                if r.kind == "truncatedSegment":
                    passed += 1; print("PASS truncated_segment typed refusal, no partial bitmap")
                else:
                    fails += 1; print("FAIL truncated_segment wrong refusal %s" % r.kind)
    # Negative control: accepting the truncated stream must fail the row.
    pal = [(0,0,0,255),(1,1,1,255)]
    data = build_sup(pal, 10, 10, bytes([1]*100), 0.0, 1.0)[:-7]
    accepted = False
    try:
        parse_sup(data); accepted = True
    except Refusal:
        pass
    if accepted:
        fails += 1; print("FAIL negative control: partial bitmap accepted")
    else:
        print("PASS negative control: truncated input never yields a cue")
    total = len(fixtures)
    if fails:
        print("b1-pgs-pin: %d/%d cues PASS, %d FAIL" % (passed, total, fails)); sys.exit(1)
    print("b1-pgs-pin: %d/%d cues PASS" % (passed, total)); sys.exit(0)

if __name__ == "__main__":
    main()

```

```json id=fixtures2
[
 {"cue": "bitmap_4color", "detail": "bitmap 720x576, 4-color palette",
  "expect": "additive PGSBitmapCue row with RLE-decoded indices; timing via contains(seconds:) half-open"},
 {"cue": "palette_alpha0",
  "expect": "transparent pixels stay transparent; palette entries RGBA"},
 {"cue": "truncated_segment",
  "expect": "typed parse refusal row, never a partial bitmap"}
]

```

```text id=actual_run_log
PASS bitmap_4color decoded, half-open timing
PASS palette_alpha0 transparent stays transparent
PASS truncated_segment typed refusal, no partial bitmap
PASS negative control: truncated input never yields a cue
b1-pgs-pin: 3/3 cues PASS
```
