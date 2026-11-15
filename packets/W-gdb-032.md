# W-gdb-032 decoder-lifetime fault vector pack
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-032

```packet-json
{
 "packet_id": "W-gdb-032",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/GorAVPlaybackCore/DecoderInventory.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "register(_:kind:codec:sourceID:revisionAtOpen:) -> RegisterOutcome; deregister(_:) -> Bool; mark(_:_:); invalidateSession(_:); snapshot(_:) -> DecoderSnapshot?; activeSnapshots(session:) -> [DecoderSnapshot]",
  "types": "RegisterOutcome { registered, refusedInvalidatedSession, refusedIdentityExhausted, duplicateRefused }; DecoderLifecycle { open, draining, failed, closed }; DecoderIdentity { session: UInt64, handle: UInt64 }",
  "ownership_lifetime": "inventory owns entries; session invalidation fences wholesale",
  "caller": "decoder fault vector runner",
  "callee": "DecoderInventory register/mark/deregister/invalidateSession/snapshot/activeSnapshots (pinned below)"
 },
 "test": {
  "command": "swift run decoder-lifetime-tests && swift run decoder-inventory-tests",
  "expected": "exit 0 for both; final lines end '0 FAIL' (9 + 27 existing checks stay green); vector rows replay green; a seeded phantom registration is caught",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/decoder-fault-vectors/"
  ],
  "return_form": "full-files"
 }
}
```

## problem (what fails for the user)
decoder registration/lifetime is tracked by DecoderInventory; abort-mid-open, double-close or registration-after-abort regressions ship as leaked decoders or phantom inventory entries.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/DecoderInventory.swift (sha256 f502dcdf; first 60 lines below); decoder-lifetime-tests (9 checks) + decoder-inventory-tests (27 checks) on Linux per the harness map.
- real test command: swift run decoder-lifetime-tests + swift run decoder-inventory-tests stay green.

## expected behaviour
fault vectors: open/fail/close/reopen sequences, abort mid-open, double-close typed no-op, registration after abort forbidden, generation counters across reopen; expected registry/lifetime state tables per sequence.

## exact call site and interface
DecoderInventory's registration/lifetime vocabulary (pinned excerpt); vectors + checker are the deliverable.

## pinned ABI decisions (integrator, 2026-11-15; register/close/invalidate ABI)
DecoderInventory (excerpt-level, same pin):
- register(_ id: DecoderIdentity, kind: DecoderKind, codec: String, sourceID: String? = nil, revisionAtOpen: UInt64 = 1) -> RegisterOutcome { registered, refusedInvalidatedSession, refusedIdentityExhausted, duplicateRefused } - a duplicate keeps the existing entry and receipts duplicateRegistrations += 1
- mark(_ id:, _ lifecycle:) with DecoderLifecycle { open, draining, failed, closed }
- deregister(_ id:) -> Bool - false = unknown identity, typed; deregistrations counter
- invalidateSession(_ session: UInt64) - fences a whole session (seek-restart/reset): all its entries drop and later registrations for it are refusedInvalidatedSession
- snapshot(_ id:) -> DecoderSnapshot? - nil for unknown/deregistered/session-invalidated; closed/failed entries still returned until deregistered
- activeSnapshots(session:) - registration order, excludes .closed, [] for invalidated sessions
- DecoderIdentity { session: UInt64, handle: UInt64 }; DecoderSnapshot carries lifecycle + registrationSeq: UInt64 (monotonic from 1)
fault vectors assert exactly these outcomes: registration after invalidateSession = refusedInvalidatedSession; double-close = second deregister returns false; abort-mid-open leaves no entry.

## behaviour that must not change
the 9+27 existing checks stay green; synthetic decoder stub only - no real codec.

## acceptance test (from the product repo)
vectors replay green against the pinned inventory; a seeded phantom registration is caught.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/DecoderInventory.swift (sha256 f502dcdf, lines 1-60 of 155)
```swift id=source1
import Foundation

// Row 195b-55 (arch-195b): active-decoder inventory. A decoder instance is
// Metadata registry only: software adapters wire lifetime below; no container inventory is read.
// Callers must serialize mutations. Decoder instances can be
// tracked from registration to explicit deregistration; snapshots are typed,
// immutable, and generation-fenced. The cache answers "what is live right
// now" without touching decoder internals - the adapter registers on open and
// deregisters on close/deinit/failure.

public struct DecoderIdentity: Equatable, Hashable, Sendable {
    /// Session/generation the decoder belongs to (same fence as frames).
    public let session: UInt64
    /// Per-session decoder handle; unique within a session.
    public let handle: UInt64
    public init(session: UInt64, handle: UInt64) {
        self.session = session; self.handle = handle
    }
}

public enum DecoderKind: String, Equatable, Sendable {
    case videoSoftware, audioSoftware, videoHardware
}

public enum DecoderLifecycle: String, Equatable, Sendable {
    case open, draining, failed, closed
}

/// Typed snapshot of one tracked decoder at read time.
public struct DecoderSnapshot: Equatable, Sendable {
    public let identity: DecoderIdentity
    public let kind: DecoderKind
    /// Probe-admitted codec name (e.g. "h264", "aac"); never a free-form
    /// source string (evidence privacy rule).
    public let codec: String
    /// Opaque provider identity, never a file path/URL. Immutable OPEN facts,
    /// not a claim to mirror a later seek revision or enumerate container tracks.
    public let sourceID: String?
    public let revisionAtOpen: UInt64
    /// Mutated only by DecoderInventory (same file) on mark(); immutable to callers.
    public internal(set) var lifecycle: DecoderLifecycle
    /// Registration order, monotonic per inventory - a cheap total order for
    /// "oldest live decoder" without trusting clocks.
    public let registrationSeq: UInt64
}

public struct DecoderInventory: Sendable {

    public enum RegisterOutcome: Equatable, Sendable {
        case registered
        case refusedInvalidatedSession
        case refusedIdentityExhausted
        /// Same identity registered twice; the existing entry wins and the
        /// attempt is receipted.
        case duplicateRefused
    }

    public private(set) var entries: [DecoderIdentity: DecoderSnapshot] = [:]
    public private(set) var duplicateRegistrations = 0
    public private(set) var deregistrations = 0
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"ops":[{"register":{"s":1,"h":1},"expect":"registered"},{"register":{"s":1,"h":1},"expect":"duplicateRefused"},{"invalidateSession":1},{"register":{"s":1,"h":2},"expect":"refusedInvalidatedSession"}],"expectCounters":{"duplicateRegistrations":1}}
```
