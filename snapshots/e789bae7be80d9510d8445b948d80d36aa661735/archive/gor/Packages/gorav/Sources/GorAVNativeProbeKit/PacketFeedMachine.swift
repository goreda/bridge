// AUTHORED_R2 replacement (2026-10-16, ZDYM provider/build lane).
// NOT the pinned r1 member (pin 4650B/e7024d2b...); byte identity is not claimed.
// Role per DECODER-ONLY-TARGET-WIRING-r1: packet feed.
import Foundation

/// Bounded packet feed between the demux read loop and the decoder. The feed is
/// explicit: every packet is admitted under a budget or the feed saturates and the
/// reader suspends (saturation is a state, not a failure - Stage 3 P-09). EOF is a
/// distinct marker, never a nil-as-error.
public final class PacketFeedMachine: @unchecked Sendable {
    public enum FeedError: Error, Equatable, Sendable {
        case budgetExhausted
        case fedAfterEOF
        case closed
    }
    public enum State: Equatable, Sendable {
        case feeding
        case saturated
        case draining   // EOF marker queued, no new packets accepted
        case done       // EOF consumed
        case closed
    }
    public struct Budget: Equatable, Sendable {
        public let maxPackets: Int
        public let maxBytes: Int
        public init(maxPackets: Int, maxBytes: Int) {
            // r4 D16: precondition, not silent clamp - a non-positive budget is a
            // programming error and fails fast at construction.
            precondition(maxPackets > 0 && maxBytes > 0, "feed budget must be positive")
            self.maxPackets = maxPackets; self.maxBytes = maxBytes
        }
    }
    private let lock = NSLock()
    private let budget: Budget
    private var state: State = .feeding
    private var queuedPackets: Int = 0
    private var queuedBytes: Int = 0
    private var eofQueued = false
    private var highWaterPacketsStore: Int = 0
    private var highWaterBytesStore: Int = 0
    /// r5 D16: lock-guarded getters; the backing stores are only touched under lock.
    public var highWaterPackets: Int { lock.lock(); defer { lock.unlock() }; return highWaterPacketsStore }
    public var highWaterBytes: Int { lock.lock(); defer { lock.unlock() }; return highWaterBytesStore }
    /// Admission ceiling used by the adapter's oversize terminal policy (r5 D08).
    public var budgetBytes: Int { lock.lock(); defer { lock.unlock() }; return budget.maxBytes }
    public init(budget: Budget) { self.budget = budget }

    /// Admit one demuxed packet. Returns false (caller must suspend reading) when the
    /// budget is full; the feed then reads as .saturated.
    @discardableResult public func feed(bytes: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // r4 D15: no packet is admitted once EOF is queued, whatever capacity says.
        guard !eofQueued else { return false }
        guard state == .feeding || state == .saturated else { return false }
        // r4 D16: negative sizes are a caller contract violation, rejected not absorbed.
        guard bytes >= 0 else { return false }
        let (sum, overflow) = queuedBytes.addingReportingOverflow(bytes)
        guard !overflow else { state = .saturated; return false }
        if queuedPackets >= budget.maxPackets || sum > budget.maxBytes {
            state = .saturated
            return false
        }
        queuedPackets += 1; queuedBytes = sum
        highWaterPacketsStore = max(highWaterPacketsStore, queuedPackets)
        highWaterBytesStore = max(highWaterBytesStore, queuedBytes)
        state = .feeding
        return true
    }

    /// Queue the end-of-stream marker exactly once.
    @discardableResult public func feedEOF() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !eofQueued, state != .closed else { return false }
        eofQueued = true
        if state != .saturated { state = .draining }
        return true
    }

    /// Decoder consumed one packet.
    public func consume(bytes: Int) {
        lock.lock(); defer { lock.unlock() }
        // r5 D16: negative consume sizes are a caller contract violation, ignored.
        guard bytes >= 0 else { return }
        if queuedPackets > 0 { queuedPackets -= 1 }
        queuedBytes = max(0, queuedBytes - bytes)
        if state == .saturated && queuedPackets < budget.maxPackets { state = eofQueued ? .draining : .feeding }
        if eofQueued && queuedPackets == 0 && state == .draining { state = .done }
    }

    /// Decoder consumed the EOF marker.
    public func consumeEOF() {
        lock.lock(); defer { lock.unlock() }
        if eofQueued && queuedPackets == 0 { state = .done }
    }

    public var currentState: State { lock.lock(); defer { lock.unlock() }; return state }
    public var pendingPackets: Int { lock.lock(); defer { lock.unlock() }; return queuedPackets }

    /// r4 (team2-D11/open lifecycle): full reset for a new session. Called by the
    /// adapter only while no feed traffic is possible (nativeQueue fence), so a
    /// reopened session never inherits .closed/.done or stale counters.
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        state = .feeding
        queuedPackets = 0; queuedBytes = 0
        eofQueued = false
    }

    /// Teardown: no further feed accepted. Unconsumed packets are reported by count,
    /// never silently discarded from the record.
    @discardableResult public func close() -> Int {
        lock.lock(); defer { lock.unlock() }
        let dropped = queuedPackets
        state = .closed
        return dropped
    }
}
