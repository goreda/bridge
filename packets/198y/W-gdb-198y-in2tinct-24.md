# W-gdb-198y-in2tinct-24
state: OPEN / unclaimed
lab: in2tinct

Build a new source-contract false-positive regression test for the exact file, independently from the prior fragment tests. Preserve source-pin evidence separately. Mask Swift comments and string literals before named declaration assertions. Add at least two real declaration signature/value boundary assertions and three mutation controls including comment-only decoy, string-only decoy, and renamed/removed declaration. Do not allow a comment/string containing an expected fragment to satisfy its declaration. Use explicit failures under python3 -O and execute normal/optimized positive plus on-disk external negative/restore controls. This remains source characterization, never Swift semantics or runtime.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-24.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-24",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/PreparedShotSession.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at Tests/Architecture/198y/W-gdb-198y-in2tinct-24.py checks Sources/GorAVPlaybackCore/PreparedShotSession.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: SourceRef, hash, PreparedShot, PreparedShotCommitReceipt, PreparedShotError, PreparedShotSourceValidator, canBind, audioSurvivesVideoReplace, PreparedShotSessionBackend, prepare, replaceVideo, currentReceipt",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-24.py",
    "callee": "Sources/GorAVPlaybackCore/PreparedShotSession.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-24.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-24.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-24.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.257572+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/PreparedShotSession.swift",
        "block": "source1",
        "sha256": "d7e6636475d4e1565e43b9741d7946e8d6615642ec92325c457ffd079d3ffb74"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-24.py",
        "block": "fixtures1",
        "sha256": "dd885e6dd9a6b59772d5ebb8b2d4d186513ab25b5aba8756259b6503b1231d63"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "b0229a3b72a4a87e61340f9dda5475b21fb242712dde2e61179f929d9b9a7486",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-24: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "9677608f4e4d591ebadf5fa0691317f255ad118214772100de56919491477537"
  }
}
```

```swift id=source1
import Foundation
import GorAVCore
import GorAVNativeProbeKit

// Sources/GorAVPlaybackCore/PreparedShotSession.swift
// arch-195b R4: atomic multi-source prepared-shot session.
// Pure coordinator state logic only. This does not open or swap media, start audio,
// or bind a real film clock. Receipts here describe coordinator bookkeeping,
// not observed playback commits. A concrete session adapter is still required.

public struct SourceRef: Hashable, Sendable {
    public let id: String
    public let kind: SourceDescriptor.Kind
    public let startOffset: RationalTime
    public init(id: String, kind: SourceDescriptor.Kind, startOffset: RationalTime) {
        self.id = id
        self.kind = kind
        self.startOffset = startOffset
    }
    public static func == (a: SourceRef, b: SourceRef) -> Bool {
        a.id == b.id && a.kind == b.kind && a.startOffset == b.startOffset
    }
    public func hash(into h: inout Hasher) {
        h.combine(id)
        h.combine(startOffset)
        switch kind {
        case .local: h.combine(0)
        case .remote: h.combine(1)
        case .webTorrent: h.combine(2)
        case .iptv: h.combine(3)
        case .ytdl: h.combine(4)
        case .archiveOrg: h.combine(5)
        }
    }
}

public struct PreparedShot: Sendable {
    public let shotID: UUID
    public let video: SourceRef
    public let audio: SourceRef?
    public let filmClockEpoch: UInt64
    public init(shotID: UUID, video: SourceRef, audio: SourceRef?, filmClockEpoch: UInt64) {
        self.shotID = shotID
        self.video = video
        self.audio = audio
        self.filmClockEpoch = filmClockEpoch
    }
}

public struct PreparedShotCommitReceipt: Sendable {
    public let shotID: UUID
    /// Film clock epoch. Unchanged across prepare+replaceVideo => no coordinator epoch change.
    public let epoch: UInt64
    /// Identical across a prepare/replaceVideo receipt pair => coordinator binding token preserved; no audio-device proof.
    public let audioBindingID: UUID?
    public let audioBindingPreserved: Bool
    /// Film time at which the commit took effect.
    public let committedAt: RationalTime
    public let priorVideo: SourceRef?
    public init(shotID: UUID, epoch: UInt64, audioBindingID: UUID?, audioBindingPreserved: Bool, committedAt: RationalTime, priorVideo: SourceRef?) {
        self.shotID = shotID
        self.epoch = epoch
        self.audioBindingID = audioBindingID
        self.audioBindingPreserved = audioBindingPreserved
        self.committedAt = committedAt
        self.priorVideo = priorVideo
    }
}

public enum PreparedShotError: Error, Sendable, Equatable {
    case sourceNotPrepared(String)
    case staleEpoch(expected: UInt64, found: UInt64)
    /// Commit fails atomically; a silent audio restart is never allowed.
    case audioBindingLost(reason: String)
    case admissionRefused(String)
}

/// Admission hook the media layer provides: can this source be bound right now?
/// The coordinator calls it for EVERY source in the atomic op before any state
/// changes; a refusal aborts the whole op with no partial state.
public protocol PreparedShotSourceValidator: Sendable {
    func canBind(_ source: SourceRef) -> Bool
    /// True when replacing the video would keep the given audio source playable
    /// without restart (same decode session, same clock domain).
    func audioSurvivesVideoReplace(_ audio: SourceRef) -> Bool
}

