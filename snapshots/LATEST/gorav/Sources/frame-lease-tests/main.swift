import Foundation
import GorAVPlaybackCore
import GorAVCore
import GorAVNativeProbeKit

// 195b-53 (review r2) witness: lease-ownership BOOKKEEPING for retained
// decoded frames. A portable fake owner records every bookkeeping release
// the store's ACTUAL code hands it; native pixel retention/readback is NOT
// claimed here (open work behind the owner's bookkeeping). Covers the r2
// review points: caller-supplied generations (no revival), refusal verdicts
// on retain failure, pin-based access that defers the owner hook, and
// honest bookkeeping labeling. Pure Swift, no FFmpeg, no network.

func check(_ id: String, _ condition: Bool, _ detail: String = "") {
    if condition { print("PASS \(id) \(detail)") } else { print("FAIL \(id) \(detail)"); exit(1) }
}

final class FakeLeaseOwner {
    private(set) var released: [(handle: UInt64, session: UInt64)] = []
    func makeStore(session: UInt64, maxLeases: Int, maxBytes: Int,
                   initialGeneration: UInt64 = 0) -> FrameLeaseStore {
        FrameLeaseStore(session: session, maxLeases: maxLeases, maxBytes: maxBytes,
                        initialGeneration: initialGeneration) { [weak self] handle, session in
            self?.released.append((handle, session))
        }
    }
}

func frame(_ session: UInt64, _ handle: UInt64, pts: Int64? = nil) -> NativeFrame {
    NativeFrame(session: session, handle: handle, pts: pts, duration: 1,
                width: 2, height: 2, pixelFormatName: "fake", isKeyFrame: false)
}

let owner = FakeLeaseOwner()

// L1: retain + pinned access roundtrip; nothing released; unpin pairs.
let s1 = owner.makeStore(session: 7, maxLeases: 4, maxBytes: 1000)
check("L1a", (try? s1.retain(frame(7, 1, pts: 10), bytes: 100, seekGeneration: 0).get()) == 1)
if case .success(let a) = s1.pin(1, seekGeneration: 0) {
    check("L1b", a.frame.pts == 10 && a.bytes == 100 && a.seekGeneration == 0)
} else { check("L1b", false, "pin refused") }
check("L1c", owner.released.isEmpty && s1.counters.retained == 1 && s1.counters.pinned == 1)
check("L1d", s1.unpin(1).map { _ in true } == .success(true) && s1.counters.unpinned == 1 && owner.released.isEmpty)

// L2: overflow eviction skips PINNED leases and releases the oldest unpinned.
let s2 = owner.makeStore(session: 7, maxLeases: 2, maxBytes: 1000)
_ = s2.retain(frame(7, 1), bytes: 10, seekGeneration: 0)
_ = s2.retain(frame(7, 2), bytes: 10, seekGeneration: 0)
_ = s2.pin(1, seekGeneration: 0)
_ = s2.retain(frame(7, 3), bytes: 10, seekGeneration: 0)
check("L2a", s2.outstandingCount == 2 && s2.counters.releasedOverflow == 1)
check("L2b", owner.released.suffix(1).map { $0.handle } == [2], "oldest UNPINNED lease evicted")
if case .success = s2.pin(1, seekGeneration: 0) {
    check("L2c", true, "pinned lease survives eviction")
} else { check("L2c", false, "pinned lease was evicted") }
check("L2d", s2.pin(2, seekGeneration: 0) == .failure(.unknownLease))

// L3: all candidates pinned -> overflow refuses typed; nothing evicted.
let s3before = owner.released.count
let s3 = owner.makeStore(session: 7, maxLeases: 1, maxBytes: 1000)
_ = s3.retain(frame(7, 1), bytes: 10, seekGeneration: 0)
_ = s3.pin(1, seekGeneration: 0)
check("L3a", s3.retain(frame(7, 2), bytes: 10, seekGeneration: 0) == .failure(.overflowBlockedByPins)
      && s3.counters.refusedPinnedOverflow == 1 && owner.released.count == s3before && s3.outstandingCount == 1)
