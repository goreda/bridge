# W-gdb-d59: 195b-59 follow-on: lifecycle marking on the shared DecoderInventoryStore

DecoderInventory (the value type) has `mark(_:_:)` and the lifecycle states open/draining/failed/closed, but the shared DecoderInventoryStore that the video and audio adapters actually use exposes only register, deregister, invalidateSession, snapshot and activeSnapshots. So failed and draining are unreachable in production. Add `DecoderInventoryStore.mark(_:_:) -> Bool` with the rules in the interface block, and the test additions in the fixture block. Adapter call-site wiring (video open failure, audio failure paths) is a separate integrator step and is not part of this packet.

Not in scope: adapter wiring, hardware registration, container track inventory, any change to the DecoderInventory value type. Excerpts are verbatim lines from the pinned product sha; the first comment line of each block is a label added by the packet writer and is not part of the excerpt hash. Fixture blocks are new text proposed by this packet.

```packet-json
{
  "packet": "W-gdb-d59",
  "code_owner": "gdb gorav integrator (decoder lane), owner of Sources/GorAVPlaybackCore and Sources/GorAVFFmpegAdapter on gorav/engine",
  "scope": "implementation",
  "product_repo": "goreda/gorav",
  "product_branch": "engine",
  "product_sha": "8eaffc75b331a9d65ddce404266738a9d42043ed",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/DecoderInventory.swift",
      "excerpt_block": "ex_lifecycle",
      "lines": "25-28"
    },
    {
      "path": "Sources/GorAVPlaybackCore/DecoderInventory.swift",
      "excerpt_block": "ex_inventory_mark",
      "lines": "85-88"
    },
    {
      "path": "Sources/GorAVPlaybackCore/DecoderInventory.swift",
      "excerpt_block": "ex_store",
      "lines": "119-167"
    },
    {
      "path": "Sources/decoder-inventory-tests/main.swift",
      "excerpt_block": "ex_test_head",
      "lines": "1-16"
    }
  ],
  "excerpt_sha256_8": {
    "ex_lifecycle": "9c0a4b92",
    "ex_inventory_mark": "182cd158",
    "ex_store": "ecf880a5",
    "ex_test_head": "8393bbdc"
  },
  "interface": {
    "signatures": "extension of DecoderInventoryStore: @discardableResult public func mark(_ id: DecoderIdentity, _ lifecycle: DecoderLifecycle) -> Bool",
    "types": "DecoderIdentity, DecoderLifecycle and DecoderSnapshot exactly as in the excerpts; no new public types.",
    "ownership_lifetime": "mark takes the store lock, applies the change through the inventory value, and returns true only when an entry existed, its session is not invalidated, and its current lifecycle is not .closed. A transition out of .closed returns false and changes nothing. A transition from .open, .draining or .failed to any lifecycle (including .failed -> .closed) returns true. No callbacks run under the lock.",
    "caller": "The adapters on their native queues (future wiring): FFmpegSoftwareDecoder and FFmpegSoftwareAudioDecoder on failure/drain/close, via their decoderInventoryID.",
    "callee": "DecoderInventory.mark (value type, excerpted), then entries[id]!.lifecycle assignment."
  },
  "test": {
    "command": "swift run decoder-inventory-tests",
    "expected": "Exit 0 and stdout ends with \"decoder-inventory-tests: N PASS, 0 FAIL\" where N is the previous pass count plus 9 (the number of check lines in the fixture). No FAIL line is printed.",
    "fixture_block": "fx_decoder_inventory_additions",
    "note": "Run by the integrator on Linux with the pinned provider; a lab without the repo returns the patch and states \"unrun\"."
  },
  "target": {
    "branch": "lane/gdb-196p-decoder (integrator creates it from product_sha; never ohal/gorav main or PR 3)",
    "paths": [
      "Sources/GorAVPlaybackCore/DecoderInventory.swift",
      "Sources/decoder-inventory-tests/main.swift"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/decoder-inventory-tests/main.swift",
        "block": "merged_main"
      },
      {
        "path": "Sources/GorAVPlaybackCore/DecoderInventory.swift",
        "block": "fx_mark_patch"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "8eaffc75b331a9d65ddce404266738a9d42043ed",
    "command": "swift run decoder-inventory-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:18:58.817154+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": " PASS, 0 FAIL",
    "inline_files": [
      {
        "path": "Sources/decoder-inventory-tests/main.swift",
        "block": "merged_main",
        "sha256": "3c246cb970f963bc553d9a80b4a442cc700861bf5cc1eef16cfc8a4ae104451a"
      },
      {
        "path": "Sources/GorAVPlaybackCore/DecoderInventory.swift",
        "block": "fx_mark_patch",
        "sha256": "abd61afcf26f2ca4879cebdc8d82a482b1de26b0fd0061539e28df62f0a87705"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "805c6a3d12c6630946f54f1b95006f9084c35dbb6e7b4751a11df4863ad58a7e",
    "last_5_lines": [
      "[52/55] Wrapping AST for decoder-inventory-tests for debugging",
      "[53/55] Write Objects.LinkFileList",
      "[54/55] Linking decoder-inventory-tests",
      "Build of product 'decoder-inventory-tests' complete! (6.90s)",
      "decoder-inventory-tests: 36 PASS, 0 FAIL"
    ],
    "receipt_sha256": "47edc3431a2dd3f358c9f19a31dff163c4f2c7f1c700221fa7d58182de5c6b2f"
  }
}
```

