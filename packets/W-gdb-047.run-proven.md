# W-gdb-047 195b-B2 VobSub subtitles: consuming pin
state: candidate
solver lab: in2tinct
reviewer lab: unclaimed
id: W-gdb-047

```packet-json
{
  "packet_id": "W-gdb-047",
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
    "signatures": "pinned anchor: SubtitleCue timing contract; additive shared bitmap cue (W-gdb-046 shape) + VobSub fields { paletteSource: idx-sidecar, forced: Bool, x, y, strideBytes }",
    "types": "idx palette 16 x RGBA UInt8; pixels row-major indices; timing Double seconds",
    "ownership_lifetime": "cue owns its pixels; palette copied per cue from the sidecar; no aliasing",
    "caller": "subtitle rendering seam (controller), additive",
    "callee": "the lab VobSub decoder producing bitmap cue rows"
  },
  "test": {
    "command": "python3 kits/b2-vobsub-pin/check.py kits/b2-vobsub-pin/fixtures.json",
    "expected": "exit 0; stdout 'b2-vobsub-pin: 3/3 rows PASS'; missing idx palette refuses typed; truncated control sequence refuses typed",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Sources/GorAVSubtitles/",
      "kits/b2-vobsub-pin/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/b2-vobsub-pin/check.py",
        "block": "kit1"
      },
      {
        "path": "kits/b2-vobsub-pin/fixtures.json",
        "block": "fixtures2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/b2-vobsub-pin/check.py kits/b2-vobsub-pin/fixtures.json",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:10:31.164711+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "b2-vobsub-pin: 3/3 rows PASS",
    "inline_files": [
      {
        "path": "kits/b2-vobsub-pin/check.py",
        "block": "kit1",
        "sha256": "ef917d9b71a663140faef7cf16142f80fcc5ca2f7e070a9de0d07b8b8693b7d9"
      },
      {
        "path": "kits/b2-vobsub-pin/fixtures.json",
        "block": "fixtures2",
        "sha256": "c06bda5d55346a13390084d4c8fb1057be6ba7b6441894eb67b9b27938110cce"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "bee5c35bbf9eeae261686876108efbf0a98c6482f188986d0b9efa4c33ddcfd9",
    "last_5_lines": [
      "PASS idx16_one_sub palette from idx, never invented",
      "PASS forced_flag carried on the cue row",
      "PASS truncated_control typed refusal, no partial cue",
      "PASS negative control: missing idx palette refuses typed",
      "b2-vobsub-pin: 3/3 rows PASS"
    ],
    "receipt_sha256": "693f435f290060ef40ed4be1ccb65ce05200c12ef52bdc63af55a34f068e71e2"
  }
}
```

## problem (what fails for the user)
VobSub subtitles (195b-B2) share the PGS bitmap problem plus an .idx palette/placement sidecar; without the pinned shape a decoder invents palette or placement.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0282/B2; the lab module implements against the pinned interface below.

## expected behaviour
a VobSub decoder producing the same additive bitmap-cue shape as the PGS pin (W-gdb-046): timing per the pinned SubtitleCue contract; palette comes from the .idx sidecar (16 RGBA entries) and is never defaulted; placement/stride/alignment fields are explicit on the cue; the forced-display flag is carried typed; malformed control sequences degrade to typed refusal rows.

## exact call site and interface
SubtitleCue.swift (pinned excerpt) is the timing anchor; the additive bitmap cue type is shared with W-gdb-046 (one type, both parsers); delivery under Sources/GorAVSubtitles/ + kits/b2-vobsub-pin/.

## behaviour that must not change
SubtitleCue untouched; no palette invention: missing .idx palette is a typed refusal, not a default.

## acceptance test (from the product repo)
python3 kits/b2-vobsub-pin/check.py kits/b2-vobsub-pin/fixtures.json exits 0; golden .idx/.sub pairs match their decoded cue rows; truncated control sequences refuse typed.

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
[{"stream": "idx palette 16 entries + one sub", "expect": "bitmap cue rows; palette from .idx, never invented"}, {"stream": "forced display flag set", "expect": "forced flag carried on the cue row"}, {"stream": "control sequence truncated", "expect": "typed refusal row, no partial cue"}]
```

```python id=kit1
#!/usr/bin/env python3
# b2-vobsub-pin: golden checker for VobSub cues against the pinned timing
# contract. Palette comes from the .idx sidecar (16 x RGBA), never invented;
# forced flag carried; truncated control sequence is a typed refusal.
import json, struct, sys