// byte overflow still works against unpinned leases.
let s3b = owner.makeStore(session: 7, maxLeases: 8, maxBytes: 100)
_ = s3b.retain(frame(7, 1), bytes: 60, seekGeneration: 0)
_ = s3b.retain(frame(7, 2), bytes: 60, seekGeneration: 0)
check("L3b", s3b.counters.releasedOverflow == 1 && s3b.outstandingByteCount == 60)
check("L3c", s3b.retain(frame(7, 3), bytes: 150, seekGeneration: 0) == .failure(.exceedsCapacity)
      && s3b.counters.refusedCapacity == 1)

// L4: foreign session refused, nothing stored or released.
let s4 = owner.makeStore(session: 7, maxLeases: 4, maxBytes: 1000)
check("L4", s4.retain(frame(8, 1), bytes: 10, seekGeneration: 0) == .failure(.foreignSession)
      && s4.counters.refusedForeign == 1 && s4.outstandingCount == 0)

// L5: caller-supplied stale generation at birth is refused (review r1: no
// revival under the store's current generation).
let s5 = owner.makeStore(session: 7, maxLeases: 4, maxBytes: 1000, initialGeneration: 5)
check("L5", s5.retain(frame(7, 1), bytes: 10, seekGeneration: 4) == .failure(.staleGeneration(current: 5))
      && s5.counters.refusedStale == 1)

// L6: fence logically releases older leases; a PINNED one's owner hook is
// deferred to the last unpin (review r3).
let s6 = owner.makeStore(session: 7, maxLeases: 8, maxBytes: 1000, initialGeneration: 5)
let beforeFence = owner.released.count
_ = s6.retain(frame(7, 1), bytes: 10, seekGeneration: 5)
_ = s6.retain(frame(7, 2), bytes: 10, seekGeneration: 5)
_ = s6.pin(1, seekGeneration: 5)
s6.fence(newGeneration: 6)
check("L6a", s6.counters.releasedFence == 2 && s6.outstandingCount == 0, "both leases logically fenced")
check("L6b", owner.released.count == beforeFence + 1 && owner.released.last?.handle == 2,
      "unpinned hook delivered, pinned hook deferred")
check("L6c", s6.counters.releaseDeferred == 1)
check("L6d", s6.pin(1, seekGeneration: 6) == .failure(.unknownLease), "logically released: no new access")
check("L6e", s6.pin(1, seekGeneration: 5) == .failure(.staleGeneration(current: 6)))
check("L6f", s6.unpin(1).map { _ in true } == .success(true) && owner.released.count == beforeFence + 2,
      "last unpin drains the deferred hook")

// L7: explicit release while pinned defers the hook; double release refused.
let s7 = owner.makeStore(session: 7, maxLeases: 4, maxBytes: 1000)
_ = s7.retain(frame(7, 1), bytes: 10, seekGeneration: 0)
_ = s7.pin(1, seekGeneration: 0)
let s7before = owner.released.count
check("L7a", s7.release(1).map { _ in true } == .success(true), "logical release while pinned")
check("L7b", owner.released.count == s7before && s7.counters.releaseDeferred == 1, "hook deferred")
check("L7c", s7.release(1).map { _ in true } == .failure(.alreadyReleased) && s7.counters.refusedDoubleRelease == 1)
check("L7d", s7.unpin(1).map { _ in true } == .success(true) && owner.released.count == s7before + 1, "unpin drains hook")
check("L7e", s7.release(99).map { _ in true } == .failure(.unknownLease))

// L8: close (cancellation path) logically releases everything; pins stay
// drainable; later ops refuse closed.
let s8 = owner.makeStore(session: 7, maxLeases: 4, maxBytes: 1000)
_ = s8.retain(frame(7, 1), bytes: 10, seekGeneration: 0)
_ = s8.retain(frame(7, 2), bytes: 10, seekGeneration: 0)
_ = s8.pin(1, seekGeneration: 0)
let s8before = owner.released.count
s8.close()
check("L8a", s8.counters.releasedClose == 2 && s8.outstandingCount == 0)
check("L8b", owner.released.count == s8before + 1, "pinned close defers one hook")
check("L8c", s8.retain(frame(7, 3), bytes: 10, seekGeneration: 0) == .failure(.storeClosed)
      && s8.pin(1, seekGeneration: 0) == .failure(.storeClosed))