## Excerpt ex_lifecycle

```swift id=ex_lifecycle
// Sources/GorAVPlaybackCore/DecoderInventory.swift lines 25-28 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
public enum DecoderLifecycle: String, Equatable, Sendable {
    case open, draining, failed, closed
}

```

## Excerpt ex_inventory_mark

```swift id=ex_inventory_mark
// Sources/GorAVPlaybackCore/DecoderInventory.swift lines 85-88 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
    public mutating func mark(_ id: DecoderIdentity, _ lifecycle: DecoderLifecycle) {
        if entries[id] != nil { entries[id]!.lifecycle = lifecycle }
    }

```

## Excerpt ex_store

```swift id=ex_store
// Sources/GorAVPlaybackCore/DecoderInventory.swift lines 119-167 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
/// Shared metadata store. The lock serializes cross-decoder registry access;
/// native open/failure/teardown calls still originate on each adapter's queue.
/// No callbacks run under this lock, and no second source open occurs here.
public final class DecoderInventoryStore: @unchecked Sendable {
    public static let shared = DecoderInventoryStore()
    private let lock = NSLock()
    private var inventory = DecoderInventory()
    private var nextHandle: UInt64 = 1
    public init() {}
    public func register(session: UInt64, kind: DecoderKind, codec: String,
                         sourceID: String, revisionAtOpen: UInt64) -> DecoderIdentity? {
        lock.lock(); defer { lock.unlock() }
        guard session != 0, revisionAtOpen != 0, !sourceID.isEmpty,
              nextHandle < UInt64.max else { return nil }
        let id=DecoderIdentity(session:session,handle:nextHandle)
        nextHandle += 1 // A refused attempt never allows handle reuse.
        guard inventory.register(id,kind:kind,codec:codec,sourceID:sourceID,
                                 revisionAtOpen:revisionAtOpen) == .registered else { return nil }
        return id
    }
    public func deregister(_ id: DecoderIdentity) {
        lock.lock(); defer { lock.unlock() }
        _ = inventory.deregister(id)
    }
    public func invalidateSession(_ session: UInt64) {
        lock.lock(); defer { lock.unlock() }
        inventory.invalidateSession(session)
    }
    public func snapshot(_ id: DecoderIdentity) -> DecoderSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return inventory.snapshot(id)
    }
    public func activeSnapshots(session: UInt64) -> [DecoderSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return inventory.activeSnapshots(session:session)
    }
}


```

## Excerpt ex_test_head

```swift id=ex_test_head
// Sources/decoder-inventory-tests/main.swift lines 1-16 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
import Foundation
import GorAVPlaybackCore

// Witness for row 195b-55: register/deregister, typed snapshots, duplicate
// refusal with receipt, lifecycle marking, session invalidation fencing,
// ordering by registration sequence.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

var inv = DecoderInventory()
let v7 = DecoderIdentity(session: 7, handle: 1)
let a7 = DecoderIdentity(session: 7, handle: 2)
let v8 = DecoderIdentity(session: 8, handle: 1)

// T1: register + snapshot
```

