import Foundation
import GorAVCore
import GorAVNativeProbeKit

// 195b-53 (r3): connect the ACTUAL decoded-frame producer to the lease-owning
// store. The producer is any LocalVideoDecoder emitting DecodeEvent.frameDecoded;
// its contract C1 says every delivered frame handle is released exactly once.
// This bridge makes the lease lifecycle that one release path:
//
//  - decoded(): a same-session frame is retained in the store under the
//    CALLER-SUPPLIED seek generation. A frame the store refuses (stale
//    generation, duplicate, capacity, closed) is released back to the
//    decoder AT ONCE (fail closed: never held untracked) and counted.
//  - Overflow eviction, seek-generation fence and close all release leases
//    through the store's ONE owner hook; the hook dispatches the decoder's
//    real releaseFrame. While a lease is pinned the hook is deferred to the
//    last unpin, so a consumer's handle stays valid against concurrent
//    release/seek/close.
//  - A foreign-session frame is refused WITHOUT a decoder release: it belongs
//    to another session's producer, never to this bridge.
//  - close() is async: it closes the store, then bounds-drains the in-flight
//    async decoder releases and reports exact counts. Leases still pinned at
//    close are named (deferredPinnedHandles); their decoder release still
//    fires at the last unpin, so C1 holds past close.
//
// Scope honesty: this is ownership of decoder handles only. No render-thread
// readback, no pixel bytes, no native retention claim - the decoder backend
// behind releaseFrame keeps its own native business. The portable fake
// decoder in frame-lease-tests rides this ACTUAL bridge code.

public final class DecodedFrameLeaseBridge: @unchecked Sendable {

    /// Counts and identities at close. hookDeliveredTotal counts every store
    /// hook fire (overflow + fence + close + explicit release); deferred
    /// handles' hooks fire later, at their last unpin.
    public struct CloseReport: Equatable, Sendable {
        public var retainedTotal = 0
        public var hookDeliveredTotal = 0
        /// Same-session frames the store refused; released to the decoder at once.
        public var unretainedReleasedTotal = 0
        /// Leases still pinned at close; decoder release fires at last unpin.
        public var deferredPinnedHandles: [UInt64] = []
        /// Async decoder releases still in flight when the bounded drain ended.
        public var undrainedDecoderReleases = 0
        public init() {}
    }

    /// The consumer side: pin/access/release/fence ride this actual store.
    public let store: FrameLeaseStore
    /// The only frame session this bridge serves (== store.storeSession).
    public var session: UInt64 { store.storeSession }

    /// Optional tap FIFO (the row's named abstraction): when attached, the
    /// producer feeds the tap and the tap retains into this same store, so
    /// the FIFO's eviction, rate limiting and readback all ride the lease
    /// lifecycle. Lock-guarded; attach before the first frame.
    private var tap: DecodedFrameTap?

    private let decoder: any LocalVideoDecoder
    private let decoderSession: SessionID
    private let byteEstimate: @Sendable (NativeFrame) -> Int

    private let lock = NSLock()
    /// Retained handles whose owner hook has not fired yet. After close()
    /// this is exactly the pin-deferred set.
    private var unhookedHandles: Set<UInt64> = []
    private var inFlightDecoderReleases = 0
    private var retainedTotal = 0
    private var unretainedReleasedTotal = 0
    private var latchedReport: CloseReport?

    public init(session: UInt64, maxLeases: Int, maxBytes: Int,
                initialGeneration: UInt64 = 0,
                decoder: any LocalVideoDecoder, decoderSession: SessionID,
                byteEstimate: @escaping @Sendable (NativeFrame) -> Int = { _ in 0 }) {
        self.decoder = decoder
        self.decoderSession = decoderSession
        self.byteEstimate = byteEstimate
        // The store's one owner hook is the decoder-release dispatch. It is
        // wired through a box because the store must exist before self is
        // complete; the box is filled in this same init before any retain
        // can happen, so the hook never fires unwired.
        let box = HookBox()
        store = FrameLeaseStore(session: session, maxLeases: maxLeases, maxBytes: maxBytes,
                                initialGeneration: initialGeneration) { handle, _ in
            box.fire(handle)
        }
        // Bookkeeping rides the (weak) bridge; the decoder release itself is
        // captured strongly, so contract C1 holds even if the bridge is
        // deallocated with leases outstanding (no retain cycle: the decoder
        // never points back at the bridge).
        box.body = { [weak self, decoder, decoderSession] handle in
            if let self {
                self.dispatchHook(handle)
            } else {
                Task { await decoder.releaseFrame(handle: handle, session: decoderSession) }
            }
        }
    }

    /// Indirection used only during init (see above).
    private final class HookBox: @unchecked Sendable {
        var body: ((UInt64) -> Void)?
        func fire(_ handle: UInt64) { body?(handle) }
    }

    /// Store hook: mark the handle hooked, then dispatch the decoder's real
    /// releaseFrame (async; the in-flight count is drained by close()).
    private func dispatchHook(_ handle: UInt64) {
        lock.lock()
        unhookedHandles.remove(handle)
        lock.unlock()
        dispatchDecoderRelease(handle)
    }

