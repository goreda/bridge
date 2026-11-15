# W-gdb-014 B4 stereo/projection metadata (rewrites W-0283)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-014

```packet-json
{
 "packet_id": "W-gdb-014",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/BridgeVTDecode/Types.swift",
   "excerpt_block": "source2"
  },
  {
   "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
   "excerpt_block": "source1"
  },
  {
   "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
   "excerpt_block": "source1_1"
  }
 ],
 "interface": {
  "signatures": "normalize(container: [String: String], track: MediaInventory.Track) -> (StereoView?, Projection?)",
  "types": "StereoView { mono, left, right, raw-token-preserving fallback }; Projection { flat, vr180, equirect, raw-token-preserving fallback }; precedence: container side data > track metadata > absent(nil)",
  "ownership_lifetime": "strings copied; unrecognized tokens preserved typed (raw carried), never coerced",
  "caller": "MediaInventory consumers + BridgeVTDecode decode seam",
  "callee": "metadata normalization to StereoView/Projection enums (pinned below); DecodedFrame.stereoView/projection raw strings"
 },
 "test": {
  "command": "swift run media-inventory-tests && swift run active-media-inventory-tests",
  "expected": "exit 0 for both; final lines end '0 FAIL'; fixture rows assert known / raw-preserved / conflicting / absent classes; a guessed eye order fails as the negative control",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
   "Sources/BridgeVTDecode/Types.swift",
   "kits/metadata-fixtures/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
stereo/projection track metadata has no normalized parsing boundary: unknown values risk being guessed (wrong eye order shows as depth-inverted 3D), and malformed inputs have no typed path.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVFFmpegAdapter/MediaInventory.swift (sha256 bbc46476, 9860B) - track/container metadata surface; Sources/BridgeVTDecode/Types.swift (sha256 15d90863, 5918B) - decode-side type seam.
- real test command: swift run media-inventory-tests + swift run active-media-inventory-tests (existing Linux PASS per STATUS.md at the pin).

## expected behaviour
metadata parsing with normalized stereo/projection enums, unknown preservation (never an eye-order guess), precedence rules and typed malformed-input outcomes; the target metadata ABI is pinned below (integrator decision).

## exact call site and interface
MediaInventory's track metadata output + BridgeVTDecode Types (pinned files); normalized enums + fixtures + expected tables are the deliverable.

## pinned ABI decisions (integrator, 2026-11-15; metadata ABI now pinned)
normalized enums (integrator decision, bound to the pinned decode seam):
  public enum StereoView: Equatable, Sendable { case mono, left, right, unknown(String) }   // unknown preserves the raw token; never an eye-order guess
  public enum Projection: Equatable, Sendable { case flat, vr180, equirect, unknown(String) }
grounding at the pin: BridgeVTDecode DecodedFrame carries stereoView: String? (e.g. "mono","left","right") and projection: String? (e.g. "flat","vr180","equirect") as raw strings (Types.swift excerpt above); MediaInventory.Track carries codec/language/title/isDefault/isAttachedPicture/durationSeconds. precedence: container side data > track metadata dictionary > absence (absence = nil, never a default); malformed/unknown values land in .unknown(raw), never coerced. fixture classes: known token -> typed case; unknown token -> .unknown(token preserved); conflicting sources -> precedence rule; absent -> nil.

## behaviour that must not change
existing inventory checks stay green; unknown stays unknown (typed), never coerced.

## acceptance test (from the product repo)
fixtures replay green against the pinned surface; a guessed eye order (negative control) fails; existing suites stay green.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVFFmpegAdapter/MediaInventory.swift (sha256 bbc46476, lines 1-58 of 210)
```swift id=source1
import Foundation
import GorAVCore
import CFFmpeg

// R10 (arch-195b): media inventory - tracks, chapters, metadata, duration and
// the image-duration rule, read from a real opened avformat context through
// the R3 admission/transport path. Behavior, not only data: the image
// duration rule decides the effective playback duration for picture sources,
// and every read is provenance-tagged (container-reported vs rule-derived).

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
        public let startSeconds: Double
        public let endSeconds: Double

        public init(index: Int, title: String?, startSeconds: Double, endSeconds: Double) {
            self.index = index
            self.title = title
            self.startSeconds = startSeconds
            self.endSeconds = endSeconds
        }
    }

    public enum DurationProvenance: Equatable, Sendable {
        /// From the container (format duration or a stream duration).
        case container
        /// Rule-derived: a picture-only source gets the configured image
        /// duration because the container carries no playable timeline.
        case imageDurationRule
        /// No duration knowable from the container.
```

### Sources/GorAVFFmpegAdapter/MediaInventory.swift (sha256 bbc46476, lines 60-80 of 210)
```swift id=source1_1
    }

    public let tracks: [Track]
    public let chapters: [Chapter]
    /// Format-level tags, untrusted container text. Do not treat as log-safe.
    public let metadata: [String: String]
    public let durationSeconds: Double?
    public let durationProvenance: DurationProvenance

    public init(tracks: [Track], chapters: [Chapter], metadata: [String: String], durationSeconds: Double?, durationProvenance: DurationProvenance) {
        self.tracks = tracks
        self.chapters = chapters
        self.metadata = metadata
        self.durationSeconds = durationSeconds
        self.durationProvenance = durationProvenance
    }

    /// mpv semantics: an image (attached picture or image codec) plays as a
    /// still for a configured duration instead of ending instantly.
    public static let defaultImageDurationSeconds = 2.0

```

### Sources/BridgeVTDecode/Types.swift (sha256 15d90863, lines 1-40 of 128)
```swift id=source2
import Foundation
import BridgeDemux

/// One decoded video frame. `pts` uses the P-A1 RationalTime contract
/// (nil is preserved, never zero). `digest` is the deterministic
/// per-machine pixel digest (PixelDigest); it is recorded, asserted stable
/// across two runs on the same host, and NOT asserted across hosts.
public struct DecodedFrame: Sendable {
    public let pts: RationalTime?      // from the P-A1 RationalTime contract
    public let width: Int
    public let height: Int
    public let digest: String          // deterministic pixel digest, recorded
    // e2 foundation (plan/E2-FOUNDATION-CONTRACT.md, owner block 190 queue
    // item 5): additive defaulted fields only. nil means "not signaled",
    // never an invented value; digest semantics are unchanged.
    public let colorPrimaries: String?      // e.g. "bt709", "bt2020"
    public let transferFunction: String?    // e.g. "bt1886", "pq", "hlg"
    public let colorMatrix: String?
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
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"container":{"stereo":"left"},"track":{},"expect":{"stereoView":"left","projection":null}},
 {"container":{"stereo":"row-interleaved-rl"},"expect":{"stereoView":{"fallbackRawPreserved":"row-interleaved-rl"}}},
 {"container":{"projection":"equirect"},"track":{"projection":"flat"},"expect":{"projection":"equirect"},"rule":"container side data wins"}]
```
