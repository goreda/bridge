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
