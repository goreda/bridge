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