## Fixture fx_decoder_inventory_additions

```swift id=fx_decoder_inventory_additions
// Append to Sources/decoder-inventory-tests/main.swift before the final print/exit lines.
let ms = DecoderInventoryStore()
guard let mid = ms.register(session: 301, kind: .videoSoftware, codec: "h264", sourceID: "opaque-m", revisionAtOpen: 1) else {
    print("FAIL store-mark-setup"); exit(1)
}
check("store-mark-failed-returns-true", ms.mark(mid, .failed) == true)
check("store-mark-failed-still-visible", ms.snapshot(mid)?.lifecycle == .failed && ms.activeSnapshots(session: 301).count == 1)
check("store-mark-closed-returns-true", ms.mark(mid, .closed) == true)
check("store-mark-closed-hidden-from-active", ms.snapshot(mid)?.lifecycle == .closed && ms.activeSnapshots(session: 301).isEmpty)
check("store-mark-closed-is-terminal", ms.mark(mid, .open) == false && ms.snapshot(mid)?.lifecycle == .closed)
ms.deregister(mid)
check("store-mark-after-deregister-refused", ms.mark(mid, .open) == false && ms.snapshot(mid) == nil)
check("store-mark-unknown-refused", ms.mark(DecoderIdentity(session: 301, handle: 9999), .failed) == false)
guard let mid2 = ms.register(session: 302, kind: .audioSoftware, codec: "aac", sourceID: "opaque-n", revisionAtOpen: 1) else {
    print("FAIL store-mark-setup2"); exit(1)
}
ms.invalidateSession(302)
check("store-mark-invalidated-session-refused", ms.mark(mid2, .draining) == false && ms.snapshot(mid2) == nil)
guard let mid3 = ms.register(session: 303, kind: .videoSoftware, codec: "h264", sourceID: "opaque-o", revisionAtOpen: 1) else {
    print("FAIL store-mark-setup3"); exit(1)
}
check("store-mark-draining-keeps-active", ms.mark(mid3, .draining) == true && ms.activeSnapshots(session: 303).first?.lifecycle == .draining)
```

