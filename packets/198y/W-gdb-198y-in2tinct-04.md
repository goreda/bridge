# W-gdb-198y-in2tinct-04
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVPlaybackCore/PreparedShotSession.swift in shipping-path engine station GorAVPlaybackCore. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-04.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-04",
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
    "signatures": "Source-only characterization script reads Sources/GorAVPlaybackCore/PreparedShotSession.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: SourceRef, hash, PreparedShot, PreparedShotCommitReceipt, PreparedShotError, PreparedShotSourceValidator, canBind, audioSurvivesVideoReplace, PreparedShotSessionBackend, prepare, replaceVideo, currentReceipt",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-04.py",
    "callee": "Sources/GorAVPlaybackCore/PreparedShotSession.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-04.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-04.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-04.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.678410+00:00",
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
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-04.py",
        "block": "fixtures1",
        "sha256": "db0a6ff605a99943484ae1a2603b04b470abe6c70d84bf86889a1e5569298b0f"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "46a3ee46dbe3f6b394db4222ebadc386a2639a58a22358f1a067dc0a067738d8",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-04: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "cf4395e1b9bee5e29ae7e297903b571fb44d1b4c8a70b3f66cf3986960f4d592"
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
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-04: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-04: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