check("L8d", s8.unpin(1).map { _ in true } == .success(true) && owner.released.count == s8before + 2,
      "pins drain after close")

// L9: unpin without a pin is a typed refusal.
let s9 = owner.makeStore(session: 7, maxLeases: 4, maxBytes: 1000)
_ = s9.retain(frame(7, 1), bytes: 10, seekGeneration: 0)
check("L9a", s9.unpin(1).map { _ in true } == .failure(.notPinned) && s9.counters.refusedNotPinned == 1)
check("L9b", s9.unpin(99).map { _ in true } == .failure(.unknownLease))

// L10: withPinnedAccess scopes the pin; a release right after fires at once.
let s10 = owner.makeStore(session: 7, maxLeases: 4, maxBytes: 1000)
_ = s10.retain(frame(7, 1, pts: 42), bytes: 10, seekGeneration: 0)
let seen = s10.withPinnedAccess(1, seekGeneration: 0) { $0.frame.pts ?? -1 }
let s10before = owner.released.count
check("L10a", seen == .success(42))
check("L10b", s10.counters.pinned == 1 && s10.counters.unpinned == 1)
_ = s10.release(1)
check("L10c", owner.released.count == s10before + 1, "no deferral after scoped pin drained")

// L11: hook deliveries are exact: every logical release fires exactly once.
let s11before = owner.released.filter { $0.handle == 1 }.count
let s11 = owner.makeStore(session: 7, maxLeases: 4, maxBytes: 1000)
_ = s11.retain(frame(7, 1), bytes: 10, seekGeneration: 0)
_ = s11.pin(1, seekGeneration: 0)
_ = s11.release(1)
_ = s11.unpin(1)
check("L11", s11.counters.hookDelivered == 1 && owner.released.filter { $0.handle == 1 }.count == s11before + 1)

// L12: tap in lease mode (review r1/r2): caller-supplied generation decides;
// retain failure refuses and is NOT queued; generation-less offer refuses.
let tapOwner = FakeLeaseOwner()
let tapStore = tapOwner.makeStore(session: 7, maxLeases: 8, maxBytes: 1000)
var tap = DecodedFrameTap(session: 7, capacity: 2, maxPerSecond: 0)
tap.attachLeaseStore(tapStore) { _ in 4 }
check("L12a", tap.offerLeased(frame(7, 1), clockNow: 1.0, seekGeneration: 0) == .accepted)
check("L12b", tap.offerLeased(frame(7, 2), clockNow: 2.0, seekGeneration: 0) == .accepted)
check("L12c", tap.offerLeased(frame(7, 3), clockNow: 3.0, seekGeneration: 0) == .acceptedEvictingOldest
      && tapOwner.released.suffix(1).map { $0.handle } == [1], "overflow eviction releases evicted lease")
check("L12d", tapStore.outstandingCount == 2 && (tap.leaseCounters?.retained ?? 0) == 3)
let depthBeforeStale = tap.depth
tap.fenceLeases(newGeneration: 1)
check("L12e", tap.offerLeased(frame(7, 9), clockNow: 4.0, seekGeneration: 0) == .refusedLease(.staleGeneration(current: 1))
      && tap.depth == depthBeforeStale && tap.counters.refusedLease == 1,
      "stale in-flight frame refuses and is not queued (no revival)")
check("L12f", tap.offer(frame(7, 10), clockNow: 5.0) == .refusedLease(.generationRequired)
      && tap.depth == depthBeforeStale && tap.counters.refusedLease == 2,
      "generation-less offer refuses in lease mode")
check("L12g", tap.offerLeased(frame(8, 9), clockNow: 6.0, seekGeneration: 1) == .refusedStaleSession
      && tapStore.outstandingCount == 0, "foreign session never reaches the store")
tap.closeLeases()
check("L12h", tapOwner.released.map { $0.handle }.sorted() == [1, 2, 3],
      "eviction + fence released exactly the three accepted frames; close adds none")

