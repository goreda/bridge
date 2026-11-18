# W-gdb-198z-1nstinct-01-fix - Reject ambiguous audio identity tuples

state: OPEN / unclaimed

Replace delimiter-only tuple serialization in stableStreamID with an explicit unambiguous encoding, including nil versus empty optional fields. Preserve public callers. Add actual Swift collision regressions for codec/language/title containing pipes, empty strings, nil and Unicode. IDs must remain deterministic across processes for unchanged tuples; do not claim cryptographic collision resistance. Existing FNV hash may remain if framing is unambiguous.

Boundary: Audio inventory ID only; no decoder switching or host edits.

Earliest verified claim; 2h progress lease. Work only on listed source and own tests. Isolated branch only, no product-main/delivery refs. Acceptance requires actual module Swift test and full provider package build; source models and excerpts do not establish integration. This fix packet is not counted in startable stock until its executable starter is supplied.

```packet-json
{
  "packet_id": "W-gdb-198z-1nstinct-01-fix",
  "lab": "1nstinct",
  "product_repo": "goreda/gorav",
  "product_sha": "2cdc620c77d2822c5ded1b4ada1f5b0c7c60b3ed",
  "paths": [
    "Sources/GorAVFFmpegAdapter/MediaInventory.swift"
  ],
  "test_paths": [
    "Tests/Architecture/198z/W-gdb-198z-1nstinct-01-fix.swift"
  ],
  "state": "OPEN",
  "lease_hours": 2,
  "scope": "product-fix",
  "evidence": "lane-b report85e0507605cafa84a473f69dfcaf39f4ffbda27899edc710b9d844a6a76c4c53",
  "stock_status": "NOT_COUNTED until executable exact-source starter and reviewed test binding are supplied"
}
```

## Sources/GorAVFFmpegAdapter/MediaInventory.swift sha256 0dcc9f13ee805361ca3de292ddd36cab2bc0163d4cbdf8a8c0cb2717a5feee35
```swift
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
        /// Stable per-source stream identifier (see stableStreamID). Control layers reference this ID instead of a bare container index, closing the inventory/ID mapping gap.
        public let streamID: String

        public init(index: Int, kind: TrackKind, codec: String, language: String?, title: String?, isDefault: Bool, isAttachedPicture: Bool, durationSeconds: Double?, streamID: String? = nil) {
            self.index = index
            self.kind = kind
            self.codec = codec
            self.language = language
            self.title = title
            self.isDefault = isDefault
            self.isAttachedPicture = isAttachedPicture
            self.durationSeconds = durationSeconds
            self.streamID = streamID ?? MediaInventory.stableStreamID(kind: kind, index: index, codec: codec, language: language, title: title)
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
    /// Stable per-source stream identifier: deterministic FNV-1a over the container-reported identity tuple (kind, stream index, codec, language, title). Stable across reloads of the same source; changes when container identity changes.
    public static func stableStreamID(kind: TrackKind, index: Int, codec: String, language: String?, title: String?) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in ("\(kind.rawValue)|\(index)|\(codec)|\(language ?? "")|\(title ?? "")").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(format: "%016llx", hash)
    }

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
        let inv = MediaInventory(tracks: tracks, chapters: chapters, metadata: metadata,
                                 durationSeconds: duration,
                                 durationProvenance: duration == nil ? .unknown : .container)
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

Executable RED starter published at packets/198z/fix-starters/W-gdb-198z-1nstinct-01-fix/run.py. From bridge root: python3 packets/198z/fix-starters/W-gdb-198z-1nstinct-01-fix/run.py. PRODUCT_ROOT points at your modified exact-pin product checkout. Starter kind exact-source-isolated; provider/full integration gate remains NOT_RUN. Preserve legacy APIs; new generation API needs new acceptance tests.
