# W-gdb-198z-1nstinct-02 - Subtitle inventory/selection
state: OPEN / unclaimed
lab: 1nstinct

Stable local-sidecar IDs; distinguish unsupported embedded subtitles. Primary, secondary and off with generation receipt.

Required acceptance: Sources/subtitle-tests/SubtitleTrackTests.swift plus real sidecar select/seek/replace fixture.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-1nstinct-02",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/SubtitleTrack.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/GorAVSubtitles/SubtitleSidecarSession.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "Subtitle inventory/selection; Stable local-sidecar IDs; distinguish unsupported embedded subtitles. Primary, secondary and off with generation receipt.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Sources/subtitle-tests/SubtitleTrackTests.swift plus real sidecar select/seek/replace fixture.",
    "callee": "Sources/GorAVSubtitles/SubtitleTrack.swift, Sources/GorAVSubtitles/SubtitleSidecarSession.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-02.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Sources/subtitle-tests/SubtitleTrackTests.swift plus real sidecar select/seek/replace fixture.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-198z-1nstinct-02",
    "paths": [
      "Sources/GorAVSubtitles/SubtitleTrack.swift",
      "Sources/GorAVSubtitles/SubtitleSidecarSession.swift",
      "Tests/Architecture/198z/W-gdb-198z-1nstinct-02.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-02.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.346067+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/SubtitleTrack.swift",
        "block": "source1",
        "sha256": "d0e635a1ec87e20d75cfdb59dd75fb4f9aec24f7c54a2f88f84dab154518b969"
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleSidecarSession.swift",
        "block": "source2",
        "sha256": "f39eadb0dddd92f330f20bdc55fdd9da0a7a5a1223225817edad5581fcc858f7"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-1nstinct-02.py",
        "block": "fixtures1",
        "sha256": "3a2ff6d95065f481c448adafd623d933f7a4835edea9544c0cc9be2e4adbb66f"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "23fe91051da65c02481ddfea9126f2d5c6189739980eda3bfc58facab91bf6fe",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-02; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "bb8090e9599ee46773ebcc9a21ad0c4c58ebd082ad7db42de0fad9a9c3bf26b8"
  }
}
```

```swift id=source1
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

        public init(format: String, cues: [SubtitleCue], styles: [ASSParser.Style],
                    unsupportedOverrides: [ASSParser.OverrideReport],
                    skippedStyles: [ASSParser.SkippedStyle], playResX: Int?, playResY: Int?) {
            self.format = format
            self.cues = cues
            self.styles = styles
            self.unsupportedOverrides = unsupportedOverrides
            self.skippedStyles = skippedStyles
            self.playResX = playResX
            self.playResY = playResY
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

```swift id=source2
import Foundation

public enum SubtitleSidecarRefusal: Error, Equatable, Sendable {
    case closed, unsupportedSource, sourceUnavailable, notDiscovered, unsupportedASS
    case unreadable, malformed, staleCompletion, invalidDelay
}
public enum SubtitleSidecarSelection: Equatable, Sendable {
    case selected(path: String, slot: SubtitleController.Slot)
    case noExactSidecar
    case refused(SubtitleSidecarRefusal)
}

/// The actual portable selection/clock producer owner. No remote discovery,
/// network I/O, language ranking or guessed tagged default. The host delivers
/// emit synchronously to its render consumer. All completions recheck source
/// revision and per-slot request ticket before changing selection or cues.
@MainActor
public final class SubtitleSidecarSession {
    public typealias Loader = @Sendable (String) async throws -> SubtitleTrack.Track
    public let session: UInt64
    public private(set) var sourcePath: String?
    public private(set) var candidates: [SubtitleAutoLoad.Candidate] = []
    public private(set) var controller = SubtitleController()
    public var generation: UInt64 { producer.generation }
    private var producer: SubtitleCueProducer
    private var sourceRevision: UInt64 = 0
    private var primaryTicket: UInt64 = 0
    private var secondaryTicket: UInt64 = 0
    private var closed = false
    private var filmTime: Double?
    private let emit: (SubtitleCueBatch) -> Void
    private let loader: Loader

    public init(session: UInt64, emit: @escaping (SubtitleCueBatch) -> Void,
                loader: @escaping Loader = { path in
                    try await Task.detached(priority: .utility) { try SubtitleTrack.load(path: path) }.value
                }) {
        self.session = session; self.emit = emit; self.loader = loader
        producer = SubtitleCueProducer(session: session)
    }
    /// Always clears the previous source before admission, including a refused
    /// remote replacement. A missing video is distinct from a valid source with
    /// no sidecars. Source paths and candidate paths are canonical local paths.
    @discardableResult
    public func replaceSource(path: String) -> SubtitleSidecarRefusal? {
        guard !closed else { return .closed }
        invalidateLoads(); clearGeneration(); controller = SubtitleController()
        filmTime = nil; sourcePath = nil; candidates = []
        guard path.hasPrefix("/"), !path.contains("://") else { return .unsupportedSource }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue else { return .sourceUnavailable }
        sourcePath = url.path
        let parent = url.deletingLastPathComponent().path
        candidates = SubtitleAutoLoad.discover(forVideoPath: url.path).filter { candidate in
            let canonical = URL(fileURLWithPath: candidate.path).standardizedFileURL.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            return canonical.deletingLastPathComponent().path == parent
                && FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }.map { SubtitleAutoLoad.Candidate(path: URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path,
                                          tag: $0.tag, format: $0.format) }
        return nil
    }
    /// Exact SRT only. Tagged files are never selected without an explicit choice.
    public func loadExactPrimary() async -> SubtitleSidecarSelection {
        guard !closed else { return .refused(.closed) }
        guard sourcePath != nil else { return .refused(.sourceUnavailable) }
        if let exact = candidates.first(where: { $0.tag == nil && $0.format == "srt" }) {
            return await select(path: exact.path, slot: .primary)
        }
        if candidates.contains(where: { $0.tag == nil && $0.format == "ass" }) { return .refused(.unsupportedASS) }
        return .noExactSidecar
    }
    public func select(path: String, slot: SubtitleController.Slot) async -> SubtitleSidecarSelection {
        guard !closed else { return .refused(.closed) }
        guard sourcePath != nil, let candidate = candidates.first(where: { $0.path == path }) else { return .refused(.notDiscovered) }
        guard candidate.format == "srt" else { return .refused(.unsupportedASS) }
        let revision = sourceRevision
        bumpTicket(slot)
        let ticket = currentTicket(slot)
        let track: SubtitleTrack.Track
        do { track = try await loader(candidate.path) }
        catch {
            guard isCurrent(revision: revision, slot: slot, ticket: ticket) else { return .refused(.staleCompletion) }
            if Task.isCancelled { return .refused(.staleCompletion) }
            if case SubtitleTrack.LoadError.unreadable = error { return .refused(.unreadable) }
            return .refused(.malformed)
        }
        guard !Task.isCancelled, isCurrent(revision: revision, slot: slot, ticket: ticket) else { return .refused(.staleCompletion) }
        guard track.format == "srt", track.styles.isEmpty, track.unsupportedOverrides.isEmpty,
              track.skippedStyles.isEmpty else { return .refused(.unsupportedASS) }
        clearGeneration()
        if slot == .primary { controller.selectPrimary(track) } else { controller.selectSecondary(track) }
        sampleLastTime()
        return .selected(path: candidate.path, slot: slot)
    }
    @discardableResult
    public func setDelay(_ seconds: Double, slot: SubtitleController.Slot) -> SubtitleSidecarRefusal? {
        guard !closed else { return .closed }
        guard seconds.isFinite else { return .invalidDelay }
        controller.setDelay(seconds, slot: slot); clearGeneration(); sampleLastTime(); return nil
    }
    public func setVisible(_ visible: Bool, slot: SubtitleController.Slot) {
        guard !closed else { return }
        controller.setVisible(visible, slot: slot); clearGeneration(); sampleLastTime()
    }
    /// Same semantics as SubtitleController.reset: keep primary; remove secondary,
    /// zero delay and restore visibility. Invalidates pre-reset async loads.
    public func reset() {
        guard !closed else { return }
        invalidateLoads(); clearGeneration(); controller.reset(); sampleLastTime()
    }
    /// Explicit external controller replacement shares the same source/async fence.
    @discardableResult
    public func setController(_ value: SubtitleController) -> Bool {
        guard !closed, sourcePath != nil else { return false }
        for track in [value.primary, value.secondary].compactMap({ $0 }) {
            guard track.format == "srt", track.styles.isEmpty,
                  track.unsupportedOverrides.isEmpty, track.skippedStyles.isEmpty else { return false }
        }
        invalidateLoads(); clearGeneration(); controller = value; sampleLastTime(); return true
    }
    public func sample(session: UInt64, generation: UInt64, filmTime: Double) {
        guard !closed, sourcePath != nil, session == self.session,
              generation == producer.generation, filmTime.isFinite else { return }
        self.filmTime = filmTime
        sampleLastTime()
    }
    public func seekBegan() {
        guard !closed else { return }
        invalidateLoads(); clearGeneration(); filmTime = nil
    }
    public func close() {
        guard !closed else { return }
        invalidateLoads(); closed = true; sourcePath = nil; candidates = []; filmTime = nil
        controller = SubtitleController()
        if let batch = producer.close() { emit(batch) }
    }
    private func sampleLastTime() {
        guard let filmTime, let batch = producer.sample(session: session, generation: producer.generation,
                                                       filmTime: filmTime, controller: controller) else { return }
        emit(batch)
    }
    private func clearGeneration() { if let batch = producer.advance() { emit(batch) } }
    private func currentTicket(_ slot: SubtitleController.Slot) -> UInt64 { slot == .primary ? primaryTicket : secondaryTicket }
    private func bumpTicket(_ slot: SubtitleController.Slot) {
        if slot == .primary { primaryTicket &+= 1 } else { secondaryTicket &+= 1 }
    }
    private func invalidateLoads() { sourceRevision &+= 1; primaryTicket &+= 1; secondaryTicket &+= 1 }
    private func isCurrent(revision: UInt64, slot: SubtitleController.Slot, ticket: UInt64) -> Bool {
        !closed && revision == sourceRevision && ticket == currentTicket(slot)
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/GorAVSubtitles/SubtitleTrack.swift').read_bytes()).hexdigest()=='d0e635a1ec87e20d75cfdb59dd75fb4f9aec24f7c54a2f88f84dab154518b969'
assert hashlib.sha256((ROOT/'Sources/GorAVSubtitles/SubtitleSidecarSession.swift').read_bytes()).hexdigest()=='f39eadb0dddd92f330f20bdc55fdd9da0a7a5a1223225817edad5581fcc858f7'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-02; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-02; baseline only, product change and semantic test still required
```

secret scan: clean
