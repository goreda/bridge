# W-gdb-198y-in2tinct-34
state: OPEN / unclaimed
lab: in2tinct

Build a new source-contract false-positive regression test for the exact file, independently from the prior fragment tests. Preserve source-pin evidence separately. Mask Swift comments and string literals before named declaration assertions. Add at least two real declaration signature/value boundary assertions and three mutation controls including comment-only decoy, string-only decoy, and renamed/removed declaration. Do not allow a comment/string containing an expected fragment to satisfy its declaration. Use explicit failures under python3 -O and execute normal/optimized positive plus on-disk external negative/restore controls. This remains source characterization, never Swift semantics or runtime.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-34.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-34",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVCore/Boundary.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at Tests/Architecture/198y/W-gdb-198y-in2tinct-34.py checks Sources/GorAVCore/Boundary.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: SessionID, PlaybackIdentityAuthority, issue, PresentationRevision, bump, SourceDescriptor, Kind, StopReason, Lifecycle, SessionSnapshot, PlaybackBackend, open",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-34.py",
    "callee": "Sources/GorAVCore/Boundary.swift owning station GorAVCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-34.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-34.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-34.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.441845+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVCore/Boundary.swift",
        "block": "source1",
        "sha256": "29e29ac1cf6dbb2e4a0552c9016347b2a3a5a4aaacceecda6d1b50b8c58fdfef"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-34.py",
        "block": "fixtures1",
        "sha256": "2cc2ffd691f61f0ae740e012fb0446aee48cfb3cfa71aa860678cd2b8d3b664a"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "fab1bc062c5f82bad8958a594a94cfb6500f8ac7aef73d86b206756802b13e19",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-34: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "358dc3d41e19d07afb4383f7bc5704130f1e3fac9573c23f6f56ca4095196aa0"
  }
}
```

```swift id=source1
import Foundation
import GorAVCAtomics

/// No media bytes, credentials or runtime player are part of this Stage 0 contract.
///
/// IDENTITY AUTHORITY (architect full verdict S4): a SessionID's public
/// init carries NO authority. Production playback identity is issued ONLY
/// by PlaybackIdentityAuthority - one owner-issued opaque identity shared
/// across decoder/audio/display/ledger for a run, with a separate
/// seek/presentation revision. Per-lane minting (String+UInt64 forms,
/// hashes, fixed shell epochs) is a contract violation; explicit-epoch
/// construction remains for TEST FIXTURES ONLY and mints nothing.
public struct SessionID: Hashable, Sendable {
    public let epoch: UInt64
    /// S7: NOT a mint. Production identities come ONLY from
    /// PlaybackIdentityAuthority.issue() (one owner-issued opaque
    /// identity per run). This unchecked constructor exists for
    /// REFUSAL/FOREIGN-SESSION TESTS, which must fabricate arbitrary
    /// unissued ids to prove they are refused; naming it unchecked
    /// keeps forgery out of production call sites by inspection.
    public init(uncheckedEpoch: UInt64) { self.epoch = uncheckedEpoch }
}

/// The single owner of playback identity issuance (S4). Monotonic atomic
/// issuance; wrap is TYPED EXHAUSTION (nil), never a recycled identity.
public final class PlaybackIdentityAuthority: @unchecked Sendable {
    public static let shared = PlaybackIdentityAuthority()
    /// C-owned atomic cell (GorAVCAtomics); failable alloc = typed refusal.
    private let lastIssued: UnsafeMutableRawPointer?
    private init() { lastIssued = gorav_acell_create(0) }
    deinit { if let c = lastIssued { gorav_acell_destroy(c) } }
    /// Issue the next opaque session identity, or nil at typed exhaustion.
    public func issue() -> SessionID? {
        guard let c = lastIssued else { return nil }     // typed cell refusal
        while true {
            let last = gorav_aload(c)
            if last == UInt64.max { return nil }         // typed exhaustion, never wrap
            var e = last
            if gorav_acas(c, &e, last &+ 1) != 0 { return SessionID(uncheckedEpoch: last &+ 1) }
        }
    }
    /// Seek/presentation revision (S4): separate from session identity.
    /// A seek NEVER mints a new session; it bumps the run's revision.
    public final class PresentationRevision: @unchecked Sendable {
        private let cell: UnsafeMutableRawPointer?
        public init() { cell = gorav_acell_create(0) }
        deinit { if let c = cell { gorav_acell_destroy(c) } }
        public var current: UInt64 { guard let c = cell else { return 0 }; return gorav_aload(c) }
        public func bump() -> UInt64 { guard let c = cell else { return 0 }; return gorav_afetch_add(c, 1) &+ 1 }
    }
}

public struct SourceDescriptor: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case local, remote, webTorrent, iptv, ytdl, archiveOrg }
    public let id: String
    public let kind: Kind
    public let seekable: Bool
    public init(id: String, kind: Kind, seekable: Bool) {
        self.id = id; self.kind = kind; self.seekable = seekable
    }
}

public enum StopReason: Equatable, Sendable { case user, replaced, endOfFile, failure }
public enum Lifecycle: Equatable, Sendable {
    case idle, opening, ready, playing, paused, buffering, ended(StopReason), failed
}
public struct SessionSnapshot: Equatable, Sendable {
    public let id: SessionID
    public let source: SourceDescriptor
    public let lifecycle: Lifecycle
    public init(id: SessionID, source: SourceDescriptor, lifecycle: Lifecycle) {
        self.id = id; self.source = source; self.lifecycle = lifecycle
    }
}

/// A backend can be an mpv adapter first. Native demux/decode and render backends
/// are later implementations, not capabilities asserted by this interface.
public protocol PlaybackBackend: AnyObject {
    func open(_ source: SourceDescriptor, session: SessionID) async throws
    func stop(session: SessionID, reason: StopReason) async
    func seek(seconds: Double, session: SessionID, requestID: UInt64) async throws
    func snapshot(session: SessionID) async -> SessionSnapshot?
}

/// Pure epoch gate for callbacks from async backends. Source/event correlation
/// remains backend-specific and must not be inferred from arrival order alone.
public struct SessionGate: Sendable {
    public private(set) var active: SessionID?
    public init() {}
    /// S7: the gate CONSUMES an owner-issued identity; it never mints
    /// one (PlaybackIdentityAuthority is the single issuance owner).
    @discardableResult public mutating func begin(_ id: SessionID) -> SessionID {
        active = id
        return id
    }
    public mutating func stop() { active = nil }
    public func accepts(_ id: SessionID) -> Bool { active == id }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVCore/Boundary.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='29e29ac1cf6dbb2e4a0552c9016347b2a3a5a4aaacceecda6d1b50b8c58fdfef', 'pinned source changed: rebase and review, never bless silently'
for token in ['SessionID', 'PlaybackIdentityAuthority', 'issue', 'PresentationRevision', 'bump', 'SourceDescriptor', 'Kind', 'StopReason', 'Lifecycle', 'SessionSnapshot', 'PlaybackBackend', 'open']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='29e29ac1cf6dbb2e4a0552c9016347b2a3a5a4aaacceecda6d1b50b8c58fdfef'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-34: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-34: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
