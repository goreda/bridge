# W-gdb-d61: 195b-61 follow-on: record the container format name in MediaInventory (capture only, rev 4)

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
 "product_sha": "8eaffc75b331a9d65ddce404266738a9d42043ed",
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
   "lines": "795-795"
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
  "expected": "Exit 0. PASS I1..I6 unchanged, PASS C1 through C5, six R lines for three fixtures (containerFormat captured for still-png.png, still-jpg.jpg and short-png-seq.mkv, the last containing \"matroska\"; effective duration identical to the pre-change rule: nil result for the two stills, container provenance for the mkv), ends with \"media-inventory-tests: all pass\". The M and A series need the repo fixtures e1-h264-aac-10s.mp4 and tone-48k.wav.",
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
 }
}
```

## Excerpt ex_inventory_fields_init

```swift id=ex_inventory_fields_init
// Sources/GorAVFFmpegAdapter/MediaInventory.swift lines 62-78 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
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
// Sources/GorAVFFmpegAdapter/MediaInventory.swift lines 79-90 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
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
// Sources/GorAVFFmpegAdapter/MediaInventory.swift lines 187-190 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
        let inv = MediaInventory(tracks: tracks, chapters: chapters, metadata: metadata,
                                 durationSeconds: duration,
                                 durationProvenance: duration == nil ? .unknown : .container)
        return inv
```

## Excerpt ex_format_name_precedent

```swift id=ex_format_name_precedent
// Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift lines 795-795 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
                    let container = String(cString: fmtCtx.pointee.iformat.pointee.name)
```

## Excerpt ex_existing_image_tests

```swift id=ex_existing_image_tests
// Sources/media-inventory-tests/main.swift lines 43-58 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
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
// Sources/media-inventory-tests/main.swift lines 76-79 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
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
