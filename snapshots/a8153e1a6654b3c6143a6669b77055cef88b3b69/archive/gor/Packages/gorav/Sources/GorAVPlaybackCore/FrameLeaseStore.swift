import Foundation
import GorAVNativeProbeKit

// 195b-53 (R5, review r2): lease-ownership BOOKKEEPING for retained decoded
// frames kept off the render path. This store is the bookkeeping spine: it
// tracks which frame leases are outstanding, under which seek generation,
// against a bounded count+byte budget, and it notifies the owner's
// bookkeeping through ONE release hook on every release path (explicit,
// overflow eviction, seek-generation fence, close). It does NOT retain or
// free pixel bytes itself, and the hook is a bookkeeping notification: actual
// native pixel retention/deallocation is the owner backend's business behind
// that hook and remains open work (GPU readback/screenshot and native pixels
// are explicitly not claimed here). The portable fake owner in
// frame-lease-tests rides this actual bookkeeping code.
//
// Pinning (review r3): pin/unpin gives an accessor a liveness guarantee. A
// release, fence, close or overflow eviction of a PINNED lease takes effect
// in the bookkeeping immediately (the lease is logically released: new pins
// and accesses refuse) but the owner release hook is DEFERRED until the last
// unpin, so a concurrent accessor can never have the owner's pixels freed
// under it. Overflow eviction never selects a pinned lease; if no unpinned
// lease can be evicted the retain refuses typed.
//
// Fences: a lease carries the CALLER-SUPPLIED seek generation it was
// retained under (never stamped by the store), so an old in-flight frame
// offered after a seek refuses stale instead of being revived under the
// current generation. Access requires the caller's generation to equal both
// the store's current generation and the lease's own generation.
//
// Thread safety: all state is lock-guarded. The release hook is invoked
// WITHOUT the store lock held, so an owner hook that re-enters the store
// cannot deadlock.

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
    public var releasedExplicit = 0
    public var releasedOverflow = 0
    public var releasedFence = 0
    public var releasedClose = 0
    /// Logical releases whose owner-hook call was deferred behind pins.
    public var releaseDeferred = 0
    /// Owner-hook calls actually delivered (immediate + drained).
    public var hookDelivered = 0
    public var refusedForeign = 0
    public var refusedClosed = 0
    public var refusedUnknown = 0
    public var refusedStale = 0
    public var refusedDoubleRelease = 0
    public var refusedDuplicate = 0
    public var refusedCapacity = 0
    public var refusedPinnedOverflow = 0
    public var refusedNotPinned = 0
    public init() {}
}

public final class FrameLeaseStore: @unchecked Sendable {

    /// Read-only view handed to a pinned accessor. Still only identity +
    /// metadata + byte accounting: pixel access stays the owner's business
    /// behind its own bookkeeping.
    public struct Access: Equatable, Sendable {
        public let frame: NativeFrame
        public let seekGeneration: UInt64
        public let bytes: Int
    }

    private struct Entry {
        let frame: NativeFrame
        let seekGeneration: UInt64
        let bytes: Int
        var pins: Int
    }

    private let lock = NSLock()
    private let session: UInt64
    private let maxLeases: Int
    private let maxBytes: Int
    /// Bookkeeping release notification (handle, session): fires exactly once
    /// per outstanding lease, possibly deferred behind pins. The owner maps
    /// this onto its actual pixel bookkeeping; this store never touches
    /// pixel bytes.
    private let onRelease: (UInt64, UInt64) -> Void

    private var leases: [UInt64: Entry] = [:]          // live leases
    private var order: [UInt64] = []                   // FIFO eviction order (live only)
    /// Logically released leases whose owner hook is deferred behind pins.
    private var pendingHook: [UInt64: Entry] = [:]
    private var releasingHandles: Set<UInt64> = []
    private var releasingBytes = 0
    private var releaseSizes: [UInt64: Int] = [:]
    private var outstandingBytes = 0
    private var generation: UInt64
    /// Bounded memory of explicitly released handles so double release is a
    /// typed refusal instead of a silent unknown (same spirit as the native
    /// FrameLeaseLedger). Kept to the most recent 64.
    private var releasedExplicitSet: Set<UInt64> = []
    private var releasedExplicitOrder: [UInt64] = []
    private var closed = false

    private var counterState = FrameLeaseCounters()
    /// Counters are always read under the lock: a snapshot, never a race.
    public var counters: FrameLeaseCounters { lock.lock(); defer { lock.unlock() }; return counterState }

    /// session: the only frame session this store serves. maxLeases/maxBytes:
    /// the bounded-retention budget; overflow logically releases the OLDEST
    /// UNPINNED lease. onRelease is the bookkeeping hook described above.
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

