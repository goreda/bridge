// TEST-ONLY SHIM. The pinned PlaybackCore.swift references two types that live in
// other package files not present in the W-0221 packet: GorAVCAtomics (AtomicU64)
// and TimingLedger (+ segment/subsystem/kind enums). This shim supplies minimal
// stand-ins so the UNMODIFIED pinned file compiles. FramePump and CancelCommit logic
// run from the pinned bytes; only the atomic cell and the ledger sink are stand-ins.
import Foundation

public final class AtomicU64: @unchecked Sendable {
    private let lock = NSLock(); private var v: UInt64
    public init(_ initial: UInt64) { v = initial }
    public func load() -> UInt64 { lock.lock(); defer { lock.unlock() }; return v }
    public func compareExchange(expected: UInt64, desired: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if v == expected { v = desired; return true }
        return false
    }
    @discardableResult public func fetchAdd(_ d: UInt64) -> UInt64 { lock.lock(); defer { lock.unlock() }; let o = v; v &+= d; return o }
}

public enum LedgerSegment { case pump }
public enum LedgerSubsystem { case video }
public enum LedgerKind { case videoPumpStart, videoPumpEnd, terminal, frameWait, frameShown, frameDroppedLate,
    presentationReset, staleRevisionFenced, ptsBackwardDrop, ptsGapForward, ptsNonFiniteDrop }

public final class TimingLedger: @unchecked Sendable {
    private let lock = NSLock(); private var kinds: [LedgerKind] = []
    public init() {}
    public func append(session: UInt64, generation: UInt64, segment: LedgerSegment, subsystem: LedgerSubsystem,
                       kind: LedgerKind, pts: Double? = nil, bytes: Int? = nil, note: String? = nil) {
        lock.lock(); kinds.append(kind); lock.unlock()
    }
}
