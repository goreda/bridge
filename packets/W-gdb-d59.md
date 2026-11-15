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
