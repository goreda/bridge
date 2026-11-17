# W-gdb-198y-in2tinct-14
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVCore/Boundary.swift in shipping-path engine station GorAVCore. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-14.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-14",
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
    "signatures": "Source-only characterization script reads Sources/GorAVCore/Boundary.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: SessionID, PlaybackIdentityAuthority, issue, PresentationRevision, bump, SourceDescriptor, Kind, StopReason, Lifecycle, SessionSnapshot, PlaybackBackend, open",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-14.py",
    "callee": "Sources/GorAVCore/Boundary.swift owning station GorAVCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-14.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-14.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-14.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.873841+00:00",
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
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-14.py",
        "block": "fixtures1",
        "sha256": "11a1e916c4fabcd7462d063e4fc1c1480655aefa6934bc140d6a1eb8c433fcc3"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "9b4c968501f25798ec0a8dcdd37dd896b1ce41b17b5c3e6072b5a1c5f46bed84",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-14: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "6cf1ca93039be09910a23f0590a19285b3b04cf28ac1aafd1c5ca677d27cf628"
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
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-14: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-14: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
