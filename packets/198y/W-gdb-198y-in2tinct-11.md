# W-gdb-198y-in2tinct-11
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVSubtitles/SubtitleSidecarSession.swift in shipping-path engine station GorAVSubtitles. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-11.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-11",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/SubtitleSidecarSession.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVSubtitles/SubtitleSidecarSession.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: SubtitleSidecarRefusal, SubtitleSidecarSelection, SubtitleSidecarSession, replaceSource, loadExactPrimary, select, setDelay, setVisible, reset, setController, sample, seekBegan",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-11.py",
    "callee": "Sources/GorAVSubtitles/SubtitleSidecarSession.swift owning station GorAVSubtitles"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-11.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-11.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-11.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:18.794246+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/SubtitleSidecarSession.swift",
        "block": "source1",
        "sha256": "f39eadb0dddd92f330f20bdc55fdd9da0a7a5a1223225817edad5581fcc858f7"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-11.py",
        "block": "fixtures1",
        "sha256": "a08530e5e453a22796e30588c379412582b906650a379f9df4a3bb40c19b9706"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "8b8ec3686c1d678e43d6486a70cda1e08c69502f2285db602599940f5ec2ad53",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-11: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "f6934f1e46434e6552f91e1bdbf4c39df6378bf354716dbb54ffe62ca6374be0"
  }
}
```

```swift id=source1
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
p=ROOT/'Sources/GorAVSubtitles/SubtitleSidecarSession.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='f39eadb0dddd92f330f20bdc55fdd9da0a7a5a1223225817edad5581fcc858f7', 'pinned source changed: rebase and review, never bless silently'
for token in ['SubtitleSidecarRefusal', 'SubtitleSidecarSelection', 'SubtitleSidecarSession', 'replaceSource', 'loadExactPrimary', 'select', 'setDelay', 'setVisible', 'reset', 'setController', 'sample', 'seekBegan']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='f39eadb0dddd92f330f20bdc55fdd9da0a7a5a1223225817edad5581fcc858f7'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-11: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-11: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