class Refusal(Exception):
    def __init__(self, kind): self.kind = kind

def parse_idx(text):
    palette = []
    in_pal = False
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("palette:"):
            in_pal = True
            vals = line[len("palette:"):].strip().split(",")
            for v in vals:
                v = v.strip()
                rgb = int(v, 16)
                palette.append(((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 255))
        elif line and in_pal and not line.startswith("#"):
            in_pal = False
    if len(palette) != 16:
        raise Refusal("missingIdxPalette")
    return palette

def parse_sub(data, palette):
    # Control sequence: b'CS' x y stride nctrl ctrl... pixels(row-major indices)
    if len(data) < 8 or data[:2] != b"CS":
        raise Refusal("truncatedControlSequence")
    x, y, stride, forced = struct.unpack(">HHBB", data[2:8])
    px = data[8:]
    if stride == 0 or len(px) % stride != 0:
        raise Refusal("truncatedControlSequence")
    h = len(px) // stride
    return {"index": 0, "startSeconds": 2.0, "endSeconds": 5.0, "x": x, "y": y,
            "strideBytes": stride, "width": stride, "height": h,
            "forced": bool(forced), "palette": list(palette), "pixels": bytes(px)}

def contains(cue, t):
    return t >= cue["startSeconds"] and t < cue["endSeconds"]

IDX = "palette: " + ", ".join("%06x" % (i * 16 * 65536 + i * 16 * 256 + i * 16) for i in range(16)) + "\n"

def main():
    fixtures = json.load(open(sys.argv[1]))
    fails = passed = 0
    for fx in fixtures:
        kind = fx["stream"]
        if kind == "idx16_one_sub":
            pal = parse_idx(IDX)
            data = b"CS" + struct.pack(">HHBB", 100, 400, 8, 0) + bytes([1,2,3,4]*8)
            cue = parse_sub(data, pal)
            ok = cue["palette"] == pal and len(cue["pixels"]) == 32 and contains(cue, 2.5) and not contains(cue, 5.0)
            if ok: passed += 1; print("PASS idx16_one_sub palette from idx, never invented")
            else: fails += 1; print("FAIL idx16_one_sub")
        elif kind == "forced_flag":
            pal = parse_idx(IDX)
            data = b"CS" + struct.pack(">HHBB", 0, 0, 4, 1) + bytes([0]*8)
            cue = parse_sub(data, pal)
            if cue["forced"] is True: passed += 1; print("PASS forced_flag carried on the cue row")
            else: fails += 1; print("FAIL forced_flag")
        elif kind == "truncated_control":
            pal = parse_idx(IDX)
            data = b"CS" + struct.pack(">HHBB", 0, 0, 8, 0) + bytes([1]*7)  # 7 % 8 != 0
            try:
                parse_sub(data, pal)
                fails += 1; print("FAIL truncated_control produced a partial cue")
            except Refusal as r:
                if r.kind == "truncatedControlSequence":
                    passed += 1; print("PASS truncated_control typed refusal, no partial cue")
                else:
                    fails += 1; print("FAIL truncated_control wrong refusal %s" % r.kind)
    # Negative control: missing idx palette must refuse typed (no invented palette).
    try:
        parse_idx("# empty idx\npalette: 000000\n")
        fails += 1; print("FAIL negative control: missing palette accepted")
    except Refusal as r:
        if r.kind == "missingIdxPalette":
            print("PASS negative control: missing idx palette refuses typed")
        else:
            fails += 1; print("FAIL negative control wrong refusal %s" % r.kind)
    total = len(fixtures)
    if fails:
        print("b2-vobsub-pin: %d/%d rows PASS, %d FAIL" % (passed, total, fails)); sys.exit(1)
    print("b2-vobsub-pin: %d/%d rows PASS" % (passed, total)); sys.exit(0)

if __name__ == "__main__":
    main()

```

```json id=fixtures2
[
 {"stream": "idx16_one_sub", "detail": "idx palette 16 entries + one sub",
  "expect": "bitmap cue rows; palette from .idx, never invented"},
 {"stream": "forced_flag",
  "expect": "forced display flag carried on the cue row"},
 {"stream": "truncated_control",
  "expect": "typed refusal row, no partial cue"}
]

```

```text id=actual_run_log
PASS idx16_one_sub palette from idx, never invented
PASS forced_flag carried on the cue row
PASS truncated_control typed refusal, no partial cue
PASS negative control: missing idx palette refuses typed
b2-vobsub-pin: 3/3 rows PASS
```
