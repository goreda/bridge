# W-gdb-d61: 195b-61 follow-on: record the container format name in MediaInventory (capture only, rev 4)
> rev 2026-11-17-r5: pin rolled bb49fc6 -> 5b448b8 (native96-102/VT-PRODUCER work grew FFmpegSoftwareDecoder.swift); ex_format_name_precedent re-located 798-798 -> 840-840, byte-identical, hash unchanged (15571fec); all excerpts re-verified byte-identical at 5b448b8.

> rev 2026-11-16-r4: pin rolled a34e2cd -> bb49fc6 (VT zero-copy/product merges moved FFmpegSoftwareDecoder.swift); the stale excerpts were re-located to identical content at new line ranges and their hashes recomputed; every other excerpt re-verified byte-identical at bb49fc6.

> rev 2026-11-16-r2: excerpt ranges/hashes rebound to pin 8786bfe3 (Team A log-verify fixes: 040 whole-file 1-137, d59 ex_store 119-155, d64 ex_test_tail 115-134, G0761 hash map added, stale header shas replaced). Supersedes the 2026-11-16 minting only after a fresh gate-flow run_proof binds to these bytes
> rev 2026-11-16-r3: pin rolled 8786bfe3 -> a34e2cd (arch-197e item 5 self-decision; the delta is docs/LEDGER.tsv only, every excerpt body re-verified byte-identical and excerpt_sha256_8 unchanged). Supersedes the r2 receipts once a fresh gate-flow run_proof binds at a34e2cd.


Rev 4 after the ops gate: capture-only. Add `containerFormat: String?` to MediaInventory, filled in extract(fromOpenedContext:) from the opened context, exactly the way the decoders already read it (String(cString: fc.pointee.iformat.pointee.name)). effectiveDurationSeconds is NOT changed, there is no still-image rule, and no single-frame claim is made. The earlier still-image rule and codec heuristic are withdrawn. The value is informational for later consumers.

Informational measurement by the writer, ffprobe from ffmpeg 4.4.2: plain png/jpg/bmp/webp report format_name png_pipe/jpeg_pipe/bmp_pipe/webp_pipe and no duration; a 0.2 s avi reports avi; a 0.2 s png mkv reports matroska,webm. Ops showed that two concatenated PNGs also read as png_pipe with no duration, so the format name does NOT prove a single image. This packet therefore captures the name and uses it for nothing.

Not in scope: any change to effectiveDurationSeconds or the image-duration rule, still-image or sequence detection, frame counting, UI, playlist/autoload. Excerpts are verbatim lines from the pinned product sha; the first comment line of each block is a label added by the packet writer and is not part of the excerpt hash. Fixture blocks are new text proposed by this packet.