    /// Retain one decoded frame's lease under the CALLER-SUPPLIED seek
    /// generation. Refusals are typed and counted. Bounded overflow
    /// logically releases the oldest UNPINNED leases BEFORE the new lease is
    /// recorded, so the budget never exceeds after return; if only pinned
    /// leases could be evicted the retain refuses.
    @discardableResult
    public func retain(_ frame: NativeFrame, bytes: Int, seekGeneration: UInt64) -> Result<UInt64, FrameLeaseRefusal> {
        var releases: [(UInt64, UInt64)] = []
        let result: Result<UInt64, FrameLeaseRefusal> = { () in
            lock.lock(); defer { lock.unlock() }
            guard !closed else { counterState.refusedClosed += 1; return .failure(.storeClosed) }
            guard frame.session == session else { counterState.refusedForeign += 1; return .failure(.foreignSession) }
            guard seekGeneration == generation else {
                counterState.refusedStale += 1; return .failure(.staleGeneration(current: generation))
            }
            guard bytes >= 0, bytes <= maxBytes else { counterState.refusedCapacity += 1; return .failure(.exceedsCapacity) }
            guard leases[frame.handle] == nil, pendingHook[frame.handle] == nil, !releasingHandles.contains(frame.handle) else {
                counterState.refusedDuplicate += 1; return .failure(.duplicateLease)
            }
            let inFlightCount = releasingHandles.count
            let pendingBytes = pendingHook.values.reduce(releasingBytes) { $0 + $1.bytes }
            while leases.count + pendingHook.count + inFlightCount >= maxLeases || outstandingBytes > maxBytes - pendingBytes - bytes {
                guard let oldest = order.first(where: { leases[$0]?.pins == 0 }) else {
                    counterState.refusedPinnedOverflow += 1
                    return .failure(.overflowBlockedByPins)
                }
                order.removeAll { $0 == oldest }
                if let evicted = leases.removeValue(forKey: oldest) {
                    outstandingBytes -= evicted.bytes
                    counterState.releasedOverflow += 1
                    releaseSizes[oldest] = evicted.bytes
                    releasingBytes += evicted.bytes
                    releasingHandles.insert(oldest)
                    releases.append((oldest, evicted.frame.session))
                }
            }
            leases[frame.handle] = Entry(frame: frame, seekGeneration: seekGeneration, bytes: bytes, pins: 0)
            order.append(frame.handle)
            outstandingBytes += bytes
            counterState.retained += 1
            return .success(frame.handle)
        }()
        deliver(releases)
        return result
    }

    /// Pin a lease for access: while pinned, the owner's release hook cannot
    /// fire for this lease, so the accessor's pixel use stays valid against
    /// concurrent release/fence/close. Returns the access view. Every
    /// successful pin MUST be paired with unpin.
    public func pin(_ handle: UInt64, seekGeneration: UInt64) -> Result<Access, FrameLeaseRefusal> {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { counterState.refusedClosed += 1; return .failure(.storeClosed) }
        guard seekGeneration == generation else {
            counterState.refusedStale += 1; return .failure(.staleGeneration(current: generation))
        }
        guard var entry = leases[handle] else {
            if releasedExplicitSet.contains(handle) { counterState.refusedDoubleRelease += 1; return .failure(.alreadyReleased) }
            counterState.refusedUnknown += 1; return .failure(.unknownLease)
        }
        guard entry.seekGeneration == seekGeneration else {
            counterState.refusedStale += 1; return .failure(.staleGeneration(current: generation))
        }
        entry.pins += 1
        leases[handle] = entry
        counterState.pinned += 1
        return .success(Access(frame: entry.frame, seekGeneration: entry.seekGeneration, bytes: entry.bytes))
    }

    /// Pair for pin. When the lease was logically released while pinned,
    /// this drains the deferred owner hook once the last pin drops. Works
    /// after close(): outstanding pins must always be drainable.
    @discardableResult
    public func unpin(_ handle: UInt64) -> Result<Void, FrameLeaseRefusal> {
        var releases: [(UInt64, UInt64)] = []
        let result: Result<Void, FrameLeaseRefusal> = { () in
            lock.lock(); defer { lock.unlock() }
            if var live = leases[handle] {
                guard live.pins > 0 else { counterState.refusedNotPinned += 1; return .failure(.notPinned) }
                live.pins -= 1
                leases[handle] = live
                counterState.unpinned += 1
                return .success(())
            }
            if var pending = pendingHook[handle] {
                guard pending.pins > 0 else { counterState.refusedNotPinned += 1; return .failure(.notPinned) }
                pending.pins -= 1
                counterState.unpinned += 1
                if pending.pins == 0 {
                    pendingHook.removeValue(forKey: handle)
                    releaseSizes[handle] = pending.bytes
                    releasingBytes += pending.bytes
                    releasingHandles.insert(handle)
                    releases.append((handle, pending.frame.session))
                } else {
                    pendingHook[handle] = pending
                }
                return .success(())
            }
            counterState.refusedUnknown += 1
            return .failure(.unknownLease)
        }()
        deliver(releases)
        return result
    }

