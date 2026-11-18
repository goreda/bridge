# W-gdb-198z-1nstinct-02-fix - Make sidecar identity serialization explicit

state: OPEN / unclaimed

Replace String(describing: cue) with documented deterministic field encoding of cue index, exact timing representation and text. Include unambiguous length or type framing. Preserve format identity, reload/move stability and content sensitivity. Add actual Swift exact-vector tests that do not compute their oracle using String(describing:) or the production serializer. Test delimiters, multiline/Unicode text, timing edits and distinct cue lists.

Boundary: Stable serialization only; embedded codec classification is not decoder support.

Earliest verified claim; 2h progress lease. Work only on listed source and own tests. Isolated branch only, no product-main/delivery refs. Acceptance requires actual module Swift test and full provider package build; source models and excerpts do not establish integration. This fix packet is not counted in startable stock until its executable starter is supplied.

```packet-json
{
  "packet_id": "W-gdb-198z-1nstinct-02-fix",
  "lab": "1nstinct",
  "product_repo": "goreda/gorav",
  "product_sha": "4c70ecfc3b03de936723a6cc65700458136690e0",
  "paths": [
    "Sources/GorAVSubtitles/SubtitleTrack.swift"
  ],
  "test_paths": [
    "Tests/Architecture/198z/W-gdb-198z-1nstinct-02-fix.swift"
  ],
  "state": "OPEN",
  "lease_hours": 2,
  "scope": "product-fix",
  "evidence": "lane-b report85e0507605cafa84a473f69dfcaf39f4ffbda27899edc710b9d844a6a76c4c53",
  "stock_status": "NOT_COUNTED until executable exact-source starter and reviewed test binding are supplied"
}
```

## Sources/GorAVSubtitles/SubtitleTrack.swift sha256 ce40f8a2a0276b340224dd5bebacd286b72778795d7aed2ef8c4fe27a0cba554
```swift
import Foundation

/// Sidecar subtitle track loader (lanes L5/L6, unit u2): picks the parser by
/// file extension (.srt, .ass, .ssa) and returns cues plus the optional ASS
/// style table. Unknown extensions and unreadable files are typed refusals,
/// never silent fallbacks. Pure loader; no playback or rendering here.
public enum SubtitleTrack {

    public enum LoadError: Error, Equatable {
        case unknownFormat(path: String)
        case unreadable(path: String)
    }

    public struct Track: Equatable, Sendable {
        public let format: String // "srt" or "ass" (.ssa normalizes to "ass")
        public let cues: [SubtitleCue]
        public let styles: [ASSParser.Style]
        /// ASS override blocks detected during load: UNSUPPORTED rendering
        /// instructions, reported, never silently stripped. Empty for SRT.
        public let unsupportedOverrides: [ASSParser.OverrideReport]
        /// ASS Style rows that failed parsing during load: caller-visible at
        /// the loader entry point too, never dropped between parser and
        /// consumer. Empty for SRT.
        public let skippedStyles: [ASSParser.SkippedStyle]
        /// ASS PlayRes layout reference frame; nil for SRT or when absent.
        public let playResX: Int?
        public let playResY: Int?
        /// Stable local-sidecar identifier: FNV-1a over format plus every cue's
        /// timing and text. Stable across reloads of the same file content.
        public let sidecarID: String

        public init(format: String, cues: [SubtitleCue], styles: [ASSParser.Style],
                    unsupportedOverrides: [ASSParser.OverrideReport],
                    skippedStyles: [ASSParser.SkippedStyle], playResX: Int?, playResY: Int?,
                    sidecarID: String? = nil) {
            self.format = format
            self.cues = cues
            self.styles = styles
            self.unsupportedOverrides = unsupportedOverrides
            self.skippedStyles = skippedStyles
            self.playResX = playResX
            self.playResY = playResY
            self.sidecarID = sidecarID ?? SubtitleTrack.stableSidecarID(format: format, cues: cues)
        }
    }

    /// Stable local-sidecar identifier: FNV-1a over the format and the full cue
    /// list (index, start/end milliseconds, text). Content-addressed, so a file
    /// move keeps the ID and a content edit changes it.
    public static func stableSidecarID(format: String, cues: [SubtitleCue]) -> String {
        var hash: UInt64 = 14695981039346656037
        func mix(_ text: String) { for byte in text.utf8 { hash ^= UInt64(byte); hash = hash &* 1099511628211 } }
        mix(format)
        for cue in cues {
            // cue.index is a proven field; String(describing:) covers the full
            // cue value without depending on unexposed timing field names.
            mix("\(cue.index)|")
            mix(String(describing: cue))
        }
        return String(format: "%016llx", hash)
    }

    /// Embedded-subtitle support, distinct from sidecar loading: text-based
    /// embedded codecs are supported; image-based ones are a named refusal.
    public enum EmbeddedSupport: Equatable, Sendable {
        case supported
        case unsupported(codec: String)
    }

    /// Classifies an embedded subtitle codec. Distinguishes unsupported embedded
    /// subtitles (PGS/DVB/DVB teletext-style image codecs) from text ones.
    public static func embeddedSupport(codec: String) -> EmbeddedSupport {
        switch codec.lowercased() {
        case "subrip", "mov_text", "webvtt", "ass", "ssa", "srt", "text", "subviewer", "microdvd":
            return .supported
        default:
            return .unsupported(codec: codec)
        }
    }

    public static func load(path: String) throws -> Track {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ext == "srt" || ext == "ass" || ext == "ssa" else { throw LoadError.unknownFormat(path: path) }
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            throw LoadError.unreadable(path: path)
        }
        if ext == "srt" {
            return Track(format: "srt", cues: try SRTParser.parse(text), styles: [],
                         unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
        }
        let doc = try ASSParser.parse(text)
        return Track(format: "ass", cues: doc.cues, styles: doc.styles,
                     unsupportedOverrides: doc.unsupportedOverrides, skippedStyles: doc.skippedStyles,
                     playResX: doc.playResX, playResY: doc.playResY)
    }
}

```