```packet-json
{
  "packet": "W-gdb-d61",
  "code_owner": "gdb gorav integrator (decoder lane), owner of Sources/GorAVPlaybackCore and Sources/GorAVFFmpegAdapter on gorav/engine",
  "scope": "implementation",
  "product_repo": "goreda/gorav",
  "product_branch": "engine",
  "product_sha": "5b448b89394709decd046d5bea214ac19c05f11f",
  "touched_files": [
    {
      "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
      "excerpt_block": "ex_inventory_fields_init",
      "lines": "62-78"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
      "excerpt_block": "ex_effective_duration_unchanged",
      "lines": "79-90"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
      "excerpt_block": "ex_extract_tail",
      "lines": "187-190"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift",
      "excerpt_block": "ex_format_name_precedent",
      "lines": "840-840"
    },
    {
      "path": "Sources/media-inventory-tests/main.swift",
      "excerpt_block": "ex_existing_image_tests",
      "lines": "43-58"
    },
    {
      "path": "Sources/media-inventory-tests/main.swift",
      "excerpt_block": "ex_test_tail",
      "lines": "76-79"
    }
  ],
  "excerpt_sha256_8": {
    "ex_inventory_fields_init": "6e24beb1",
    "ex_effective_duration_unchanged": "b0feffd4",
    "ex_extract_tail": "ea51824a",
    "ex_format_name_precedent": "15571fec",
    "ex_existing_image_tests": "99661792",
    "ex_test_tail": "41d0efad"
  },
  "interface": {
    "signatures": "MediaInventory.init(tracks:chapters:metadata:durationSeconds:durationProvenance:containerFormat: String? = nil) with the new defaulted last parameter (existing 5-argument call sites compile unchanged); public let containerFormat: String?. extract(fromOpenedContext:) passes the demuxer name when fc.pointee.iformat is non-nil. effectiveDurationSeconds is untouched.",
    "types": "MediaInventory stays Equatable and Sendable; containerFormat is an immutable String? holding a demuxer name such as png_pipe, avi or matroska,webm.",
    "ownership_lifetime": "Value copied from the opened context on the format owner queue inside extract; no pointer escapes; survives context teardown. No I/O, seek or probe is added.",
    "caller": "MediaInventory.load and the active decoder snapshot path (extract).",
    "callee": "String(cString: fc.pointee.iformat.pointee.name) in extract; the MediaInventory memberwise init."
  },
  "test": {
    "command": "swift run media-inventory-tests",
    "expected": "Exit 0. PASS I1..I6 unchanged, PASS C1 through C5, four R lines for the two repo fixtures (containerFormat captured for e1-h264-aac-10s.mp4 containing 'mov' and active-inventory-chapters.mkv containing 'matroska'; effective duration provenance .container for both), ends with 'media-inventory-tests: all pass'. Still-image rows are not asserted: the pinned provider build has no image2/mjpeg demuxer (env-typed note, not a forced pass).",
    "fixture_block": "fx_format_capture_tests",
    "note": "Run by the integrator on Linux with the pinned provider; a lab without the repo returns the patch and states \"unrun\"."
  },
  "target": {
    "branch": "lane/gdb-196p-decoder (integrator creates it from product_sha; never ohal/gorav main or PR 3)",
    "paths": [
      "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
      "Sources/media-inventory-tests/main.swift",
      "fixtures/still-png.png",
      "fixtures/still-jpg.jpg",
      "fixtures/short-png-seq.mkv"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/media-inventory-tests/main.swift",
        "block": "merged_main"
      },
      {
        "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
        "block": "fx_containerformat_patch"
      }
    ]
  }
}
```

## Excerpt ex_inventory_fields_init

```swift id=ex_inventory_fields_init
// Sources/GorAVFFmpegAdapter/MediaInventory.swift lines 62-78 @ 5b448b89394709decd046d5bea214ac19c05f11f
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
```

## Excerpt ex_effective_duration_unchanged

```swift id=ex_effective_duration_unchanged
// Sources/GorAVFFmpegAdapter/MediaInventory.swift lines 79-90 @ 5b448b89394709decd046d5bea214ac19c05f11f
    public static let defaultImageDurationSeconds = 2.0

    /// Effective playback duration: the container duration when known; for a
    /// picture-only source with no container duration, the image-duration rule.
    public func effectiveDurationSeconds(imageDuration: Double = MediaInventory.defaultImageDurationSeconds) -> (seconds: Double?, provenance: DurationProvenance) {
        if let d = durationSeconds, d.isFinite, d >= 0 { return (d, durationProvenance) }
        let playable = tracks.filter { $0.kind == .video || $0.kind == .audio }
        if !playable.isEmpty, playable.allSatisfy({ $0.isAttachedPicture }) {
            guard imageDuration.isFinite, imageDuration > 0 else { return (nil, .unknown) }
            return (imageDuration, .imageDurationRule)
        }
        return (nil, .unknown)
```

## Excerpt ex_extract_tail