// L13: metadata-only taps are unchanged: no store, same verdicts, nil counters.
var plain = DecodedFrameTap(session: 1, capacity: 1, maxPerSecond: 0)
check("L13a", plain.offer(frame(1, 1), clockNow: .nan) == .accepted)
check("L13b", plain.offer(frame(1, 2), clockNow: .nan) == .acceptedEvictingOldest)
check("L13c", plain.leaseCounters == nil && plain.releaseLease(1) == nil)
check("L13d", plain.offerLeased(frame(1, 3), clockNow: .nan, seekGeneration: 0) == .acceptedEvictingOldest,
      "offerLeased degrades to plain offer without a store")

print("frame-lease-tests: all checks passed")

// Integrator: overflow-safe arithmetic, future generations, pinned physical budget.
let huge = FrameLeaseStore(session: 7, maxLeases: 2, maxBytes: Int.max) { _,_ in }
_ = huge.retain(frame(7, 1), bytes: Int.max, seekGeneration: 0)
check("I1", huge.retain(frame(7, 2), bytes: 1, seekGeneration: 0) == .success(2))
check("I2", huge.retain(frame(7, 3), bytes: 1, seekGeneration: 1) == .failure(.staleGeneration(current: 0)))
let pending = FrameLeaseStore(session: 7, maxLeases: 1, maxBytes: 10) { _,_ in }
_ = pending.retain(frame(7, 1), bytes: 10, seekGeneration: 0)
_ = pending.pin(1, seekGeneration: 0)
pending.fence(newGeneration: 1)
check("I3", pending.retain(frame(7, 2), bytes: 1, seekGeneration: 1) == .failure(.overflowBlockedByPins))
_ = pending.unpin(1)
check("I4", pending.retain(frame(7, 2), bytes: 1, seekGeneration: 1) == .success(2))
var reentrant: FrameLeaseStore!
var refusedReentrant = false
reentrant = FrameLeaseStore(session: 7, maxLeases: 1, maxBytes: 10) { handle,_ in
    refusedReentrant = reentrant.retain(frame(7, handle), bytes: 1, seekGeneration: 0) == .failure(.duplicateLease)
}
_ = reentrant.retain(frame(7, 1), bytes: 1, seekGeneration: 0)
_ = reentrant.release(1)
check("I5", refusedReentrant, "handle reserved until owner hook returns")
print("integrator lease regressions: 5 PASS")

// 195b-53 (r3) witness: the bridge connects the ACTUAL producer contract
// (LocalVideoDecoder, C1) to the lease lifecycle. The fake decoder records
// every releaseFrame the bridge's ACTUAL code dispatches; async releases are
// awaited by polling the recorder. No FFmpeg, no pixels, no network.

final class FakeBridgeDecoder: LocalVideoDecoder, @unchecked Sendable {
    let interruptCapability: InterruptCapability = .none
    private let recorder = ReleaseRecorder()
    var released: [UInt64] { recorder.all() }
    func open(source: SourceDescriptor, session: SessionID) async throws {}
    func nextEvent(session: SessionID) async -> DecodeEvent? { nil }
    func releaseFrame(handle: UInt64, session: SessionID) async { recorder.record(handle) }
    func requestInterrupt(session: SessionID) {}
    func close(session: SessionID) async {}
}

/// Sync recorder so the async protocol surface never locks across an await.
final class ReleaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var handles: [UInt64] = []
    func record(_ handle: UInt64) { lock.lock(); handles.append(handle); lock.unlock() }
    func all() -> [UInt64] { lock.lock(); defer { lock.unlock() }; return handles }
}