```swift id=merged_main
import Foundation
import GorAVPlaybackCore

// Witness for row 195b-55: register/deregister, typed snapshots, duplicate
// refusal with receipt, lifecycle marking, session invalidation fencing,
// ordering by registration sequence.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

var inv = DecoderInventory()
let v7 = DecoderIdentity(session: 7, handle: 1)
let a7 = DecoderIdentity(session: 7, handle: 2)
let v8 = DecoderIdentity(session: 8, handle: 1)

// T1: register + snapshot
check("T1-register", inv.register(v7, kind: .videoSoftware, codec: "h264") == .registered)
let s1 = inv.snapshot(v7)
check("T1-snapshot", s1?.kind == .videoSoftware && s1?.codec == "h264"
      && s1?.lifecycle == .open && s1?.registrationSeq == 1)

// T2: duplicate refused, receipted, original wins
check("T2-dup", inv.register(v7, kind: .audioSoftware, codec: "aac") == .duplicateRefused
      && inv.duplicateRegistrations == 1)
check("T2-original-wins", inv.snapshot(v7)?.kind == .videoSoftware)

// T3: ordering across registrations
_ = inv.register(a7, kind: .audioSoftware, codec: "aac")
_ = inv.register(v8, kind: .videoSoftware, codec: "hevc")
let act7 = inv.activeSnapshots(session: 7)
check("T3-order", act7.map { $0.identity.handle } == [1, 2])

// T4: lifecycle marking
inv.mark(a7, .draining)
check("T4-lifecycle", inv.snapshot(a7)?.lifecycle == .draining)
inv.mark(DecoderIdentity(session: 9, handle: 9), .failed) // unknown: no crash, no entry
check("T4-unknown-mark", inv.snapshot(DecoderIdentity(session: 9, handle: 9)) == nil)

// T5: activeSnapshots excludes closed, includes failed (it happened)
inv.mark(a7, .closed)
check("T5-closed-excluded", inv.activeSnapshots(session: 7).map { $0.identity.handle } == [1])
inv.mark(a7, .failed) // re-mark after closed is caller error but must not corrupt
check("T5b-snapshot-survives", inv.snapshot(a7)?.lifecycle == .failed)

// T6: deregister
check("T6-dereg", inv.deregister(a7) && inv.deregistrations == 1)
check("T6-gone", inv.snapshot(a7) == nil && !inv.deregister(a7))

// T7: session invalidation fences everything for that session
inv.invalidateSession(7)
check("T7-fenced", inv.snapshot(v7) == nil && inv.activeSnapshots(session: 7).isEmpty)
check("T7-other-session-live", inv.activeSnapshots(session: 8).count == 1)

// T8: invalidated generations are terminal; stale registrations cannot revive them.
check("T8-stale-register-refused", inv.register(v7, kind: .videoSoftware, codec: "h264") == .refusedInvalidatedSession)
check("T8-remains-fenced", inv.snapshot(v7) == nil && inv.activeSnapshots(session: 7).isEmpty)
let v9 = DecoderIdentity(session: 9, handle: 1)
check("T8-new-generation-registers", inv.register(v9, kind: .videoSoftware, codec: "h264") == .registered)
check("T8-seq-monotonic", inv.snapshot(v9)!.registrationSeq > inv.snapshot(v8)!.registrationSeq)

// 195b-59: serialized multi-decoder metadata store, not container inventory.
let store=DecoderInventoryStore()
let live=store.register(session:100,kind:.videoSoftware,codec:"h264",sourceID:"opaque-video-1",revisionAtOpen:1)!
let liveAudio=store.register(session:100,kind:.audioSoftware,codec:"aac",sourceID:"opaque-audio-1",revisionAtOpen:1)!
check("store-composite-handles",live != liveAudio)
check("store-open-identity",store.snapshot(live)?.sourceID == "opaque-video-1" && store.snapshot(live)?.revisionAtOpen == 1)
store.deregister(live)
check("store-close-drops-only-owner",store.snapshot(live) == nil && store.snapshot(liveAudio) != nil)
store.deregister(live)
let replacement=store.register(session:100,kind:.videoSoftware,codec:"hevc",sourceID:"opaque-video-2",revisionAtOpen:1)!
check("store-replacement-not-stale",replacement != live && store.snapshot(live) == nil)
store.invalidateSession(100)
check("store-invalidate-all",store.activeSnapshots(session:100).isEmpty)
check("store-stale-reregister-refused",store.register(session:100,kind:.videoSoftware,codec:"h264",sourceID:"old",revisionAtOpen:1) == nil)
check("store-zero-session-refused",store.register(session:0,kind:.videoSoftware,codec:"h264",sourceID:"x",revisionAtOpen:1) == nil)
check("store-zero-revision-refused",store.register(session:101,kind:.videoSoftware,codec:"h264",sourceID:"x",revisionAtOpen:0) == nil)
let lock=NSLock()
var ids:[DecoderIdentity]=[]
DispatchQueue.concurrentPerform(iterations:100) { n in
    if let id=store.register(session:101,kind:.videoSoftware,codec:"h264",sourceID:"opaque-\(n)",revisionAtOpen:1) {
        lock.lock(); ids.append(id); lock.unlock()
    }
}
check("store-concurrent-identities",Set(ids).count == 100 && store.activeSnapshots(session:101).count == 100)
for id in ids { store.deregister(id) }
check("store-concurrent-clean",store.activeSnapshots(session:101).isEmpty)

// Append to Sources/decoder-inventory-tests/main.swift before the final print/exit lines.
let ms = DecoderInventoryStore()
guard let mid = ms.register(session: 301, kind: .videoSoftware, codec: "h264", sourceID: "opaque-m", revisionAtOpen: 1) else {
    print("FAIL store-mark-setup"); exit(1)
}
check("store-mark-failed-returns-true", ms.mark(mid, .failed) == true)
check("store-mark-failed-still-visible", ms.snapshot(mid)?.lifecycle == .failed && ms.activeSnapshots(session: 301).count == 1)
check("store-mark-closed-returns-true", ms.mark(mid, .closed) == true)
check("store-mark-closed-hidden-from-active", ms.snapshot(mid)?.lifecycle == .closed && ms.activeSnapshots(session: 301).isEmpty)
check("store-mark-closed-is-terminal", ms.mark(mid, .open) == false && ms.snapshot(mid)?.lifecycle == .closed)
ms.deregister(mid)
check("store-mark-after-deregister-refused", ms.mark(mid, .open) == false && ms.snapshot(mid) == nil)
check("store-mark-unknown-refused", ms.mark(DecoderIdentity(session: 301, handle: 9999), .failed) == false)
guard let mid2 = ms.register(session: 302, kind: .audioSoftware, codec: "aac", sourceID: "opaque-n", revisionAtOpen: 1) else {
    print("FAIL store-mark-setup2"); exit(1)
}
ms.invalidateSession(302)
check("store-mark-invalidated-session-refused", ms.mark(mid2, .draining) == false && ms.snapshot(mid2) == nil)
guard let mid3 = ms.register(session: 303, kind: .videoSoftware, codec: "h264", sourceID: "opaque-o", revisionAtOpen: 1) else {
    print("FAIL store-mark-setup3"); exit(1)
}
check("store-mark-draining-keeps-active", ms.mark(mid3, .draining) == true && ms.activeSnapshots(session: 303).first?.lifecycle == .draining)

print("decoder-inventory-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)

```