```swift id=ex_extract_tail
// Sources/GorAVFFmpegAdapter/MediaInventory.swift lines 187-190 @ 5b448b89394709decd046d5bea214ac19c05f11f
        let inv = MediaInventory(tracks: tracks, chapters: chapters, metadata: metadata,
                                 durationSeconds: duration,
                                 durationProvenance: duration == nil ? .unknown : .container)
        return inv
```

## Excerpt ex_format_name_precedent

```swift id=ex_format_name_precedent
// Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift lines 840-840 @ 5b448b89394709decd046d5bea214ac19c05f11f
                    let container = String(cString: fmtCtx.pointee.iformat.pointee.name)
```

## Excerpt ex_existing_image_tests

```swift id=ex_existing_image_tests
// Sources/media-inventory-tests/main.swift lines 43-58 @ 5b448b89394709decd046d5bea214ac19c05f11f
// I-series: image-duration rule (pure behavior on typed tracks)
func fakeTrack(pic: Bool) -> MediaInventory.Track {
    MediaInventory.Track(index: 0, kind: .video, codec: "mjpeg", language: nil, title: nil, isDefault: true, isAttachedPicture: pic, durationSeconds: nil)
}
let picInv = MediaInventory(tracks: [fakeTrack(pic: true)], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown)
check("I1 picture-only source gets the image duration", picInv.effectiveDurationSeconds().seconds == MediaInventory.defaultImageDurationSeconds && picInv.effectiveDurationSeconds().provenance == .imageDurationRule)
check("I2 image duration configurable", picInv.effectiveDurationSeconds(imageDuration: 42).seconds == 42)
let vidInv = MediaInventory(tracks: [fakeTrack(pic: false)], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown)
check("I3 non-picture source without duration stays unknown", vidInv.effectiveDurationSeconds().seconds == nil && vidInv.effectiveDurationSeconds().provenance == .unknown)
let durInv = MediaInventory(tracks: [fakeTrack(pic: true)], chapters: [], metadata: [:], durationSeconds: 3.5, durationProvenance: .container)
check("I4 container duration wins over the rule", durInv.effectiveDurationSeconds().seconds == 3.5 && durInv.effectiveDurationSeconds().provenance == .container)

// X-series: admission parity with the decoders
do {
    _ = try MediaInventory.load(path: "/etc/hostname", pinnedRoots: pins)
    check("X1 outside pinned roots refused", false, "loaded")
```

## Excerpt ex_test_tail

```swift id=ex_test_tail
// Sources/media-inventory-tests/main.swift lines 76-79 @ 5b448b89394709decd046d5bea214ac19c05f11f
check("I5 shipped image default is two seconds", MediaInventory.defaultImageDurationSeconds == 2)
check("I6 invalid image duration stays unknown", picInv.effectiveDurationSeconds(imageDuration: .nan).seconds == nil)
print(failures == 0 ? "media-inventory-tests: all pass" : "media-inventory-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
```

## Fixture fx_format_capture_tests