func waitUntil(_ label: String, _ cond: () -> Bool) async {
    for _ in 0..<2000 {
        if cond() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    print("FAIL \(label) (timeout)"); exit(1)
}

let bDecoder = FakeBridgeDecoder()
let bSession = SessionID(uncheckedEpoch: 7)
let bridge = DecodedFrameLeaseBridge(session: 7, maxLeases: 2, maxBytes: 1000,
                                     decoder: bDecoder, decoderSession: bSession) { _ in 4 }

// B1: retained frames are NOT released to the decoder while leased.
check("B1a", bridge.decoded(frame(7, 1), seekGeneration: 0) == .success(1))
check("B1b", bridge.decoded(frame(7, 2), seekGeneration: 0) == .success(2))
try? await Task.sleep(nanoseconds: 20_000_000)
check("B1c", bDecoder.released.isEmpty, "no decoder release while leases are live")

// B2: bounded overflow evicts the oldest lease and drives the decoder's real
// releaseFrame for exactly the evicted handle.
check("B2a", bridge.decoded(frame(7, 3), seekGeneration: 0) == .success(3))
await waitUntil("B2b") { bDecoder.released == [1] }
check("B2c", bridge.store.outstandingCount == 2, "budget holds after overflow release")

// B3: seek fence releases old-generation leases to the decoder; a stale
// in-flight frame refuses AND is released at once (fail closed, C1), counted.
bridge.advanceSeekGeneration(1)
await waitUntil("B3a") { bDecoder.released.sorted() == [1, 2, 3] }
check("B3b", bridge.decoded(frame(7, 9), seekGeneration: 0) == .failure(.staleGeneration(current: 1)))
await waitUntil("B3c") { bDecoder.released.contains(9) }
check("B3d", bridge.store.outstandingCount == 0, "stale frame never retained")

// B4: a pinned lease defers the decoder release until the last unpin.
check("B4a", bridge.decoded(frame(7, 4), seekGeneration: 1) == .success(4))
guard case .success = bridge.store.pin(4, seekGeneration: 1) else { print("FAIL B4b"); exit(1) }
bridge.advanceSeekGeneration(2)
try? await Task.sleep(nanoseconds: 20_000_000)
check("B4c", !bDecoder.released.contains(4), "pinned lease survives the fence")
check("B4d", { if case .success = bridge.store.unpin(4) { return true }; return false }())
await waitUntil("B4e") { bDecoder.released.contains(4) }

// B5: duplicate handle refuses typed and is released to the decoder at once;
// the outstanding lease for that handle is untouched.
check("B5a", bridge.decoded(frame(7, 5), seekGeneration: 2) == .success(5))
check("B5b", bridge.decoded(frame(7, 5), seekGeneration: 2) == .failure(.duplicateLease))
await waitUntil("B5c") { bDecoder.released.filter { $0 == 5 }.count == 1 }
check("B5d", bridge.store.pin(5, seekGeneration: 2) != .failure(.unknownLease), "original lease still live")
check("B5e", { if case .success = bridge.store.unpin(5) { return true }; return false }())

// B6: a foreign-session frame refuses WITHOUT a decoder release (not ours).
check("B6a", bridge.decoded(frame(8, 1), seekGeneration: 2) == .failure(.foreignSession))
try? await Task.sleep(nanoseconds: 20_000_000)
check("B6b", !bDecoder.released.contains(1) || bDecoder.released.filter { $0 == 1 }.count == 1,
      "foreign handle never released to this decoder")

// B7: close releases every outstanding lease to the decoder and reports exact
// counts; a lease pinned at close is named and still released at unpin (C1
// past close). Bridge here: handle 5 outstanding + handle 6 pinned.
check("B7a", bridge.decoded(frame(7, 6), seekGeneration: 2) == .success(6))
guard case .success = bridge.store.pin(6, seekGeneration: 2) else { print("FAIL B7b"); exit(1) }
let report = await bridge.close()
check("B7c", report.retainedTotal == 6, "frames 1,2,3,4,5,6 retained; 8 foreign, 9 stale refused")
await waitUntil("B7d") { bDecoder.released.contains(5) }
check("B7e", report.deferredPinnedHandles == [6], "pinned-at-close lease named")
check("B7f", report.undrainedDecoderReleases == 0, "drain completed inside budget")
check("B7g", report.hookDeliveredTotal == report.retainedTotal - report.deferredPinnedHandles.count,
      "every non-deferred retained lease delivered its hook exactly once")
try? await Task.sleep(nanoseconds: 20_000_000)
check("B7h", !bDecoder.released.contains(6), "still pinned: no decoder release yet")
check("B7i", { if case .success = bridge.store.unpin(6) { return true }; return false }())
await waitUntil("B7j") { bDecoder.released.contains(6) }
let report2 = await bridge.close()
check("B7k", report2 == report, "close is idempotent, first report latched")
check("B7l", bDecoder.released.sorted() == [1, 2, 3, 4, 5, 5, 6, 9],
      "C1: every session-7 handle the bridge saw is released exactly once (5 twice: refusal + lease)")

print("bridge lease witness: all checks passed")

// 195b-53 (r3b) witness: the SAME bridge feeding the row's named tap FIFO.
// Every frame the tap does not retain - rate drop, stale, refusal - is still
// released to the decoder (C1 counts drops, not only refusals).
let tDecoder = FakeBridgeDecoder()
let tBridge = DecodedFrameLeaseBridge(session: 11, maxLeases: 8, maxBytes: 1000,
                                      decoder: tDecoder, decoderSession: SessionID(uncheckedEpoch: 11)) { _ in 4 }
tBridge.attachTap(capacity: 2, maxPerSecond: 5)   // min interval 0.2 s

func tframe(_ handle: UInt64) -> NativeFrame { frame(11, handle) }

// C1: accepted frames queue in the FIFO and are not released.
check("C1a", tBridge.decodedThroughTap(tframe(1), clockNow: 1.0, seekGeneration: 0) == .accepted)
check("C1b", tBridge.decodedThroughTap(tframe(2), clockNow: 1.3, seekGeneration: 0) == .accepted)
check("C1c", tBridge.tapDepth == 2)
try? await Task.sleep(nanoseconds: 20_000_000)
check("C1d", tDecoder.released.isEmpty)

// C2: FIFO eviction drives the decoder release of exactly the evicted frame.
check("C2a", tBridge.decodedThroughTap(tframe(3), clockNow: 1.6, seekGeneration: 0) == .acceptedEvictingOldest)
await waitUntil("C2b") { tDecoder.released == [1] }
check("C2c", tBridge.tapDepth == 2)

// C3: a rate-limited frame is dropped by the tap AND released to the decoder
// at once - a tap drop is never a decoder-side leak.
check("C3a", tBridge.decodedThroughTap(tframe(4), clockNow: 1.7, seekGeneration: 0) == .droppedRateLimit)
await waitUntil("C3b") { tDecoder.released.contains(4) }
check("C3c", tBridge.tapDepth == 2)

// C4: stale in-flight frame refuses and is released; FIFO untouched.
tBridge.advanceSeekGeneration(1)
await waitUntil("C4a") { tDecoder.released.sorted() == [1, 2, 3, 4] }   // eviction 1, rate drop 4, fence 2+3
check("C4b", tBridge.decodedThroughTap(tframe(9), clockNow: 2.0, seekGeneration: 0) == .refusedLease(.staleGeneration(current: 1)))
await waitUntil("C4c") { tDecoder.released.contains(9) }
check("C4d", tBridge.tapDepth == 2 && tBridge.store.outstandingCount == 0,
      "fenced frames keep FIFO metadata only; their leases are gone (readback must pin-check)")

// C5: FIFO consumer + readback path ride the same leases.
check("C5a", tBridge.decodedThroughTap(tframe(5), clockNow: 3.0, seekGeneration: 1) == .acceptedEvictingOldest)
check("C5b", tBridge.latestForReadback()?.handle == 5)
if let latest = tBridge.latestForReadback() {
    let access = tBridge.store.withPinnedAccess(latest.handle, seekGeneration: 1) { $0.bytes }
    check("C5c", access == .success(4), "readback pins the newest lease")
} else { check("C5c", false) }
check("C5d", tBridge.nextQueuedFrame()?.handle == 3 && tBridge.tapDepth == 1,
      "FIFO consumer gets the oldest entry even when its lease was fenced; the pin check is the guard")

// C6: close after tap-fed traffic still releases every retained frame.
check("C6a", tBridge.decodedThroughTap(tframe(6), clockNow: 3.5, seekGeneration: 1) == .accepted)
let tReport = await tBridge.close()
await waitUntil("C6b") { tDecoder.released.sorted() == [1, 2, 3, 4, 5, 6, 9] }
check("C6c", tReport.retainedTotal == 5 && tReport.unretainedReleasedTotal == 2 && tReport.undrainedDecoderReleases == 0)

print("tap-bridge witness: all checks passed")
