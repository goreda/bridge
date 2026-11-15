# W-gdb-045 195b-N10 crop detection: consuming pin
state: candidate
solver lab: 1nstinct
reviewer lab: unclaimed
id: W-gdb-045

```packet-json
{
  "packet_id": "W-gdb-045",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/TapCropDetector.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "LumaPlane init?(bytes:width:height:strideBytes:); BorderScanConfig { barMaxLuma, barMaxPeak, minBarPx, maxBarFraction, minRemainFraction, sampleStride } + isValid; scan semantics (mean, peak) per pinned excerpt",
    "types": "luma values Int 0...255; bar/remainder fractions Double; typed config refusal via isValid",
    "ownership_lifetime": "plane bytes borrowed for the scan; detector returns value-type results; no retained plane references",
    "caller": "CropStage (the crop consumer) via TapCropDetector",
    "callee": "the lab detector behind the pinned surface"
  },
  "test": {
    "command": "python3 kits/n10-crop-pin/check.py kits/n10-crop-pin/fixtures.json",
    "expected": "exit 0; stdout 'n10-crop-pin: 3/3 planes PASS'; content-above-threshold and over-fraction rows are no-crop; negative control fails on mutation",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Sources/GorAVPlaybackCore/",
      "kits/n10-crop-pin/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/n10-crop-pin/check.py",
        "block": "kit1"
      },
      {
        "path": "kits/n10-crop-pin/fixtures.json",
        "block": "fixtures2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/n10-crop-pin/check.py kits/n10-crop-pin/fixtures.json",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:07:47.085189+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "n10-crop-pin: 3/3 planes PASS",
    "inline_files": [
      {
        "path": "kits/n10-crop-pin/check.py",
        "block": "kit1",
        "sha256": "646ab37340e1a77263f80f40e6dea6ffcfb7c1e36cbbacad1fb14269ab8a1713"
      },
      {
        "path": "kits/n10-crop-pin/fixtures.json",
        "block": "fixtures2",
        "sha256": "824748c46829c3bd0e09ef9df1c52e7eb7ca3faeca54020056c15955398cae67"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "60b837d48d6c915c63b2828bfc60a5257f215c78cc9687d9f14c5c6491c7e803",
    "last_5_lines": [
      "PASS bars40 -> (40, 40, 0, 0)",
      "PASS content17 -> no-crop",
      "PASS overfraction -> no-crop",
      "PASS negative control: luma-17 mutation flips the expected row (got no-crop)",
      "n10-crop-pin: 3/3 planes PASS"
    ],
    "receipt_sha256": "2b98c9ebfd5df4e78fbec05b840b3de5f80919451df8b68329c2bf3847b0aedd"
  }
}
```

## problem (what fails for the user)
crop detection (195b-N10) must match the pinned TapCropDetector semantics; a lab detector with invented thresholds crops real content or misses bars.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0280/N10; the lab module implements against the pinned interface below.

## expected behaviour
a crop detector over the pinned LumaPlane/BorderScanConfig surface: LumaPlane { bytes, width, height, strideBytes } (failable init), BorderScanConfig defaults barMaxLuma 16, barMaxPeak 48, minBarPx 2, maxBarFraction 0.45, minRemainFraction 0.20, sampleStride 8 with the pinned isValid rule; mean/peak row-column scan semantics per the pinned scan(); thresholds are the pinned defaults unless the caller overrides through BorderScanConfig, never hardcoded in the module. barMaxLuma is INCLUSIVE (a row/column with mean luma <= 16 counts as a bar), so content fixtures must sit strictly above 16 - the tight boundary witness is content at luma 17.

## exact call site and interface
TapCropDetector.swift (pinned excerpt): the module consumes LumaPlane and respects BorderScanConfig; CropStage applies the result downstream (sha256 f42207d0, unchanged); delivery as detector code + kits/n10-crop-pin/ fixtures.

## behaviour that must not change
the pinned defaults and isValid rule stay; a config failing isValid is refused typed; no geometry invention beyond detected bars.