/// Atomic multi-source prepared-shot session. Semantics:
/// - prepare binds render video + optional separate source audio to ONE film
///   clock at their startOffsets; no playback starts.
/// - replaceVideo commits at a film time without audio restart and without
///   clock rebase; the receipt pair proves both (constant epoch + binding id).
public protocol PreparedShotSessionBackend {
    func prepare(_ shot: PreparedShot) async throws -> PreparedShotCommitReceipt
    func replaceVideo(at filmTime: RationalTime, with video: SourceRef) async throws -> PreparedShotCommitReceipt
    func currentReceipt() async -> PreparedShotCommitReceipt?
    func abortUncommittedPreparation() async -> PreparedAdoptionRelease
    /// Explicit terminal cancellation, not recovery from a refused first swap.
    func cancel() async
}

/// Reference coordinator implementing the atomic semantics. All validation
/// happens before any state mutation, so a failed op leaves the session
/// exactly as it was (atomicity).
public actor PreparedShotCoordinator: PreparedShotSessionBackend {
    public enum State: Sendable, Equatable {
        case idle, prepared, cancelled
    }
    private let validator: PreparedShotSourceValidator
    private var state: State = .idle
    private var shot: PreparedShot?
    private var receipt: PreparedShotCommitReceipt?
    private var audioBinding: UUID?
    private var adoption = PreparedAdoption()

    public init(validator: PreparedShotSourceValidator) {
        self.validator = validator
    }

    public func prepare(_ shot: PreparedShot) async throws -> PreparedShotCommitReceipt {
        guard state == .idle else {
            throw PreparedShotError.staleEpoch(expected: 0, found: shot.filmClockEpoch)
        }
        guard validator.canBind(shot.video) else {
            throw PreparedShotError.admissionRefused("video \(shot.video.id)")
        }
        if let a = shot.audio, !validator.canBind(a) {
            throw PreparedShotError.admissionRefused("audio \(a.id)")
        }
        // All sources validated; commit atomically.
        let binding = shot.audio == nil ? nil : UUID()
        let r = PreparedShotCommitReceipt(
            shotID: shot.shotID, epoch: shot.filmClockEpoch,
            audioBindingID: binding, audioBindingPreserved: shot.audio != nil,
            committedAt: shot.video.startOffset, priorVideo: nil)
        self.shot = shot
        self.receipt = r
        self.audioBinding = binding
        self.state = .prepared
        adoption.adopt()
        return r
    }

    public func replaceVideo(at filmTime: RationalTime, with video: SourceRef) async throws -> PreparedShotCommitReceipt {
        guard state == .prepared, let current = shot, let prior = receipt else {
            throw PreparedShotError.sourceNotPrepared("no prepared shot")
        }
        guard adoption.beginOperation() else {
            throw PreparedShotError.sourceNotPrepared("operation in flight")
        }
        var didCommit = false
        defer { adoption.finishOperation(didCommit: didCommit) }
        guard current.filmClockEpoch == prior.epoch else {
            throw PreparedShotError.staleEpoch(expected: prior.epoch, found: current.filmClockEpoch)
        }
        guard validator.canBind(video) else {
            throw PreparedShotError.admissionRefused("video \(video.id)")
        }
        var preserved = false
        if let a = current.audio {
            guard validator.audioSurvivesVideoReplace(a), let binding = audioBinding else {
                // Atomic failure: no state changed, audio never silently restarts.
                throw PreparedShotError.audioBindingLost(reason: "audio \(a.id) cannot survive video replace")
            }
            preserved = true
            let r = PreparedShotCommitReceipt(
                shotID: current.shotID, epoch: prior.epoch,
                audioBindingID: binding, audioBindingPreserved: preserved,
                committedAt: filmTime, priorVideo: current.video)
            self.shot = PreparedShot(shotID: current.shotID, video: video, audio: current.audio, filmClockEpoch: current.filmClockEpoch)
            self.receipt = r
            didCommit = true
            return r
        }
        let r = PreparedShotCommitReceipt(
            shotID: current.shotID, epoch: prior.epoch,
            audioBindingID: nil, audioBindingPreserved: preserved,
            committedAt: filmTime, priorVideo: current.video)
        self.shot = PreparedShot(shotID: current.shotID, video: video, audio: nil, filmClockEpoch: current.filmClockEpoch)
        self.receipt = r
        didCommit = true
        return r
    }

    public func currentReceipt() async -> PreparedShotCommitReceipt? { receipt }

    public func abortUncommittedPreparation() async -> PreparedAdoptionRelease {
        let result = adoption.abortUncommitted()
        if result == .released {
            state = .idle; shot = nil; receipt = nil; audioBinding = nil
        }
        return result
    }

    public func cancel() async {
        adoption.clear()
        state = .cancelled
        shot = nil
        receipt = nil
        audioBinding = nil
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVPlaybackCore/PreparedShotSession.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='d7e6636475d4e1565e43b9741d7946e8d6615642ec92325c457ffd079d3ffb74', 'pinned source changed: rebase and review, never bless silently'
for token in ['SourceRef', 'hash', 'PreparedShot', 'PreparedShotCommitReceipt', 'PreparedShotError', 'PreparedShotSourceValidator', 'canBind', 'audioSurvivesVideoReplace', 'PreparedShotSessionBackend', 'prepare', 'replaceVideo', 'currentReceipt']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='d7e6636475d4e1565e43b9741d7946e8d6615642ec92325c457ffd079d3ffb74'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-24: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-24: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
