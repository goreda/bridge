# W-gdb-036 subtitle sidecar discovery and selection fixtures
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-036

```packet-json
{
 "packet_id": "W-gdb-036",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/GorAVSubtitles/SubtitleSidecarSession.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "discover(forVideoPath: String) -> [Candidate]; select(path: String, slot: Slot) async -> SubtitleSidecarSelection; loadExactPrimary() async -> SubtitleSidecarSelection",
  "types": "Candidate { path: String, tag: String?, format: String }; SubtitleSidecarSelection { selected(path,slot), noExactSidecar, refused(SubtitleSidecarRefusal) }; SubtitleSidecarRefusal 9 cases",
  "ownership_lifetime": "Candidate value types; staleCompletion fences mid-session file changes",
  "caller": "sidecar fixture runner + cue-output-tests",
  "callee": "SubtitleAutoLoad.discover(forVideoPath:) -> [Candidate] + SubtitleSidecarSession select/loadExactPrimary (pinned below)"
 },
 "test": {
  "command": "swift run cue-output-tests",
  "expected": "exit 0; final line 'cue-output-tests: N PASS, 0 FAIL' with N >= 74; fixture-tree rows replay green; a renamed file produces exactly the expected selection change",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/sidecar-fixtures/",
   "Sources/cue-output-tests/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
sidecar discovery/selection order decides which subtitle file the user sees; naming-convention drift or a stale selection after files change ships as wrong-language or missing subtitles.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVSubtitles/SubtitleSidecarSession.swift (sha256 f39eadb0; first 60 lines below); cue-output-tests covers discovery/load/select (74 PASS at the pin).
- real test command: swift run cue-output-tests stays green.

## expected behaviour
fixture trees: naming-convention matches (exact, language-suffixed, case variants), directory-order determinism, multi-track language priority, stale-selection fencing when files change mid-session; expected discovery order and selection per tree; generator builds trees in a temp dir.

## exact call site and interface
SubtitleSidecarSession's discovery/select surface (pinned excerpt) is asserted.

## pinned ABI decisions (integrator, 2026-11-15; discovery/select methods)
- public static func SubtitleAutoLoad.discover(forVideoPath: String) -> [Candidate] (SubtitleAutoLoad.swift, sha256 bdf2a96b, same pin): exact-basename matches first, then language-tagged matches sorted by path; extensions {"srt","ass","ssa"} ("ssa" normalized to format "ass"); unknown extensions never returned; an empty result is a fact (no sidecars), never an error
- public struct Candidate { path: String; tag: String? /* nil = exact-basename match, else the tag between basename and extension */; format: String }
- session surface (excerpt above): replaceSource(path: String) -> SubtitleSidecarRefusal?; loadExactPrimary() async -> SubtitleSidecarSelection; select(path: String, slot: SubtitleController.Slot) async -> SubtitleSidecarSelection
- public enum SubtitleSidecarSelection { selected(path: String, slot: SubtitleController.Slot), noExactSidecar, refused(SubtitleSidecarRefusal) }; SubtitleSidecarRefusal { closed, unsupportedSource, sourceUnavailable, notDiscovered, unsupportedASS, unreadable, malformed, staleCompletion, invalidDelay }
- convention at the pin: exact SRT only for auto primary; tagged files are never selected without an explicit choice; every completion rechecks source revision + per-slot request ticket before mutating (staleCompletion fences mid-session changes). fixture trees assert discovery ORDER and the exact selection/refusal case per tree.

## behaviour that must not change
the 74 existing checks stay green; text files only.

## acceptance test (from the product repo)
trees replay green; a renamed file produces exactly the expected selection change.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVSubtitles/SubtitleSidecarSession.swift (sha256 f39eadb0, lines 1-60 of 153)
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
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"tree":{"video":"movie.mp4","files":["movie.srt","movie.en.srt","movie.tr.ass","notes.txt"]},"expectOrder":["movie.srt","movie.en.srt","movie.tr.ass"],"expectAutoSelect":{"selected":"movie.srt","slot":"primary"},"expectTaggedAutoSelect":"never without explicit choice"}
```