## acceptance test (from the product repo)
python3 kits/n10-crop-pin/check.py kits/n10-crop-pin/fixtures.json exits 0; the three golden planes match their crop/no-crop outcomes; a one-luma-value mutation flips the expected row and fails the negative control.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/TapCropDetector.swift (sha256 648d03d4, lines 14-55 of 235)
```swift id=source1
public struct LumaPlane: Equatable, Sendable {
    public let bytes: [UInt8]
    public let width: Int
    public let height: Int
    public let strideBytes: Int
    public init?(bytes: [UInt8], width: Int, height: Int, strideBytes: Int) {
        guard width > 0, height > 0, strideBytes >= width else { return nil }
        let (lastRow, overflow) = strideBytes.multipliedReportingOverflow(by: height - 1)
        let (needed, overflow2) = lastRow.addingReportingOverflow(width)
        guard !overflow, !overflow2, bytes.count >= needed else { return nil }
        self.bytes = bytes; self.width = width; self.height = height
        self.strideBytes = strideBytes
    }
}

public struct BorderScanConfig: Equatable, Sendable {
    /// Inclusive mean-luma ceiling for a row/column to count as a black bar.
    public var barMaxLuma: Int = 16
    /// No sampled pixel inside a bar row/column may exceed this (letterbox
    /// bars with noise/logo residue stay bars; bright content does not).
    public var barMaxPeak: Int = 48
    /// Bars thinner than this are ignored (1px edge noise is not a bar).
    public var minBarPx: Int = 2
    /// Per-dimension cap: bar share beyond this means dark content, not bars.
    public var maxBarFraction: Double = 0.45
    /// The remaining inner region must keep at least this share per dimension.
    public var minRemainFraction: Double = 0.20
    /// Pixel sampling step inside one row/column scan. >= 1.
    public var sampleStride: Int = 8
    public init(barMaxLuma: Int = 16, barMaxPeak: Int = 48, minBarPx: Int = 2,
                maxBarFraction: Double = 0.45, minRemainFraction: Double = 0.20,
                sampleStride: Int = 8) {
        self.barMaxLuma = barMaxLuma; self.barMaxPeak = barMaxPeak
        self.minBarPx = minBarPx; self.maxBarFraction = maxBarFraction
        self.minRemainFraction = minRemainFraction; self.sampleStride = sampleStride
    }
    public var isValid: Bool {
        (0...255).contains(barMaxLuma) && (0...255).contains(barMaxPeak)
            && barMaxLuma <= barMaxPeak && minBarPx >= 1 && sampleStride >= 1
            && maxBarFraction.isFinite && maxBarFraction > 0 && maxBarFraction < 0.5
            && minRemainFraction.isFinite && minRemainFraction > 0 && minRemainFraction <= 1
    }
```


## roles and state
solver lab: 1nstinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"plane": "uniform black bars top/bottom 40px on 360px height, content luma 32", "expect": "bars detected per BorderScanConfig defaults (barMaxLuma 16, barMaxPeak 48); content mean 32 > 16 keeps it out of the bar class unambiguously"}, {"plane": "full plane at uniform content luma 17", "expect": "no crop: 17 is one above the INCLUSIVE barMaxLuma 16, so the whole plane is content, never a bar"}, {"plane": "bars covering 50% height", "expect": "no crop: maxBarFraction 0.45 refusal"}]
```

```python id=kit1
#!/usr/bin/env python3
# n10-crop-pin: golden checker for the pinned TapCropDetector semantics.
# Ports the pinned LumaPlane/BorderScanConfig/TapCropDetector.detect logic
# (Sources/GorAVPlaybackCore/TapCropDetector.swift @ 2112af0d60df16c5473173b664903f76ce54173e)
# and replays generated fixture planes plus a luma-17 mutation negative control.
import json, sys

BAR_MAX_LUMA = 16      # inclusive
BAR_MAX_PEAK = 48
MIN_BAR_PX = 2
MAX_BAR_FRACTION = 0.45
MIN_REMAIN_FRACTION = 0.20
SAMPLE_STRIDE = 8

def make_plane(spec):
    w, h = spec["width"], spec["height"]
    stride = spec.get("stride", w)
    fill = spec["fill"]
    bars = spec.get("bars", {})
    bar_luma = spec.get("bar_luma", 0)
    px = bytearray([fill] * (stride * h))
    t, b = bars.get("top", 0), bars.get("bottom", 0)
    l, r = bars.get("left", 0), bars.get("right", 0)
    for y in range(h):
        for x in range(w):
            if y < t or y >= h - b or x < l or x >= w - r:
                px[y * stride + x] = bar_luma
    return bytes(px), w, h, stride