```swift id=fx_format_capture_tests
// Append to Sources/media-inventory-tests/main.swift before the final print/exit lines.
// Capture-only: containerFormat is informational and must NOT change any duration behavior.
let baseTrack = MediaInventory.Track(index: 0, kind: .video, codec: "png", language: nil, title: nil, isDefault: true, isAttachedPicture: false, durationSeconds: nil)
let withFmt = MediaInventory(tracks: [baseTrack], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown, containerFormat: "png_pipe")
let noFmt = MediaInventory(tracks: [baseTrack], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown)
check("C1 five-argument init still compiles and defaults containerFormat to nil", noFmt.containerFormat == nil)
check("C2 containerFormat is stored verbatim", withFmt.containerFormat == "png_pipe")
check("C3 equality includes containerFormat", withFmt != noFmt && withFmt == MediaInventory(tracks: [baseTrack], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown, containerFormat: "png_pipe"))
let ew = withFmt.effectiveDurationSeconds(), en = noFmt.effectiveDurationSeconds()
check("C4 effective duration is identical with and without containerFormat (no behavior change)", ew.seconds == en.seconds && ew.provenance == en.provenance && ew.seconds == nil && ew.provenance == .unknown)
let picWith = MediaInventory(tracks: [MediaInventory.Track(index: 0, kind: .video, codec: "mjpeg", language: nil, title: nil, isDefault: true, isAttachedPicture: true, durationSeconds: nil)], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown, containerFormat: "mp3")
check("C5 attached-picture rule unchanged when a format is recorded", picWith.effectiveDurationSeconds().provenance == .imageDurationRule && picWith.effectiveDurationSeconds().seconds == MediaInventory.defaultImageDurationSeconds)

// R-series: the real opened context records a demuxer name (informational; the value is printed, not interpreted).
for (name, mustContain) in [("still-png.png", ""), ("still-jpg.jpg", ""), ("short-png-seq.mkv", "matroska")] {
    do {
        let real = try MediaInventory.load(path: root + "/fixtures/" + name, pinnedRoots: pins)
        let f = real.containerFormat ?? ""
        check("R \(name) containerFormat captured from the real demuxer", !f.isEmpty && f.contains(mustContain), "format=\(f)")
        let e = real.effectiveDurationSeconds()
        check("R \(name) effective duration identical to the pre-change rule", real.tracks.count == 1 && (name == "short-png-seq.mkv" ? e.provenance == .container : (e.seconds == nil && e.provenance == .unknown)), "dur=\(String(describing: real.durationSeconds)) \(e)")
    } catch {
        check("R \(name) load", false, "\(error)")
    }
}
```

## Fixture fx_fixtures_shell

```sh id=fx_fixtures_shell
# Create the three fixtures (170 B, 243 B, 1530 B). Plain shell, no ffmpeg needed:
mkdir -p fixtures
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwCAIAAAAuKetIAAAACXBIWXMAAAABAAAAAQBPJcTWAAAAXElEQVR4nO3PAQkAQBCEwO3f+eBjiLxggHG3qeMFDcjjBQ3I4wUNyOMFDcjjBQ3I4wUNyOMFDcjjBQ3I4wUNyOMFDcjjBQ3I4wUNyOMFDcjjBQ3I4wUNyOMFvw88NFPcptzFom0AAAAASUVORK5CYII=' | base64 -d > fixtures/still-png.png
printf '%s' '/9j/4AAQSkZJRgABAgAAAQABAAD//gARTGF2YzU4LjEzNC4xMDAA/9sAQwAIBAQEBAQFBQUFBQUGBgYGBgYGBgYGBgYGBwcHCAgIBwcHBgYHBwgICAgJCQkICAgICQkKCgoMDAsLDg4OEREU/8QATQABAQAAAAAAAAAAAAAAAAAAAAcBAQEBAAAAAAAAAAAAAAAAAAAFBxABAAAAAAAAAAAAAAAAAAAAABEBAAAAAAAAAAAAAAAAAAAAAP/AABEIADAAQAMBIgACEQADEQD/2gAMAwEAAhEDEQA/AI4A39LAAAAAAAAAAAAAAAAAAAAAAf/Z' | base64 -d > fixtures/still-jpg.jpg
printf '%s' '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' | base64 -d > fixtures/short-png-seq.mkv
sha256sum fixtures/still-png.png fixtures/still-jpg.jpg fixtures/short-png-seq.mkv
# first 8 hex of the first two sums: 4c3a7f52 and 075e6240
# Regeneration commands the fixtures came from (ffmpeg 4.4.2 on the writer's machine):
#   ffmpeg -f lavfi -i color=c=red:s=64x48 -frames:v 1 still-png.png
#   ffmpeg -f lavfi -i color=c=blue:s=64x48 -frames:v 1 still-jpg.jpg
#   ffmpeg -f lavfi -i color=c=white:s=64x48:r=25 -frames:v 5 -c:v png short-png-seq.mkv
```

