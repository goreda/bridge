// AUTHORED_R2 replacement (2026-10-16, ZDYM provider/build lane).
// NOT the pinned r1 member (pin 2912B/0f5fb9eb...); byte identity is not claimed.
// Role per DECODER-ONLY-TARGET-WIRING-r1: ownership accounting.
import Foundation

/// Ownership accounting for native frame buffers, separate from the contract-level
/// FrameLeaseLedger (which tracks protocol stage transitions). LeaseTable answers
/// one question: who currently owns buffer slot N, and is every acquire matched
/// by exactly one release before teardown. A leak here is a retained native buffer;
/// it is recorded, never silently dropped.
public final class LeaseTable: @unchecked Sendable {
    public enum Owner: Equatable, Sendable {
        case decoder
        case presenter
        case none
    }
    public struct Entry: Equatable, Sendable {
        public let handle: UInt64
        public let bytes: Int
        public internal(set) var owner: Owner
        public init(handle: UInt64, bytes: Int, owner: Owner) {
            self.handle = handle; self.bytes = bytes; self.owner = owner
        }
    }
    private let lock = NSLock()
    private var entries: [UInt64: Entry] = [:]
    private var outstandingBytes: Int = 0
    private var maxOutstandingBytesStore: Int = 0
    /// r5 D16: lock-guarded getter; backing store only touched under lock.
    public var maxOutstandingBytes: Int { lock.lock(); defer { lock.unlock() }; return maxOutstandingBytesStore }
    public init() {}

    /// Records a freshly allocated native buffer. Returns false on duplicate handle.
    @discardableResult public func acquire(handle: UInt64, bytes: Int, owner: Owner) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // r4 D16: negative byte counts are a caller contract violation.
        guard bytes >= 0 else { return false }
        guard entries[handle] == nil else { return false }
        entries[handle] = Entry(handle: handle, bytes: bytes, owner: owner)
        let (sum, overflow) = outstandingBytes.addingReportingOverflow(bytes)
        if overflow { entries.removeValue(forKey: handle); return false }
        outstandingBytes = sum
        maxOutstandingBytesStore = max(maxOutstandingBytesStore, outstandingBytes)
        return true
    }

    /// Transfers ownership (decoder -> presenter). Unknown handle is a no-op returning false.
    @discardableResult public func transfer(handle: UInt64, to owner: Owner) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard var e = entries[handle] else { return false }
        e.owner = owner; entries[handle] = e
        return true
    }

    /// Releases the buffer. Returns false when the handle is unknown (double/unknown release).
    @discardableResult public func release(handle: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries.removeValue(forKey: handle) else { return false }
        outstandingBytes -= e.bytes
        return true
    }

    /// Immutable per-handle copy; caller still owns session serialization.
    public func entry(handle: UInt64) -> Entry? {
        lock.lock(); defer { lock.unlock() }; return entries[handle]
    }

    public var outstandingCount: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
    public var currentOutstandingBytes: Int { lock.lock(); defer { lock.unlock() }; return outstandingBytes }

    /// r6: clears every entry; call after recording leaks so a later session
    /// never collides with stale handles.
    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries = [:]; outstandingBytes = 0
    }

    /// Handles still owned at teardown; every entry here is a leak to report.
    public func leakedHandles() -> [UInt64] {
        lock.lock(); defer { lock.unlock() }
        return entries.keys.sorted()
    }
}