    /// Scoped pinned access: pins, runs body with the access view, unpins.
    /// The owner hook can never fire for the lease while body runs.
    public func withPinnedAccess<T>(_ handle: UInt64, seekGeneration: UInt64, _ body: (Access) -> T) -> Result<T, FrameLeaseRefusal> {
        switch pin(handle, seekGeneration: seekGeneration) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let access):
            let value = body(access)
            _ = unpin(handle)
            return .success(value)
        }
    }

    /// Explicit logical release of one outstanding lease. The owner hook
    /// fires immediately unless the lease is pinned, in which case it is
    /// deferred to the last unpin. Releasing an already-released or unknown
    /// handle is a typed refusal.
    @discardableResult
    public func release(_ handle: UInt64) -> Result<Void, FrameLeaseRefusal> {
        var releases: [(UInt64, UInt64)] = []
        let result: Result<Void, FrameLeaseRefusal> = { () in
            lock.lock(); defer { lock.unlock() }
            guard !closed else { counterState.refusedClosed += 1; return .failure(.storeClosed) }
            guard let entry = leases.removeValue(forKey: handle) else {
                if releasedExplicitSet.contains(handle) { counterState.refusedDoubleRelease += 1; return .failure(.alreadyReleased) }
                counterState.refusedUnknown += 1; return .failure(.unknownLease)
            }
            order.removeAll { $0 == handle }
            outstandingBytes -= entry.bytes
            counterState.releasedExplicit += 1
            rememberExplicitRelease(handle)
            deferHookOrDeliver(entry, into: &releases)
            return .success(())
        }()
        deliver(releases)
        return result
    }

    /// Seek-generation fence: leases retained under a generation older than
    /// newGeneration are logically released, and their handles refuse stale
    /// on later access. Pinned leases defer the owner hook to their last
    /// unpin. Generations are monotonic; a fence at a generation not newer
    /// than the current one is a no-op.
    public func fence(newGeneration: UInt64) {
        var releases: [(UInt64, UInt64)] = []
        lock.lock()
        if newGeneration > generation {
            generation = newGeneration
            let doomed = order.filter { (leases[$0]?.seekGeneration ?? newGeneration) < newGeneration }
            for handle in doomed {
                if let entry = leases.removeValue(forKey: handle) {
                    outstandingBytes -= entry.bytes
                    counterState.releasedFence += 1
                    deferHookOrDeliver(entry, into: &releases)
                }
            }
            order.removeAll { doomed.contains($0) }
        }
        lock.unlock()
        deliver(releases)
    }

    /// Close the store: every outstanding lease is logically released and
    /// all later operations refuse with storeClosed (unpin excepted: pins
    /// must remain drainable). Cancellation routes through close: there is
    /// no lighter-weight cancel state to leave resources dangling in.
    public func close() {
        var releases: [(UInt64, UInt64)] = []
        lock.lock()
        if !closed {
            closed = true
            for handle in order {
                if let entry = leases.removeValue(forKey: handle) {
                    outstandingBytes -= entry.bytes
                    counterState.releasedClose += 1
                    deferHookOrDeliver(entry, into: &releases)
                }
            }
            order.removeAll()
            outstandingBytes = 0
        }
        lock.unlock()
        deliver(releases)
    }

    /// Logical release bookkeeping: pinned leases park in pendingHook with
    /// their pins intact and the owner hook deferred; unpinned leases are
    /// queued for immediate hook delivery. Must be called under the lock.
    private func deferHookOrDeliver(_ entry: Entry, into releases: inout [(UInt64, UInt64)]) {
        if entry.pins > 0 {
            pendingHook[entry.frame.handle] = entry
            counterState.releaseDeferred += 1
        } else {
            releaseSizes[entry.frame.handle] = entry.bytes
            releasingBytes += entry.bytes
            releasingHandles.insert(entry.frame.handle)
            releases.append((entry.frame.handle, entry.frame.session))
        }
    }

    private func rememberExplicitRelease(_ handle: UInt64) {
        releasedExplicitSet.insert(handle)
        releasedExplicitOrder.append(handle)
        if releasedExplicitOrder.count > 64 {
            let dropped = releasedExplicitOrder.removeFirst()
            releasedExplicitSet.remove(dropped)
        }
    }

    /// Hook delivery happens outside the store lock: an owner that re-enters
    /// the store from its release path cannot deadlock.
    private func deliver(_ releases: [(UInt64, UInt64)]) {
        guard !releases.isEmpty else { return }
        lock.lock()
        counterState.hookDelivered += releases.count
        lock.unlock()
        for (handle, session) in releases {
            onRelease(handle, session)
            lock.lock(); releasingHandles.remove(handle); releasingBytes -= releaseSizes.removeValue(forKey: handle) ?? 0; lock.unlock()
        }
    }
}
