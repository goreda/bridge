import Foundation
import GorAVNativeProbeKit

// R5 (arch-195b): metadata bookkeeping only, not a pixel tap or readback.
// A handle here is not proof of live pixels. Consumes frame metadata OFF
// the render path: bounded FIFO with explicit overflow policy, rate limiting,
// per-session fencing, and a latest-frame readback for screenshots. Every
// decision is receipt-counted; nothing is dropped silently. Pixel bytes are
// never retained here - the tap carries the lease identity + metadata, and
// readback copies happen through the caller's hook against the live lease.
//
// 195b-53 (review r2): with a FrameLeaseStore attached the tap also does
// lease-ownership BOOKKEEPING: accepted frames are retained in the store
// under the CALLER-SUPPLIED seek generation (offerLeased), FIFO overflow
// evictions logically release the evicted frame's lease, and seek
// generations are fenced by the store. The store's hook is a bookkeeping
// notification only - no native pixel retention is claimed here. With no
// store attached (default) every verdict, counter and ordering is exactly
// as before: the lease plumbing is strictly additive and the metadata-only
// mode stays valid. The plain generation-less offer REFUSES in lease mode
// (generationRequired): an in-flight frame must never be revived under the
// store's current generation.

public struct DecodedFrameTap: Sendable {

    public enum Verdict: Equatable, Sendable {
        case accepted
        /// Within the rate budget: frame refused, not queued.
        case droppedRateLimit
        /// Queue full: the OLDEST queued frame was evicted to keep the tap live.
        case acceptedEvictingOldest
        /// Frame carries a session/generation this tap no longer serves.
        case refusedStaleSession
        /// 195b-53: a lease operation failed or the lease mode contract was
        /// violated (generation-less offer with a store attached). The frame
        /// was NOT queued.
        case refusedLease(FrameLeaseRefusal)
    }

    public struct Counters: Equatable, Sendable {
        public var accepted = 0
        public var droppedRateLimit = 0
        public var evictedOldest = 0
        public var refusedStaleSession = 0
        public var refusedLease = 0
        public var readbacks = 0
        public init() {}
    }

    public private(set) var counters = Counters()
    private let capacity: Int
    private let minInterval: Double
    private var queue: [NativeFrame] = []
    private var lastAcceptClock: Double?
    private var newest: NativeFrame?
    /// The session this tap serves; frames from any other session are refused.
    public let session: UInt64
    /// 195b-53: optional lease-ownership bookkeeping store. Nil keeps the
    /// metadata-only behavior unchanged; the two never mix within one tap.
    private var leaseStore: FrameLeaseStore?
    private var byteEstimate: (@Sendable (NativeFrame) -> Int)?

    /// capacity >= 1; maxPerSecond <= 0 means no rate limit.
    public init(session: UInt64, capacity: Int, maxPerSecond: Double) {
        self.session = session
        self.capacity = max(1, capacity)
        self.minInterval = maxPerSecond > 0 ? 1.0 / maxPerSecond : 0
    }

    /// Attach the lease bookkeeping store. Only valid before the first
    /// offer; the store's session must match the tap's. Frames offered
    /// before attachment are NOT backfilled (no byte accounting).
    public mutating func attachLeaseStore(_ store: FrameLeaseStore, byteEstimate: @escaping @Sendable (NativeFrame) -> Int) {
        precondition(store.storeSession == session, "lease store session must match the tap session")
        self.leaseStore = store
        self.byteEstimate = byteEstimate
    }

    /// Lease counters of the attached store, nil in metadata-only mode.
    public var leaseCounters: FrameLeaseCounters? { leaseStore?.counters }

    /// Explicit logical release of one retained lease (typed refusals on
    /// stale or unknown handles; pinned leases defer the owner hook).
    /// Nil-store taps return nil and do nothing.
    @discardableResult
    public mutating func releaseLease(_ handle: UInt64) -> FrameLeaseRefusal? {
        guard let store = leaseStore else { return nil }
        if case .failure(let refusal) = store.release(handle) { return refusal }
        return nil
    }

    /// Fence leases at a new seek generation; older-generation leases are
    /// logically released and refuse stale afterwards.
    public mutating func fenceLeases(newGeneration: UInt64) {
        leaseStore?.fence(newGeneration: newGeneration)
    }

    /// Logically release every retained lease (cancellation/teardown path).
    public mutating func closeLeases() {
        leaseStore?.close()
    }

    public var depth: Int { queue.count }

    /// Offer one decoded frame observed at `clockNow`. Non-finite clock
    /// samples bypass the rate limiter (treated as "no clock": the rate
    /// check is skipped, matching the timePos gate's one-clock rule).
    /// In lease mode (a store is attached) this generation-less offer
    /// REFUSES with refusedLease(.generationRequired): the producer must
    /// use offerLeased so a stale in-flight frame can never be revived
    /// under the store's current generation.
    @discardableResult
    public mutating func offer(_ frame: NativeFrame, clockNow: Double) -> Verdict {
        guard frame.session == session else {
            counters.refusedStaleSession += 1
            return .refusedStaleSession
        }
        if minInterval > 0, clockNow.isFinite, let last = lastAcceptClock, clockNow - last < minInterval {
            counters.droppedRateLimit += 1
            return .droppedRateLimit
        }
        guard leaseStore == nil else {
            counters.refusedLease += 1
            return .refusedLease(.generationRequired)
        }
        var verdict: Verdict = .accepted
        if queue.count >= capacity {
            queue.removeFirst()
            counters.evictedOldest += 1
            verdict = .acceptedEvictingOldest
        }
        queue.append(frame)
        newest = frame
        if clockNow.isFinite { lastAcceptClock = clockNow }
        counters.accepted += 1
        return verdict
    }

    /// Lease-mode offer: the producer supplies the frame's seek generation.
    /// The lease is retained FIRST: a stale in-flight frame (generation
    /// older than the store's fence) refuses typed and is NOT queued, and
    /// no eviction is spent on a frame that cannot be retained. Only a
    /// retained frame joins the FIFO; bounded overflow then logically
    /// releases the evicted frame's lease through the same store path.
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
}