```swift id=fx_mark_patch
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
    /// Sessions invalidated wholesale (reset/seek-restart); snapshots for
    /// them are never served again even if a stale decoder forgets to
    /// deregister.
    public private(set) var invalidatedSessions: Set<UInt64> = []
    private var nextSeq: UInt64 = 1

    public init() {}

    @discardableResult
    public mutating func register(_ id: DecoderIdentity, kind: DecoderKind,
                                  codec: String, sourceID: String? = nil,
                                  revisionAtOpen: UInt64 = 1) -> RegisterOutcome {
        guard !invalidatedSessions.contains(id.session) else { return .refusedInvalidatedSession }
        guard nextSeq < UInt64.max else { return .refusedIdentityExhausted }
        guard entries[id] == nil else {
            duplicateRegistrations += 1
            return .duplicateRefused
        }
        entries[id] = DecoderSnapshot(identity: id, kind: kind, codec: codec, sourceID: sourceID,
                                      revisionAtOpen: revisionAtOpen, lifecycle: .open, registrationSeq: nextSeq)
        nextSeq += 1
        return .registered
    }

    public mutating func mark(_ id: DecoderIdentity, _ lifecycle: DecoderLifecycle) {
        if entries[id] != nil { entries[id]!.lifecycle = lifecycle }
    }

    @discardableResult
    public mutating func deregister(_ id: DecoderIdentity) -> Bool {
        guard entries.removeValue(forKey: id) != nil else { return false }
        deregistrations += 1
        return true
    }

    /// Fence a whole session (seek-restart / reset): all its entries drop.
    public mutating func invalidateSession(_ session: UInt64) {
        invalidatedSessions.insert(session)
        entries = entries.filter { $0.key.session != session }
    }

    /// Live snapshot for one identity; nil for unknown, deregistered, or
    /// session-invalidated decoders. `lifecycle` filter: closed/failed
    /// entries are still returned (they happened) until deregistered.
    public func snapshot(_ id: DecoderIdentity) -> DecoderSnapshot? {
        guard !invalidatedSessions.contains(id.session) else { return nil }
        return entries[id]
    }

    /// All currently tracked decoders for a session, registration order.
    public func activeSnapshots(session: UInt64) -> [DecoderSnapshot] {
        guard !invalidatedSessions.contains(session) else { return [] }
        return entries.values
            .filter { $0.identity.session == session && $0.lifecycle != .closed }
            .sorted { $0.registrationSeq < $1.registrationSeq }
    }
}

/// Shared metadata store. The lock serializes cross-decoder registry access;
/// native open/failure/teardown calls still originate on each adapter's queue.
/// No callbacks run under this lock, and no second source open occurs here.
public final class DecoderInventoryStore: @unchecked Sendable {
    public static let shared = DecoderInventoryStore()
    private let lock = NSLock()
    private var inventory = DecoderInventory()
    private var nextHandle: UInt64 = 1
    public init() {}
    public func register(session: UInt64, kind: DecoderKind, codec: String,
                         sourceID: String, revisionAtOpen: UInt64) -> DecoderIdentity? {
        lock.lock(); defer { lock.unlock() }
        guard session != 0, revisionAtOpen != 0, !sourceID.isEmpty,
              nextHandle < UInt64.max else { return nil }
        let id=DecoderIdentity(session:session,handle:nextHandle)
        nextHandle += 1 // A refused attempt never allows handle reuse.
        guard inventory.register(id,kind:kind,codec:codec,sourceID:sourceID,
                                 revisionAtOpen:revisionAtOpen) == .registered else { return nil }
        return id
    }
    public func deregister(_ id: DecoderIdentity) {
        lock.lock(); defer { lock.unlock() }
        _ = inventory.deregister(id)
    }
    public func invalidateSession(_ session: UInt64) {
        lock.lock(); defer { lock.unlock() }
        inventory.invalidateSession(session)
    }
    public func snapshot(_ id: DecoderIdentity) -> DecoderSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return inventory.snapshot(id)
    }
    public func activeSnapshots(session: UInt64) -> [DecoderSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return inventory.activeSnapshots(session:session)
    }
}

extension DecoderInventoryStore {
    /// Lifecycle transition through the store lock: true only when the entry
    /// exists, its session is not invalidated, and its current lifecycle is
    /// not .closed. A transition out of .closed returns false and changes
    /// nothing. No callbacks run under the lock.
    @discardableResult
    public func mark(_ id: DecoderIdentity, _ lifecycle: DecoderLifecycle) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !inventory.invalidatedSessions.contains(id.session),
              let cur = inventory.entries[id], cur.lifecycle != .closed else { return false }
        inventory.mark(id, lifecycle)
        return true
    }
}

```

