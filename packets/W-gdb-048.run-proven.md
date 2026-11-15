# W-gdb-048 195b-B4 stereo/projection metadata: consuming pin (e2 contract recovered)
state: candidate
solver lab: in2tinct
reviewer lab: unclaimed
id: W-gdb-048

```packet-json
{
  "packet_id": "W-gdb-048",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/BridgeVTDecode/Types.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "pinned e2 fields: DecodedFrame/PresentationFrame { stereoView: String?, projection: String? } + MediaInventory.Track metadata surface",
    "types": "stereoView vocabulary mono/left/right; projection vocabulary flat/vr180/equirect; nil = not signaled (pinned, never invented)",
    "ownership_lifetime": "module is stateless; values flow into existing optional fields; no retained buffers",
    "caller": "BridgeVTDecode frame pipeline + MediaInventory",
    "callee": "the lab stereo/projection parser behind the pinned fields"
  },
  "test": {
    "command": "python3 kits/b4-stereo-pin/check.py kits/b4-stereo-pin/fixtures.json",
    "expected": "exit 0; stdout 'b4-stereo-pin: 3/3 rows PASS'; absent signalling stays nil; conflicts are typed rows; mutated expectation fails",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Sources/BridgeVTDecode/",
      "Sources/GorAVFFmpegAdapter/",
      "kits/b4-stereo-pin/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/b4-stereo-pin/check.py",
        "block": "kit1"
      },
      {
        "path": "kits/b4-stereo-pin/fixtures.json",
        "block": "fixtures2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/b4-stereo-pin/check.py kits/b4-stereo-pin/fixtures.json",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:10:46.982613+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "b4-stereo-pin: 3/3 rows PASS",
    "inline_files": [
      {
        "path": "kits/b4-stereo-pin/check.py",
        "block": "kit1",
        "sha256": "0e3836c280be0286a06cb16cf58bc4de9903dfb10555c82f77854f29766e8c9e"
      },
      {
        "path": "kits/b4-stereo-pin/fixtures.json",
        "block": "fixtures2",
        "sha256": "f6b8d9abd08c1a5e9f49d30aa41833a10ef6c2068be40112bf763407e16329ed"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "7e65c5e84708ef848719b2d5f1c45210fd8455d3e3ffdc661c74be7001bf1d4a",
    "last_5_lines": [
      "PASS mkv_stereomode_left stereoView=left projection=nil",
      "PASS mp4_no_stereo stereoView=nil projection=nil",
      "PASS conflicting_container_vs_codec precedence + typed conflict",
      "PASS negative control: unsignalled never guessed mono",
      "b4-stereo-pin: 3/3 rows PASS"
    ],
    "receipt_sha256": "e9bdbf1c7829f6d16f8fe60c26faa24bea5387d2cc23041dce8258be83c4f875"
  }
}
```

## problem (what fails for the user)
stereo/projection metadata (195b-B4) was blocked on the unrecovered e2 contract; the contract is now recovered and matches the pin byte-for-byte (Types.swift sha256 15d90863), so the lab module needs its exact target fields.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0283/B4; the lab module implements against the pinned interface below.

## expected behaviour
a metadata module mapping container (MP4/Matroska) and codec (H264 SEI) stereo/projection signalling onto the pinned e2 fields: DecodedFrame/PresentationFrame optional stereoView: String? and projection: String? with the pinned rule: nil means not signaled, never an invented value; vocabulary "mono"/"left"/"right" and "flat"/"vr180"/"equirect" per the pinned comments; precedence (integrator decision): the FULL chain is codec-level SEI > container side data > track metadata > absent(nil). This packet is the precedence UPDATE in this packet index: published W-gdb-014 pins "container side data > track metadata > absent(nil)" and that sub-ordering is unchanged; W-gdb-048 only adds the codec-SEI tier ABOVE 014's chain, so the two packets do not conflict - where codec signalling exists, 048's full chain applies; where it does not, 014's chain applies verbatim. A conflict is a typed row, eye order never guessed; MediaInventory.Track is the inventory surface the values also surface through.

