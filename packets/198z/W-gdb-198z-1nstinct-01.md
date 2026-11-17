# W-gdb-198z-1nstinct-01 - Audio inventory/control receipt
state: OPEN / unclaimed
lab: 1nstinct

Stable stream ID, language/title/default/current, explicit unavailable state and source-generation identity. Close the inventory/ID mapping gap without replacing existing setAudioTrack APIs.

Required acceptance: Sources/active-media-inventory-tests/main.swift and Sources/media-inventory-tests/main.swift: multiaudio, switch, no-audio, stale generation. Coordinate test edits with labB01/03; do not overwrite its path-only diffs.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-1nstinct-01",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/GorAVPlaybackCore/AudioTrackPlan.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "Audio inventory/control receipt; Stable stream ID, language/title/default/current, explicit unavailable state and source-generation identity. Close the inventory/ID mapping gap without replacing existing setAudioTrack APIs.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Sources/active-media-inventory-tests/main.swift and Sources/media-inventory-tests/main.swift: multiaudio, switch, no-audio, stale generation. Coordinate test edits with labB01/03; do not overwrite its path-only diffs.",
    "callee": "Sources/GorAVFFmpegAdapter/MediaInventory.swift, Sources/GorAVPlaybackCore/AudioTrackPlan.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-01.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Sources/active-media-inventory-tests/main.swift and Sources/media-inventory-tests/main.swift: multiaudio, switch, no-audio, stale generation. Coordinate test edits with labB01/03; do not overwrite its path-only diffs.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-198z-1nstinct-01",
    "paths": [
      "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
      "Sources/GorAVPlaybackCore/AudioTrackPlan.swift",
      "Tests/Architecture/198z/W-gdb-198z-1nstinct-01.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-01.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.322891+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
        "block": "source1",
        "sha256": "bbc464766d8f2137ed023f2bee9de0a1a88cc148f828502a1e575733fe71fec2"
      },
      {
        "path": "Sources/GorAVPlaybackCore/AudioTrackPlan.swift",
        "block": "source2",
        "sha256": "24d8e9f53b044811f39268299767fad5a2bf788982133439138f5269c5678c31"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-1nstinct-01.py",
        "block": "fixtures1",
        "sha256": "a341c5df9b286e1581fdd8cc9f4ade6d7e32c61f89c1d1e17399078ac8d5add5"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "4d5bff5154469f55c1b99dbb03c893a72ffced06e61177634a0be7d076d5a855",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-01; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "dff6f5d3d59e0cb1841c56978f637db3c813b14f3a4634b3af2a26328a583763"
  }
}
```

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

```swift id=source2
import Foundation

// R6 (arch-195l, dispatch L6): audio track selection policy + audio delay
// value semantics. Pure Swift, Linux-verifiable; the Mac wiring
// (FFmpegSoftwareAudioDecoder preferred stream, session commands) consumes
// these types. Selection is typed and loud: an explicit request that the
// container cannot honor is a typed refusal, never a silent fallback.

/// One audio track as the control layer needs it (mirrors the audio rows of
/// MediaInventory.Track without importing the FFmpeg adapter).
public struct AudioTrackInfo: Equatable, Sendable {
    /// Container stream index (avformat stream index, not an ordinal).
    public let index: Int
    public let language: String?
    public let title: String?
    public let isDefault: Bool
    public init?(index: Int, language: String?, title: String?, isDefault: Bool) {
        guard index >= 0 else { return nil }
        self.index = index; self.language = language
        self.title = title; self.isDefault = isDefault
    }
}

public enum AudioTrackSelector: Equatable, Sendable {
    /// Container default flag first, else the lowest stream index.
    case auto
    /// Exact container stream index.
    case index(Int)
    /// Exact language tag, case-insensitive (e.g. "eng", "tur").
    case language(String)
}

public enum AudioTrackRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    case noAudioTracks
    case requestedIndexAbsent(Int)
    case requestedLanguageAbsent(String)
    public var description: String {
        switch self {
        case .noAudioTracks: return "noAudioTracks"
        case .requestedIndexAbsent(let i): return "requestedIndexAbsent(\(i))"
        case .requestedLanguageAbsent(let l): return "requestedLanguageAbsent(\(l))"
        }
    }
}

public enum AudioTrackPlan {
    public static func select(_ selector: AudioTrackSelector, from tracks: [AudioTrackInfo])
        -> Result<AudioTrackInfo, AudioTrackRefusal> {
        guard !tracks.isEmpty else { return .failure(.noAudioTracks) }
        switch selector {
        case .auto:
            if let d = tracks.first(where: { $0.isDefault }) { return .success(d) }
            return .success(tracks.min(by: { $0.index < $1.index })!)
        case .index(let i):
            guard i >= 0, let t = tracks.first(where: { $0.index == i }) else {
                return .failure(.requestedIndexAbsent(i))
            }
            return .success(t)
        case .language(let lang):
            let wanted = lang.lowercased()
            guard let t = tracks.first(where: { $0.language?.lowercased() == wanted }) else {
                return .failure(.requestedLanguageAbsent(lang))
            }
            return .success(t)
        }
    }
}

/// User audio delay, mpv audio-delay convention: POSITIVE delays the audio
/// relative to the video. Setting REPLACES the value; it never accumulates.
public struct AudioDelay: Equatable, Sendable {
    public static let limitSeconds = 600.0
    public let seconds: Double
    public init?(_ seconds: Double) {
        guard seconds.isFinite, abs(seconds) <= AudioDelay.limitSeconds else { return nil }
        self.seconds = seconds
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/GorAVFFmpegAdapter/MediaInventory.swift').read_bytes()).hexdigest()=='bbc464766d8f2137ed023f2bee9de0a1a88cc148f828502a1e575733fe71fec2'
assert hashlib.sha256((ROOT/'Sources/GorAVPlaybackCore/AudioTrackPlan.swift').read_bytes()).hexdigest()=='24d8e9f53b044811f39268299767fad5a2bf788982133439138f5269c5678c31'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-01; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-01; baseline only, product change and semantic test still required
```

secret scan: clean
