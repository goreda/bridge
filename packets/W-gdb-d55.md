# W-gdb-d55: 195b-55/61 follow-on: normalized chapter list from the cached MediaInventory

MediaInventory.extract copies chapters straight from the container: no ordering guarantee, no check of end >= start, no clamp to the container duration. Add a pure `MediaInventory.normalizedChapters()` that consumers (seek-by-chapter, chapter list UI) can rely on, leaving the raw `chapters` array untouched. Pure Swift on typed values, no FFmpeg, no I/O.

Not in scope: changing extract(), the ActiveMediaInventory identity types, native forwarding, chapter UI. Excerpts are verbatim lines from the pinned product sha; the first comment line of each block is a label added by the packet writer and is not part of the excerpt hash. Fixture blocks are new text proposed by this packet.

```packet-json
{
 "packet": "W-gdb-d55",
 "code_owner": "gdb gorav integrator (decoder lane), owner of Sources/GorAVPlaybackCore and Sources/GorAVFFmpegAdapter on gorav/engine",
 "scope": "implementation",
 "product_repo": "goreda/gorav",
 "product_branch": "engine",
 "product_sha": "8eaffc75b331a9d65ddce404266738a9d42043ed",
 "touched_files": [
  {
   "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
   "excerpt_block": "ex_chapter_type",
   "lines": "38-52"
  },
  {
   "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
   "excerpt_block": "ex_chapter_extract",
   "lines": "170-179"
  },
  {
   "path": "Sources/media-inventory-tests/main.swift",
   "excerpt_block": "ex_test_head",
   "lines": "1-16"
  },
  {
   "path": "Sources/media-inventory-tests/main.swift",
   "excerpt_block": "ex_test_image_series",
   "lines": "43-58"
  }
 ],
 "excerpt_sha256_8": {
  "ex_chapter_type": "240ea34c",
  "ex_chapter_extract": "92b581c6",
  "ex_test_head": "fd9a5095",
  "ex_test_image_series": "99661792"
 },
 "interface": {
  "signatures": "extension MediaInventory { public func normalizedChapters() -> [Chapter] }",
  "types": "MediaInventory.Chapter(index: Int, title: String?, startSeconds: Double, endSeconds: Double), unchanged. Return value is a new array; self is not mutated.",
  "ownership_lifetime": "Pure function on an immutable Sendable struct; no state, no lock, no escape of pointers.",
  "caller": "Future chapter consumers on any thread; the existing extract(fromOpenedContext:) and ActiveMediaInventorySnapshot are not changed.",
  "callee": "Foundation only. Rules: drop a chapter when start or end is non-finite, start < 0, or end < start; when durationSeconds is finite and >= 0, drop chapters with start >= duration and clamp end to duration; keep zero-length chapters whose start < duration; sort by startSeconds ascending, ties by index ascending; keep original index and title."
 },
 "test": {
  "command": "swift run media-inventory-tests",
  "expected": "Exit 0. Output contains PASS N1 through PASS N9 and ends with the line \"media-inventory-tests: all pass\". The M, A, I, X series PASS lines are unchanged (the M and A series need the repo fixtures e1-h264-aac-10s.mp4 and tone-48k.wav).",
  "fixture_block": "fx_chapter_tests",
  "note": "Run by the integrator on Linux with the pinned provider; a lab without the repo returns the patch and states \"unrun\"."
 },
 "target": {
  "branch": "lane/gdb-196p-decoder (integrator creates it from product_sha; never ohal/gorav main or PR 3)",
  "paths": [
   "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
   "Sources/media-inventory-tests/main.swift"
  ],
  "return_form": "patch"
 }
}
```

## Excerpt ex_chapter_type

```swift id=ex_chapter_type
// Sources/GorAVFFmpegAdapter/MediaInventory.swift lines 38-52 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
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
```

## Excerpt ex_chapter_extract

```swift id=ex_chapter_extract
// Sources/GorAVFFmpegAdapter/MediaInventory.swift lines 170-179 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
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
```

## Excerpt ex_test_head

```swift id=ex_test_head
// Sources/media-inventory-tests/main.swift lines 1-16 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
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

```

## Excerpt ex_test_image_series

```swift id=ex_test_image_series
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

## Fixture fx_chapter_tests

```swift id=fx_chapter_tests
// Append to Sources/media-inventory-tests/main.swift before the final print/exit lines.
func ch(_ i: Int, _ s: Double, _ e: Double, _ t: String? = nil) -> MediaInventory.Chapter {
    MediaInventory.Chapter(index: i, title: t, startSeconds: s, endSeconds: e)
}
func inv(_ chapters: [MediaInventory.Chapter], duration: Double?) -> MediaInventory {
    MediaInventory(tracks: [], chapters: chapters, metadata: [:], durationSeconds: duration,
                   durationProvenance: duration == nil ? .unknown : .container)
}
let n1 = inv([ch(0, 30, 60), ch(1, 0, 30), ch(2, 60, 90)], duration: 90).normalizedChapters()
check("N1 sorted by start, original indexes kept", n1.map { $0.index } == [1, 0, 2])
let n2 = inv([ch(0, 0, 10), ch(1, 10, 5), ch(2, .nan, 20), ch(3, 20, .infinity)], duration: 90).normalizedChapters()
check("N2 end<start and non-finite entries dropped", n2.map { $0.index } == [0])
let n3 = inv([ch(0, 0, 100), ch(1, 95, 120)], duration: 90).normalizedChapters()
check("N3 end clamped to duration, start>=duration dropped", n3.count == 1 && n3[0].endSeconds == 90 && n3[0].index == 0)
let n4 = inv([ch(0, 0, 100), ch(1, 95, 120)], duration: nil).normalizedChapters()
check("N4 unknown duration: no clamp, nothing dropped for range", n4.count == 2 && n4[1].endSeconds == 120)
let n5 = inv([ch(3, 10, 20, "b"), ch(1, 10, 25, "a")], duration: 90).normalizedChapters()
check("N5 equal starts ordered by original index", n5.map { $0.index } == [1, 3])
let n6 = inv([ch(0, -5, 10)], duration: 90).normalizedChapters()
check("N6 negative start dropped", n6.isEmpty)
let n7 = inv([ch(0, 0, 0)], duration: 90).normalizedChapters()
check("N7 zero-length chapter kept (container may mark a point)", n7.count == 1)
check("N8 titles pass through untouched", n5.map { $0.title } == ["a", "b"])
check("N9 raw chapters property unchanged by normalization", inv([ch(1, 5, 1)], duration: 9).chapters.count == 1)
```
