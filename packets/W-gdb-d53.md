# W-gdb-d53: 195b-53 follow-on: byte-owning backend behind the lease release hook

Row 195b-53 landed lease BOOKKEEPING: FrameLeaseStore calls one release hook on every release path, but nothing owns the bytes behind that hook. Write `RetainedPixelOwner`, a portable owner that holds the retained frame bytes by handle, frees them exactly once when the store's hook fires, and ledgers double and unknown releases. It must not read pixels on the render thread and must not touch the store lock. The decoder producer wiring and native/Metal pixels stay open.

Not in scope: native pixel retention, producer wiring in FFmpegSoftwareDecoder, GPU readback, any change to FrameLeaseStore or DecodedFrameTap source. Excerpts are verbatim lines from the pinned product sha; the first comment line of each block is a label added by the packet writer and is not part of the excerpt hash. Fixture blocks are new text proposed by this packet.

```packet-json
{
 "packet": "W-gdb-d53",
 "code_owner": "gdb gorav integrator (decoder lane), owner of Sources/GorAVPlaybackCore and Sources/GorAVFFmpegAdapter on gorav/engine",
 "scope": "implementation",
 "product_repo": "goreda/gorav",
 "product_branch": "engine",
 "product_sha": "8eaffc75b331a9d65ddce404266738a9d42043ed",
 "touched_files": [
  {
   "path": "Sources/GorAVPlaybackCore/FrameLeaseStore.swift",
   "excerpt_block": "ex_refusal",
   "lines": "34-64"
  },
  {
   "path": "Sources/GorAVPlaybackCore/FrameLeaseStore.swift",
   "excerpt_block": "ex_store_init",
   "lines": "136-150"
  },
  {
   "path": "Sources/GorAVPlaybackCore/DecodedFrameTap.swift",
   "excerpt_block": "ex_tap_attach",
   "lines": "73-78"
  },
  {
   "path": "Sources/GorAVPlaybackCore/DecodedFrameTap.swift",
   "excerpt_block": "ex_tap_offerleased",
   "lines": "145-191"
  },
  {
   "path": "Package.swift",
   "excerpt_block": "ex_pkg_target",
   "lines": "14-14"
  }
 ],
 "excerpt_sha256_8": {
  "ex_refusal": "78a2afbf",
  "ex_store_init": "921730ea",
  "ex_tap_attach": "21916ff7",
  "ex_tap_offerleased": "7370ffa0",
  "ex_pkg_target": "8c03081c"
 },
 "interface": {
  "signatures": "public final class RetainedPixelOwner: @unchecked Sendable { public init(session: UInt64); public func adopt(handle: UInt64, bytes: [UInt8]); public func abandon(handle: UInt64); public var releaseHook: (UInt64, UInt64) -> Void { get }; public func firstByte(handle: UInt64) -> UInt8?; public var liveHandles: [UInt64] { get }; public var releasedHandles: [UInt64] { get }; public var abandonedHandles: [UInt64] { get }; public var liveBytes: Int { get }; public var unknownReleases: Int { get }; public var doubleReleases: Int { get }; public var adoptedCount: Int { get } }. liveHandles, releasedHandles and abandonedHandles return handles sorted ascending by handle.",
  "types": "Handles and sessions are UInt64, the same values as NativeFrame.handle and NativeFrame.session. Bytes are stored as [UInt8]. The release hook type is (handle: UInt64, session: UInt64) -> Void, exactly the onRelease parameter of FrameLeaseStore.init.",
  "ownership_lifetime": "adopt moves the byte array into the owner under an NSLock. The caller adopts BEFORE offerLeased. If offerLeased returns refusedLease or any non-accepted verdict, the caller calls abandon(handle) to free the bytes. The store fires releaseHook exactly once per retained lease (immediately or after the last unpin), and the owner frees the bytes on that call and appends the handle to releasedHandles. A hook for a handle that was already freed increments doubleReleases; a hook for a handle never adopted increments unknownReleases; neither crashes. The hook is called without the store lock held, and the owner must never call back into the store.",
  "caller": "The decoder frame producer (future wiring, not in this packet) calls adopt then DecodedFrameTap.offerLeased(frame, clockNow:, seekGeneration:); frame-lease-tests style consumers read bytes through FrameLeaseStore.withPinnedAccess and owner.firstByte.",
  "callee": "RetainedPixelOwner implements only Foundation (NSLock, Array). It calls no GorAV API."
 },
 "test": {
  "command": "swift run retained-owner-tests",
  "expected": "Exit 0 and stdout ends with the line \"retained-owner-tests: 0 FAIL\" after 13 lines PASS O1 through PASS O13. Any FAIL line exits 1.",
  "fixture_block": "fx_retained_owner_tests",
  "note": "Run by the integrator on Linux with the pinned provider; a lab without the repo returns the patch and states \"unrun\"."
 },
 "target": {
  "branch": "lane/gdb-196p-decoder (integrator creates it from product_sha; never ohal/gorav main or PR 3)",
  "paths": [
   "Sources/GorAVPlaybackCore/RetainedFrameOwner.swift",
   "Sources/retained-owner-tests/main.swift",
   "Package.swift"
  ],
  "return_form": "full-files"
 }
}
```