```text id=actual_run_log
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--6630B1A18289934C.txt
[7/14] Emitting module GorAVCore
[8/14] Compiling GorAVCore AdmissionTable.swift
[9/15] Compiling GorAVCore Boundary.swift
[10/16] Wrapping AST for GorAVCore for debugging
[12/20] Emitting module GorAVNativeProbeKit
[13/22] Compiling GorAVNativeProbeKit NativeProbe.swift
[14/22] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[15/22] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[16/22] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[17/22] Compiling GorAVNativeProbeKit LeaseTable.swift
[18/23] Wrapping AST for GorAVNativeProbeKit for debugging
[20/38] Emitting module GorAVPlaybackCore
[21/51] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[22/51] Compiling GorAVPlaybackCore PlayheadObservers.swift
[23/51] Compiling GorAVPlaybackCore PlayheadPosition.swift
[24/51] Compiling GorAVPlaybackCore PreparedAdoption.swift
[25/51] Compiling GorAVPlaybackCore PreparedShotSession.swift
[26/51] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[27/51] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[28/51] Compiling GorAVPlaybackCore RenderGraph.swift
[29/51] Compiling GorAVPlaybackCore SPSC.swift
[30/51] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[31/51] Compiling GorAVPlaybackCore StageGeometry.swift
[32/51] Compiling GorAVPlaybackCore TimingLedger.swift
[33/51] Compiling GorAVPlaybackCore UniformPacking.swift
[34/51] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[35/51] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[36/51] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[37/51] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[38/51] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[39/51] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[40/51] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[41/51] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[42/51] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[43/51] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[44/51] Compiling GorAVPlaybackCore Lane0Contract.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[45/51] Compiling GorAVPlaybackCore LifetimeRegistry.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[46/51] Compiling GorAVPlaybackCore PlayArguments.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[47/51] Compiling GorAVPlaybackCore PlaybackCore.swift
/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-314d1u5n/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[48/54] Wrapping AST for GorAVPlaybackCore for debugging
[50/54] Emitting module decoder_inventory_tests
[51/54] Compiling decoder_inventory_tests main.swift
[52/55] Wrapping AST for decoder-inventory-tests for debugging
[53/55] Write Objects.LinkFileList
[54/55] Linking decoder-inventory-tests
Build of product 'decoder-inventory-tests' complete! (6.90s)
decoder-inventory-tests: 36 PASS, 0 FAIL
```