    /// Attach the tap FIFO (capacity >= 1; maxPerSecond <= 0 = no rate
    /// limit). One tap per bridge; after this, producers may call
    /// decodedThroughTap. The tap retains into this bridge's store, so tap
    /// eviction and bridge-side fence/close share one release path.
    public func attachTap(capacity: Int, maxPerSecond: Double) {
        lock.lock(); defer { lock.unlock() }
        precondition(tap == nil, "one tap per bridge")
        var newTap = DecodedFrameTap(session: session, capacity: capacity, maxPerSecond: maxPerSecond)
        newTap.attachLeaseStore(store, byteEstimate: byteEstimate)
        tap = newTap
    }

    /// Number of frames queued in the tap FIFO (0 when no tap is attached).
    public var tapDepth: Int { lock.lock(); defer { lock.unlock() }; return tap?.depth ?? 0 }

    /// Oldest queued frame for FIFO consumers; nil without a tap.
    public func nextQueuedFrame() -> NativeFrame? {
        lock.lock(); defer { lock.unlock() }; return tap?.next()
    }

    /// Newest accepted frame for the screenshot readback path; the caller
    /// pins through store.withPinnedAccess before touching pixels.
    public func latestForReadback() -> NativeFrame? {
        lock.lock(); defer { lock.unlock() }; return tap?.latestForReadback()
    }

    /// Producer path through the tap: the tap's verdict is returned verbatim
    /// and EVERY frame the tap did not retain - rate-limit drop, stale
    /// generation, generation-less contract violation, capacity refusal - is
    /// released back to the decoder at once (contract C1 counts frames the
    /// tap drops, not only frames it refuses). Foreign-session frames are
    /// refused WITHOUT a decoder release, as in decoded().
    @discardableResult
    public func decodedThroughTap(_ frame: NativeFrame, clockNow: Double,
                                  seekGeneration: UInt64) -> DecodedFrameTap.Verdict {
        guard frame.session == session else { return .refusedStaleSession }
        // The tap is mutated OUTSIDE the bridge lock: a tap eviction releases
        // through the store, whose hook re-enters the bridge (dispatchHook)
        // synchronously - holding the lock across offerLeased would deadlock.
        // Producers are serialized per session, and attachTap is attach-once,
        // so the copy-out/mutate/write-back below cannot lose tap state.
        lock.lock()
        guard var activeTap = tap else { lock.unlock(); return .refusedLease(.generationRequired) }
        lock.unlock()
        let verdict = activeTap.offerLeased(frame, clockNow: clockNow, seekGeneration: seekGeneration)
        lock.lock()
        if tap != nil { tap = activeTap }
        switch verdict {
        case .accepted, .acceptedEvictingOldest:
            unhookedHandles.insert(frame.handle)
            retainedTotal += 1
            lock.unlock()
        case .droppedRateLimit, .refusedLease:
            unretainedReleasedTotal += 1
            lock.unlock()
            dispatchDecoderRelease(frame.handle)
        case .refusedStaleSession:
            lock.unlock() // unreachable: guarded above; kept for enum exhaustion
        }
        return verdict
    }

    /// One decoded frame from the producer, under the caller's seek
    /// generation (never stamped by the bridge: a stale in-flight frame must
    /// refuse, not be revived under the current generation).
    @discardableResult
    public func decoded(_ frame: NativeFrame, seekGeneration: UInt64) -> Result<UInt64, FrameLeaseRefusal> {
        guard frame.session == session else { return .failure(.foreignSession) }
        switch store.retain(frame, bytes: byteEstimate(frame), seekGeneration: seekGeneration) {
        case .success(let handle):
            lock.lock()
            unhookedHandles.insert(handle)
            retainedTotal += 1
            lock.unlock()
            return .success(handle)
        case .failure(let refusal):
            // Fail closed: a frame this session produced that cannot be
            // retained is released to the decoder immediately (contract C1),
            // never queued, never held untracked.
            lock.lock()
            unretainedReleasedTotal += 1
            lock.unlock()
            dispatchDecoderRelease(frame.handle)
            return .failure(refusal)
        }
    }

    /// Seek-generation fence: leases from older generations are logically
    /// released and their decoder releases dispatched (deferred behind pins).
    public func advanceSeekGeneration(_ newGeneration: UInt64) {
        store.fence(newGeneration: newGeneration)
    }

    /// Close the store and bound-drain in-flight async decoder releases.
    /// Idempotent: the first report is latched and replayed. Leases pinned at
    /// close are named; their decoder release fires at their last unpin even
    /// after this returns (the hook stays live).
    @discardableResult
    public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
        lock.lock()
        if let report = latchedReport { lock.unlock(); return report }
        lock.unlock()

        store.close()

        let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
        while true {
            lock.lock()
            let inFlight = inFlightDecoderReleases
            lock.unlock()
            if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        lock.lock()
        var report = CloseReport()
        report.retainedTotal = retainedTotal
        report.hookDeliveredTotal = store.counters.hookDelivered
        report.unretainedReleasedTotal = unretainedReleasedTotal
        report.deferredPinnedHandles = unhookedHandles.sorted()
        report.undrainedDecoderReleases = inFlightDecoderReleases
        latchedReport = report
        lock.unlock()
        return report
    }

    /// Immediate decoder release for a frame the bridge never retained.
    /// Tracked in the same in-flight count so close() drains it too.
    private func dispatchDecoderRelease(_ handle: UInt64) {
        lock.lock()
        inFlightDecoderReleases += 1
        lock.unlock()
        let decoder = self.decoder, session = self.decoderSession
        Task {
            await decoder.releaseFrame(handle: handle, session: session)
            self.lock.lock()
            self.inFlightDecoderReleases -= 1
            self.lock.unlock()
        }
    }
}