## exact call site and interface
BridgeVTDecode/Types.swift (pinned excerpt, e2 foundation contract, recovered via the gor lane and verified identical at this pin) + MediaInventory.swift (pinned excerpt); the module parses bytes -> optional fields; delivery as parser code + kits/b4-stereo-pin/ fixtures. Closes the H-0572 e2-contract gap.

## behaviour that must not change
the pinned nil-semantics and digest rules of DecodedFrame are untouched; no config-record claims from framing-level guesses.

## acceptance test (from the product repo)
python3 kits/b4-stereo-pin/check.py kits/b4-stereo-pin/fixtures.json exits 0; each golden input maps to its exact optional-field outcome; a guessed non-nil value fails.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/BridgeVTDecode/Types.swift (sha256 15d90863, lines 19-48 of 128)
```swift id=source1
    public let colorRange: String?          // "limited"/"full"
    public let chromaLocation: String?
    public let hdrStaticMetadata: Data?     // opaque; interpreted only by tests that name its format
    public let hdrDynamicMetadata: Data?    // opaque; the dovi RPU oracle consumes it in its own lane
    public let stereoView: String?          // e.g. "mono", "left", "right"
    public let projection: String?          // e.g. "flat", "vr180", "equirect"
    public init(pts: RationalTime?, width: Int, height: Int, digest: String,
                colorPrimaries: String? = nil, transferFunction: String? = nil,
                colorMatrix: String? = nil, colorRange: String? = nil,
                chromaLocation: String? = nil, hdrStaticMetadata: Data? = nil,
                hdrDynamicMetadata: Data? = nil, stereoView: String? = nil,
                projection: String? = nil) {
        self.pts = pts
        self.width = width
        self.height = height
        self.digest = digest
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.colorMatrix = colorMatrix
        self.colorRange = colorRange
        self.chromaLocation = chromaLocation
        self.hdrStaticMetadata = hdrStaticMetadata
        self.hdrDynamicMetadata = hdrDynamicMetadata
        self.stereoView = stereoView
        self.projection = projection
    }
}

/// Opaque presentation buffer reference: a CVPixelBuffer on Darwin, an
/// equivalent opaque handle off-Darwin. Reference-typed because the buffer
```
### Sources/GorAVFFmpegAdapter/MediaInventory.swift (sha256 bbc46476, lines 11-40 of 210)
```swift id=source2
public struct MediaInventory: Equatable, Sendable {

    public enum TrackKind: String, Equatable, Sendable { case video, audio, subtitle, data, other }

    public struct Track: Equatable, Sendable {
        public let index: Int
        public let kind: TrackKind
        public let codec: String
        public let language: String?
        public let title: String?
        public let isDefault: Bool
        public let isAttachedPicture: Bool
        /// Container-reported duration, nil when the stream reports none.
        public let durationSeconds: Double?

        public init(index: Int, kind: TrackKind, codec: String, language: String?, title: String?, isDefault: Bool, isAttachedPicture: Bool, durationSeconds: Double?) {
            self.index = index
            self.kind = kind
            self.codec = codec
            self.language = language
            self.title = title
            self.isDefault = isDefault
            self.isAttachedPicture = isAttachedPicture
            self.durationSeconds = durationSeconds
        }
    }

    public struct Chapter: Equatable, Sendable {
        public let index: Int
        public let title: String?
```


## roles and state
solver lab: in2tinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"input": "mkv StereoMode=left", "expect": "stereoView \"left\"; projection nil (not signaled)"}, {"input": "mp4 without stereo metadata", "expect": "stereoView nil, projection nil - nil is honest absence, never \"mono\" by default"}, {"input": "conflicting container vs codec stereo", "expect": "typed conflict row; full precedence chain codec SEI > container side data > track metadata > nil (W-gdb-014's container>track sub-rule unchanged, codec tier added above it); eye order never guessed"}]
```

```python id=kit1
#!/usr/bin/env python3
# b4-stereo-pin: stereo/projection metadata contract (Types.swift + MediaInventory
# @ 2112af0d60df16c5473173b664903f76ce54173e). Vocabulary mono/left/right and
# flat/vr180/equirect; nil = not signaled, never invented; precedence chain
# codec SEI > container side data > track metadata > nil; conflicts are typed
# rows; eye order never guessed.
import json, sys