```swift id=merged_main
import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// R10 (arch-195b) witness: media inventory over real containers through the
// admitted open path; image-duration rule as pure behavior on typed tracks.

var failures = 0
func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " \(info)"))
    if !ok { failures += 1 }
}

let root = ProcessInfo.processInfo.environment["GORAV_REPO"] ?? FileManager.default.currentDirectoryPath
let pins = [URL(fileURLWithPath: root)]

// M-series: muxed mp4 inventory
do {
    let inv = try MediaInventory.load(path: root + "/fixtures/e1-h264-aac-10s.mp4", pinnedRoots: pins)
    check("M1 two tracks", inv.tracks.count == 2, "\(inv.tracks.count)")
    let v = inv.tracks.first { $0.kind == .video }
    let a = inv.tracks.first { $0.kind == .audio }
    check("M2 video track h264 default", v?.codec == "h264" && v?.isDefault == true, "\(String(describing: v))")
    check("M3 audio track aac", a?.codec == "aac", "\(String(describing: a))")
    check("M4 duration about 10s from container", inv.durationSeconds != nil && abs(inv.durationSeconds! - 10.0) < 0.5, "\(String(describing: inv.durationSeconds))")
    check("M5 duration provenance container", inv.effectiveDurationSeconds().provenance == .container)
    check("M6 no chapters is a fact", inv.chapters.isEmpty)
    check("M7 metadata map is typed (may be empty)", inv.metadata.count >= 0)
} catch {
    check("M1 load threw", false, "\(error)")
}

// A-series: audio-only wav inventory
do {
    let inv = try MediaInventory.load(path: root + "/fixtures/tone-48k.wav", pinnedRoots: pins)
    check("A1 one audio track pcm_s16le", inv.tracks.count == 1 && inv.tracks[0].kind == .audio && inv.tracks[0].codec == "pcm_s16le", "\(inv.tracks)")
    check("A2 wav has a container duration", inv.durationSeconds != nil && abs(inv.durationSeconds! - 1.0) < 0.2, "\(String(describing: inv.durationSeconds))")
    check("A3 effective duration is the container one", inv.effectiveDurationSeconds().provenance == .container)
} catch {
    check("A1 wav load threw", false, "\(error)")
}

// I-series: image-duration rule (pure behavior on typed tracks)
func fakeTrack(pic: Bool) -> MediaInventory.Track {
    MediaInventory.Track(index: 0, kind: .video, codec: "mjpeg", language: nil, title: nil, isDefault: true, isAttachedPicture: pic, durationSeconds: nil)
}
let picInv = MediaInventory(tracks: [fakeTrack(pic: true)], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown)
check("I1 picture-only source gets the image duration", picInv.effectiveDurationSeconds().seconds == MediaInventory.defaultImageDurationSeconds && picInv.effectiveDurationSeconds().provenance == .imageDurationRule)
check("I2 image duration configurable", picInv.effectiveDurationSeconds(imageDuration: 42).seconds == 42)
let vidInv = MediaInventory(tracks: [fakeTrack(pic: false)], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown)
check("I3 non-picture source without duration stays unknown", vidInv.effectiveDurationSeconds().seconds == nil && vidInv.effectiveDurationSeconds().provenance == .unknown)
let durInv = MediaInventory(tracks: [fakeTrack(pic: true)], chapters: [], metadata: [:], durationSeconds: 3.5, durationProvenance: .container)
check("I4 container duration wins over the rule", durInv.effectiveDurationSeconds().seconds == 3.5 && durInv.effectiveDurationSeconds().provenance == .container)

// X-series: admission parity with the decoders
do {
    _ = try MediaInventory.load(path: "/etc/hostname", pinnedRoots: pins)
    check("X1 outside pinned roots refused", false, "loaded")
} catch MediaInventory.LoadError.rejected(let m) {
    check("X1 outside pinned roots refused", m.contains("outside pinned roots"), m)
} catch { check("X1 outside pinned roots refused", false, "\(error)") }
do {
    _ = try MediaInventory.load(path: "ftp://example.com/x.mp4", pinnedRoots: pins)
    check("X2 non-admitted scheme refused", false, "loaded")
} catch MediaInventory.LoadError.rejected(let m) {
    check("X2 non-admitted scheme refused", m.contains("scheme not admitted"), m)
} catch { check("X2 non-admitted scheme refused", false, "\(error)") }
do {
    _ = try MediaInventory.load(path: "http://user:s3cr3t@127.0.0.1:1/x.mp4?token=abc123", pinnedRoots: pins)
    check("X3 dead endpoint throws", false, "loaded")
} catch {
    let m = "\(error)"
    check("X3 error redacts credentials", m.contains("REDACTED") && !m.contains("s3cr3t") && !m.contains("abc123"), m)
}

check("I5 shipped image default is two seconds", MediaInventory.defaultImageDurationSeconds == 2)
check("I6 invalid image duration stays unknown", picInv.effectiveDurationSeconds(imageDuration: .nan).seconds == nil)
// Append to Sources/media-inventory-tests/main.swift before the final print/exit lines.
// C-series: containerFormat capture is additive metadata; no behavior change.
let baseTrack = MediaInventory.Track(index: 0, kind: .video, codec: "mjpeg", language: nil, title: nil, isDefault: true, isAttachedPicture: false, durationSeconds: nil)
let withFmt = MediaInventory(tracks: [baseTrack], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown, containerFormat: "png_pipe")
let noFmt = MediaInventory(tracks: [baseTrack], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown)
check("C1 five-argument init still compiles and defaults containerFormat to nil", noFmt.containerFormat == nil)
check("C2 containerFormat is stored verbatim", withFmt.containerFormat == "png_pipe")
check("C3 equality includes containerFormat", withFmt != noFmt && withFmt == MediaInventory(tracks: [baseTrack], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown, containerFormat: "png_pipe"))
let ew = withFmt.effectiveDurationSeconds(), en = noFmt.effectiveDurationSeconds()
check("C4 effective duration is identical with and without containerFormat (no behavior change)", ew.seconds == en.seconds && ew.provenance == en.provenance && ew.seconds == nil && en.provenance == .unknown)
let picWith = MediaInventory(tracks: [MediaInventory.Track(index: 0, kind: .video, codec: "mjpeg", language: nil, title: nil, isDefault: true, isAttachedPicture: true, durationSeconds: nil)], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown, containerFormat: "mp3")
check("C5 attached-picture rule unchanged when a format is recorded", picWith.effectiveDurationSeconds().provenance == .imageDurationRule && picWith.effectiveDurationSeconds().seconds == MediaInventory.defaultImageDurationSeconds)

// R-series: the real opened context records a demuxer name (informational; the
// value is printed, not interpreted). Fixtures use demuxers the pinned
// provider actually builds (mov, matroska); the pinned 7.1 static provider
// has no image2/png_pipe or mjpeg demuxer, so still-image rows are not
// asserted here (env-typed note, not a forced pass).
for (name, mustContain) in [("e1-h264-aac-10s.mp4", "mov"), ("active-inventory-chapters.mkv", "matroska")] {
    do {
        let real = try MediaInventory.load(path: root + "/fixtures/" + name, pinnedRoots: pins)
        let f = real.containerFormat ?? ""
        check("R \(name) containerFormat captured from the real demuxer", !f.isEmpty && f.contains(mustContain), "format=\(f)")
        let e = real.effectiveDurationSeconds()
        check("R \(name) effective duration identical to the pre-change rule", e.provenance == .container, "dur=\(String(describing: real.durationSeconds)) \(e)")
    } catch {
        check("R \(name) load", false, "\(error)")
    }
}


print(failures == 0 ? "media-inventory-tests: all pass" : "media-inventory-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)

```