## Excerpt ex_refusal

```swift id=ex_refusal
// Sources/GorAVPlaybackCore/FrameLeaseStore.swift lines 34-64 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
public enum FrameLeaseRefusal: Error, Equatable, Sendable {
    /// Frame session does not match the store's session.
    case foreignSession
    /// Store is closed; nothing can be retained, pinned, accessed or released.
    case storeClosed
    /// No live lease known for this handle (never retained, or already
    /// logically released by overflow/fence/close).
    case unknownLease
    /// Caller's or lease's seek generation is behind the store's fence.
    case staleGeneration(current: UInt64)
    /// Release or access of a lease that was already explicitly released.
    case alreadyReleased
    /// A lease for this handle is already outstanding (including one whose
    /// owner hook is still deferred behind pins).
    case duplicateLease
    /// Single frame exceeds the byte budget even when empty, or a negative
    /// byte count was claimed.
    case exceedsCapacity
    /// Overflow could not be resolved: every evictable candidate is pinned.
    case overflowBlockedByPins
    /// unpin without a matching outstanding pin.
    case notPinned
    /// The caller offered a frame without the generation the lease needs
    /// (produced by DecodedFrameTap's generation-less offer in lease mode).
    case generationRequired
}

public struct FrameLeaseCounters: Equatable, Sendable {
    public var retained = 0
    public var pinned = 0
    public var unpinned = 0
```

## Excerpt ex_store_init

```swift id=ex_store_init
// Sources/GorAVPlaybackCore/FrameLeaseStore.swift lines 136-150 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
    public init(session: UInt64, maxLeases: Int, maxBytes: Int,
                initialGeneration: UInt64 = 0,
                onRelease: @escaping (UInt64, UInt64) -> Void) {
        self.session = session
        self.maxLeases = max(1, maxLeases)
        self.maxBytes = max(1, maxBytes)
        self.generation = initialGeneration
        self.onRelease = onRelease
    }

    /// The only frame session this store serves (set at init).
    public var storeSession: UInt64 { session }
    public var outstandingCount: Int { lock.lock(); defer { lock.unlock() }; return leases.count }
    public var outstandingByteCount: Int { lock.lock(); defer { lock.unlock() }; return outstandingBytes }
    public var currentGeneration: UInt64 { lock.lock(); defer { lock.unlock() }; return generation }
```

## Excerpt ex_tap_attach

```swift id=ex_tap_attach
// Sources/GorAVPlaybackCore/DecodedFrameTap.swift lines 73-78 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
    public mutating func attachLeaseStore(_ store: FrameLeaseStore, byteEstimate: @escaping @Sendable (NativeFrame) -> Int) {
        precondition(store.storeSession == session, "lease store session must match the tap session")
        self.leaseStore = store
        self.byteEstimate = byteEstimate
    }

```

## Excerpt ex_tap_offerleased

```swift id=ex_tap_offerleased
// Sources/GorAVPlaybackCore/DecodedFrameTap.swift lines 145-191 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
    @discardableResult
    public mutating func offerLeased(_ frame: NativeFrame, clockNow: Double, seekGeneration: UInt64) -> Verdict {
        guard let store = leaseStore else { return offer(frame, clockNow: clockNow) }
        guard frame.session == session else {
            counters.refusedStaleSession += 1
            return .refusedStaleSession
        }
        if minInterval > 0, clockNow.isFinite, let last = lastAcceptClock, clockNow - last < minInterval {
            counters.droppedRateLimit += 1
            return .droppedRateLimit
        }
        switch store.retain(frame, bytes: byteEstimate?(frame) ?? 0, seekGeneration: seekGeneration) {
        case .failure(let refusal):
            counters.refusedLease += 1
            return .refusedLease(refusal)
        case .success:
            break
        }
        var verdict: Verdict = .accepted
        if queue.count >= capacity {
            let evicted = queue.removeFirst()
            counters.evictedOldest += 1
            verdict = .acceptedEvictingOldest
            // Bounded overflow logically releases the evicted frame's lease
            // (owner hook deferred while that lease is pinned).
            _ = store.release(evicted.handle)
        }
        queue.append(frame)
        newest = frame
        if clockNow.isFinite { lastAcceptClock = clockNow }
        counters.accepted += 1
        return verdict
    }

    /// Oldest queued frame (FIFO) for consumers like crop/live-depth/brightness.
    public mutating func next() -> NativeFrame? {
        queue.isEmpty ? nil : queue.removeFirst()
    }

    /// Newest accepted frame for the screenshot readback path. The caller
    /// copies pixels from the still-leased frame through its own hook; the
    /// tap returns stored identity and PTS only. It cannot vouch for lease validity,
    /// generation or freshness. The caller must check those before readback.
    public mutating func latestForReadback() -> NativeFrame? {
        if newest != nil { counters.readbacks += 1 }
        return newest
    }
```