def scan(px, w, h, stride, horizontal, index, step):
    s = 0; peak = 0; n = 0
    if horizontal:
        base = index * stride
        x = 0
        while x < w:
            v = px[base + x]; s += v; peak = max(peak, v); n += 1; x += step
    else:
        y = 0
        while y < h:
            v = px[y * stride + index]; s += v; peak = max(peak, v); n += 1; y += step
    return (s // n if n else 0), peak

def detect(px, w, h, stride):
    # Exact port of TapCropDetector.detect with BorderScanConfig defaults.
    step = SAMPLE_STRIDE
    def is_bar_row(y):
        mean, peak = scan(px, w, h, stride, True, y, step)
        return mean <= BAR_MAX_LUMA and peak <= BAR_MAX_PEAK
    def is_bar_col(x):
        mean, peak = scan(px, w, h, stride, False, x, step)
        return mean <= BAR_MAX_LUMA and peak <= BAR_MAX_PEAK
    top = 0
    while top < h and is_bar_row(top): top += 1
    bottom = 0
    while bottom < h - top and is_bar_row(h - 1 - bottom): bottom += 1
    left = 0
    while left < w and is_bar_col(left): left += 1
    right = 0
    while right < w - left and is_bar_col(w - 1 - right): right += 1
    if top < MIN_BAR_PX: top = 0
    if bottom < MIN_BAR_PX: bottom = 0
    if left < MIN_BAR_PX: left = 0
    if right < MIN_BAR_PX: right = 0
    if top + bottom + left + right == 0: return None
    if (top + bottom) > MAX_BAR_FRACTION * h: return None
    if (left + right) > MAX_BAR_FRACTION * w: return None
    innerW, innerH = w - left - right, h - top - bottom
    if innerW < 1 or innerH < 1: return None
    if innerW < MIN_REMAIN_FRACTION * w: return None
    if innerH < MIN_REMAIN_FRACTION * h: return None
    s = 0; n = 0; y = top
    stepY = max(1, innerH // 16)
    while y < top + innerH:
        mean, _ = scan(px, w, h, stride, True, y, step)
        s += mean; n += 1; y += stepY
    if n > 0 and s // n <= BAR_MAX_LUMA: return None
    return (top, bottom, left, right)

def main():
    fixtures = json.load(open(sys.argv[1]))
    fails = 0
    passed = 0
    results = {}
    for fx in fixtures:
        px, w, h, stride = make_plane(fx)
        got = detect(px, w, h, stride)
        exp = fx["expect"]
        exp_t = None if exp is None else (exp["top"], exp["bottom"], exp["left"], exp["right"])
        ok = got == exp_t
        results[fx["name"]] = got
        if ok:
            passed += 1
            print("PASS %s -> %s" % (fx["name"], got if got else "no-crop"))
        else:
            fails += 1
            print("FAIL %s expected %s got %s" % (fx["name"], exp_t, got))
    # Negative control: the tight boundary witness. Content at luma 17 sits
    # strictly above barMaxLuma 16, so mutating bar rows to 17 must flip the
    # expected row: the 40px bars are no longer bars and detect returns nil.
    src = fixtures[0]
    mut = dict(src)
    mut["bar_luma"] = 17
    px, w, h, stride = make_plane(mut)
    mgot = detect(px, w, h, stride)
    if mgot is not None and mgot == results[src["name"]]:
        fails += 1
        print("FAIL negative control: luma-17 mutation kept the expected row %s" % (mgot,))
    else:
        print("PASS negative control: luma-17 mutation flips the expected row (got %s)" % (mgot if mgot else "no-crop",))
    total = len(fixtures)
    if fails:
        print("n10-crop-pin: %d/%d planes PASS, %d FAIL" % (passed, total, fails))
        sys.exit(1)
    print("n10-crop-pin: %d/%d planes PASS" % (passed, total))
    sys.exit(0)

if __name__ == "__main__":
    main()

```

```json id=fixtures2
[
 {"name": "bars40", "width": 320, "height": 360, "fill": 32,
  "bars": {"top": 40, "bottom": 40}, "bar_luma": 0,
  "expect": {"top": 40, "bottom": 40, "left": 0, "right": 0}},
 {"name": "content17", "width": 320, "height": 360, "fill": 17,
  "bars": {}, "expect": null},
 {"name": "overfraction", "width": 320, "height": 360, "fill": 32,
  "bars": {"top": 100, "bottom": 100}, "bar_luma": 0, "expect": null}
]

```

```text id=actual_run_log
PASS bars40 -> (40, 40, 0, 0)
PASS content17 -> no-crop
PASS overfraction -> no-crop
PASS negative control: luma-17 mutation flips the expected row (got no-crop)
n10-crop-pin: 3/3 planes PASS
```