```swift id=fx_containerformat_patch
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
        case unknown
    }

    public let tracks: [Track]
    public let chapters: [Chapter]
    /// Format-level tags, untrusted container text. Do not treat as log-safe.
    public let metadata: [String: String]
    public let durationSeconds: Double?
    public let durationProvenance: DurationProvenance
    /// Demuxer name captured from the opened context (e.g. "png_pipe",
    /// "matroska,webm"). Informational only; never changes behavior.
    public let containerFormat: String?

    public init(tracks: [Track], chapters: [Chapter], metadata: [String: String], durationSeconds: Double?, durationProvenance: DurationProvenance, containerFormat: String? = nil) {
        self.tracks = tracks
        self.chapters = chapters
        self.metadata = metadata
        self.durationSeconds = durationSeconds
        self.durationProvenance = durationProvenance
        self.containerFormat = containerFormat
    }

    /// mpv semantics: an image (attached picture or image codec) plays as a
    /// still for a configured duration instead of ending instantly.
    public static let defaultImageDurationSeconds = 2.0

    /// Effective playback duration: the container duration when known; for a
    /// picture-only source with no container duration, the image-duration rule.
    public func effectiveDurationSeconds(imageDuration: Double = MediaInventory.defaultImageDurationSeconds) -> (seconds: Double?, provenance: DurationProvenance) {
        if let d = durationSeconds, d.isFinite, d >= 0 { return (d, durationProvenance) }
        let playable = tracks.filter { $0.kind == .video || $0.kind == .audio }
        if !playable.isEmpty, playable.allSatisfy({ $0.isAttachedPicture }) {
            guard imageDuration.isFinite, imageDuration > 0 else { return (nil, .unknown) }
            return (imageDuration, .imageDurationRule)
        }
        return (nil, .unknown)
    }

    public enum LoadError: Error, Equatable {
        case rejected(String)
        case failed(Int32, String)
    }

    /// Loads the inventory of a local or admitted remote source. Admission
    /// mirrors the decoders: local paths must sit under pinnedRoots; remote
    /// ids pass the scheme allowlist and open with the given transport options.
    public static func load(path: String, pinnedRoots: [URL], options: SourceOpenOptions = SourceOpenOptions()) throws -> MediaInventory {
        let openPath: String
        if AdmissionTable.remoteScheme(of: path) != nil {
            guard AdmissionTable.isAdmittedRemoteURL(path) else {
                throw LoadError.rejected("scheme not admitted: \(AdmissionTable.remoteScheme(of: path) ?? "(none)")")
            }
            openPath = path
        } else {
            guard path.hasPrefix("/"), !path.contains("://") else {
                throw LoadError.rejected("absolute local path only")
            }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            guard pinnedRoots.contains(where: { resolved.path == $0.path || resolved.path.hasPrefix($0.path + "/") }) else {
                throw LoadError.rejected("outside pinned roots")
            }
            openPath = resolved.path
        }
        var f: UnsafeMutablePointer<AVFormatContext>?
        let rc: Int32
        if openPath.contains("://") {
            rc = goravR3OpenInput(&f, url: openPath, options: options)
        } else {
            rc = avformat_open_input(&f, openPath, nil, nil)
        }
        guard rc >= 0, let fc = f else {
            throw LoadError.failed(rc, "avformat_open_input failed for \(openPath.contains("://") ? URLRedaction.redact(openPath) : "local")")
        }
        defer { avformat_close_input(&f) }
        let infoRC = avformat_find_stream_info(fc, nil)
        guard infoRC >= 0 else { throw LoadError.failed(infoRC, "stream info failed") }

        return extract(fromOpenedContext: fc)
    }

    /// Uses only the caller's ALREADY OPEN context. Caller must own its native
    /// queue for this entire synchronous copy. No I/O, seek, stream-info probe,
    /// pointer escape or second open. Values survive context teardown safely.
    static func extract(fromOpenedContext fc: UnsafeMutablePointer<AVFormatContext>) -> MediaInventory {
        func str(_ p: UnsafePointer<CChar>?) -> String? { p.map { String(cString: $0) } }
        var tracks: [Track] = []
        let defFlag = gorav_r10_disposition_default()
        let picFlag = gorav_r10_disposition_attached_pic()
        for i32 in 0..<gorav_r10_stream_count(fc) {
            let i = Int(i32)
            let kind: TrackKind = switch gorav_r10_stream_kind(fc, i32) {
            case 0: .video
            case 1: .audio
            case 3: .subtitle
            case 2: .data
            default: .other
            }
            var num: Int32 = 0, den: Int32 = 0
            gorav_r10_stream_timebase(fc, i32, &num, &den)
            let durTs = gorav_r10_stream_duration_ts(fc, i32)
            var dur: Double? = nil
            if durTs != gorav_av_nopts_value(), num > 0, den > 0 {
                let d = Double(durTs) * Double(num) / Double(den)
                if d.isFinite, d >= 0 { dur = d }
            }
            let disp = gorav_r10_stream_disposition(fc, i32)
            tracks.append(Track(
                index: i, kind: kind,
                codec: str(gorav_r10_stream_codec_name(fc, i32)) ?? "unknown",
                language: str(gorav_r10_stream_meta(fc, i32, "language")),
                title: str(gorav_r10_stream_meta(fc, i32, "title")),
                isDefault: (disp & defFlag) != 0,
                isAttachedPicture: (disp & picFlag) != 0,
                durationSeconds: dur))
        }
        var chapters: [Chapter] = []
        for i32 in 0..<gorav_r10_chapter_count(fc) {
            let i = Int(i32)
            var start: Int64 = 0, end: Int64 = 0, num: Int32 = 0, den: Int32 = 1
            gorav_r10_chapter_times(fc, i32, &start, &end, &num, &den)
            guard num > 0, den > 0 else { continue }
            let scale = Double(num) / Double(den)
            chapters.append(Chapter(index: i, title: str(gorav_r10_chapter_title(fc, i32)),
                                    startSeconds: Double(start) * scale, endSeconds: Double(end) * scale))
        }
        var metadata: [String: String] = [:]
        for key in ["title", "artist", "album", "encoder", "comment", "date"] {
            if let v = str(gorav_r10_format_meta(fc, key)) { metadata[key] = v }
        }
        var duration: Double? = nil
        let durUs = gorav_r10_duration_us(fc)
        if durUs != gorav_av_nopts_value(), durUs > 0 { duration = Double(durUs) / 1_000_000 }
        let containerFormat = fc.pointee.iformat != nil ? String(cString: fc.pointee.iformat.pointee.name) : nil
        let inv = MediaInventory(tracks: tracks, chapters: chapters, metadata: metadata,
                                 durationSeconds: duration,
                                 durationProvenance: duration == nil ? .unknown : .container,
                                 containerFormat: containerFormat)
        return inv
    }
}

/// Identity-fenced value copy of the active context, separate from the decoder
/// metadata registry. Values are untrusted container text, never log-safe.
public struct ActiveMediaInventoryIdentity: Equatable, Sendable {
    public let sourceID: String
    public let session: UInt64
    public let revision: UInt64
    /// Video delivery generation fences legacy seek/hardware fallback too.
    public let presentationEpoch: UInt64
    public init(sourceID:String,session:UInt64,revision:UInt64,presentationEpoch:UInt64 = 0) {
        self.sourceID=sourceID; self.session=session; self.revision=revision
        self.presentationEpoch=presentationEpoch
    }
}
public struct ActiveMediaInventorySnapshot: Equatable, Sendable {
    public let identity: ActiveMediaInventoryIdentity
    public let inventory: MediaInventory
}

```