## Excerpt ex_pkg_target

```swift id=ex_pkg_target
// Package.swift lines 14-14 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
        .executableTarget(name: "frame-lease-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/frame-lease-tests"),
```

## Fixture fx_retained_owner_tests

```swift id=fx_retained_owner_tests
import Foundation
import GorAVPlaybackCore
import GorAVNativeProbeKit

var failures = 0
func check(_ id: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + id + (ok || detail.isEmpty ? "" : " " + detail))
    if !ok { failures += 1 }
}
func frame(_ s: UInt64, _ h: UInt64) -> NativeFrame {
    NativeFrame(session: s, handle: h, pts: Int64(h), duration: 1, width: 2, height: 2,
                pixelFormatName: "fake", isKeyFrame: false)
}

let owner = RetainedPixelOwner(session: 7)
let store = FrameLeaseStore(session: 7, maxLeases: 8, maxBytes: 1024, onRelease: owner.releaseHook)
var tap = DecodedFrameTap(session: 7, capacity: 2, maxPerSecond: 0)
tap.attachLeaseStore(store, byteEstimate: { _ in 16 })

for h in 1...3 {
    owner.adopt(handle: UInt64(h), bytes: [UInt8](repeating: UInt8(h), count: 16))
    _ = tap.offerLeased(frame(7, UInt64(h)), clockNow: .nan, seekGeneration: 0)
}
check("O1 overflow released the oldest frame's bytes", owner.liveHandles == [2, 3] && owner.releasedHandles == [1])
check("O2 live bytes match the two retained frames", owner.liveBytes == 32)
check("O3 pinned access reads owner bytes without copying out of the owner",
      store.withPinnedAccess(3, seekGeneration: 0, { _ in owner.firstByte(handle: 3) }) == .success(3))

tap.fenceLeases(newGeneration: 1)
check("O4 seek fence released every older-generation lease", owner.liveHandles.isEmpty && owner.releasedHandles == [1, 2, 3])
check("O5 live bytes are zero after the fence", owner.liveBytes == 0)

owner.adopt(handle: 4, bytes: [UInt8](repeating: 4, count: 16))
let stale = tap.offerLeased(frame(7, 4), clockNow: .nan, seekGeneration: 0)
var staleRefused = false
if case .refusedLease(.staleGeneration) = stale { staleRefused = true }
check("O6 stale in-flight frame refused typed", staleRefused, "\(stale)")
check("O7 refused frame stays owner-held until abandon", owner.liveHandles == [4])
owner.abandon(handle: 4)
check("O8 abandon frees refused frame bytes", owner.liveHandles.isEmpty && owner.abandonedHandles == [4])

owner.adopt(handle: 5, bytes: [UInt8](repeating: 5, count: 16))
_ = tap.offerLeased(frame(7, 5), clockNow: .nan, seekGeneration: 1)
check("O9 current-generation frame retained", owner.liveHandles == [5])
tap.closeLeases()
check("O10 close released everything", owner.liveHandles.isEmpty && owner.releasedHandles == [1, 2, 3, 5])

owner.releaseHook(99, 7)
check("O11 unknown handle release is counted, not a crash", owner.unknownReleases == 1)
owner.releaseHook(5, 7)
check("O12 second release of a freed handle is counted as a double free", owner.doubleReleases == 1)
check("O13 ledger balances: adopted == released + abandoned + live",
      owner.adoptedCount == owner.releasedHandles.count + owner.abandonedHandles.count + owner.liveHandles.count)
print("retained-owner-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)

```

## Fixture fx_package_additions

```swift id=fx_package_additions
// Package.swift additions (two lines, same style as frame-lease-tests):
// in products: .executable(name: "retained-owner-tests", targets: ["retained-owner-tests"])
// in targets:  .executableTarget(name: "retained-owner-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/retained-owner-tests"),
```