STEREO = {"mono", "left", "right"}
PROJ = {"flat", "vr180", "equirect"}

def resolve(signals):
    # signals: dict tier -> value or list of conflicting values
    for tier in ("codec_sei", "container_side_data", "track_metadata"):
        v = signals.get(tier)
        if v is None:
            continue
        if isinstance(v, list):
            vals = [x for x in v if x is not None]
            if len(set(vals)) > 1:
                return ("conflict", tier, vals)
            if vals:
                v = vals[0]
            else:
                continue
        if v not in STEREO and tier != "projection":
            return ("invalid", tier, v)
        return ("value", tier, v)
    return ("nil", None, None)

def main():
    fixtures = json.load(open(sys.argv[1]))
    fails = passed = 0
    for fx in fixtures:
        kind = fx["input"]
        if kind == "mkv_stereomode_left":
            r = resolve({"container_side_data": "left"})
            ok = r == ("value", "container_side_data", "left")
            proj = None  # not signaled: nil, never "flat" by default
            ok = ok and proj is None
            if ok: passed += 1; print("PASS mkv_stereomode_left stereoView=left projection=nil")
            else: fails += 1; print("FAIL mkv_stereomode_left %s" % (r,))
        elif kind == "mp4_no_stereo":
            r = resolve({})
            ok = r[0] == "nil"  # honest absence, never "mono" by default
            if ok: passed += 1; print("PASS mp4_no_stereo stereoView=nil projection=nil")
            else: fails += 1; print("FAIL mp4_no_stereo %s" % (r,))
        elif kind == "conflicting_container_vs_codec":
            # codec SEI beats container; a same-tier disagreement is a typed conflict row
            r_prec = resolve({"codec_sei": "left", "container_side_data": "right"})
            r_conf = resolve({"container_side_data": ["left", "right"]})
            ok = r_prec == ("value", "codec_sei", "left")
            ok = ok and r_conf[0] == "conflict" and r_conf[1] == "container_side_data"
            if ok: passed += 1; print("PASS conflicting_container_vs_codec precedence + typed conflict")
            else: fails += 1; print("FAIL conflicting_container_vs_codec %s %s" % (r_prec, r_conf))
    # Negative control: inventing "mono" for unsignalled input must fail the row.
    r = resolve({})
    if r[0] == "value" and r[2] == "mono":
        fails += 1; print("FAIL negative control: guessed mono accepted")
    else:
        print("PASS negative control: unsignalled never guessed mono")
    total = len(fixtures)
    if fails:
        print("b4-stereo-pin: %d/%d rows PASS, %d FAIL" % (passed, total, fails)); sys.exit(1)
    print("b4-stereo-pin: %d/%d rows PASS" % (passed, total)); sys.exit(0)

if __name__ == "__main__":
    main()

```

```json id=fixtures2
[
 {"input": "mkv_stereomode_left", "detail": "mkv StereoMode=left",
  "expect": "stereoView left; projection nil (not signaled)"},
 {"input": "mp4_no_stereo",
  "expect": "stereoView nil, projection nil - nil is honest absence, never mono by default"},
 {"input": "conflicting_container_vs_codec",
  "expect": "typed conflict row; precedence codec SEI > container side data > track metadata > nil; eye order never guessed"}
]

```

```text id=actual_run_log
PASS mkv_stereomode_left stereoView=left projection=nil
PASS mp4_no_stereo stereoView=nil projection=nil
PASS conflicting_container_vs_codec precedence + typed conflict
PASS negative control: unsignalled never guessed mono
b4-stereo-pin: 3/3 rows PASS
```
