// SOURCE-ONLY PROPOSAL. Extracted from held r11 candidate; UNCOMPILED.
// Decoder contracts only. No presenter, playback backend, queue or CLI.
import Foundation
import GorAVCore

/// How much of a deadline the decoder can actually enforce. Partial capability is never bounded-run proof.
public enum InterruptCapability: Equatable, Sendable {
    case none                  // cannot interrupt
    case ioOnly                // aborts blocking demux/AVIO calls that poll the interrupt callback; NOT a stuck decode
    case hardDecodeDeadline    // any in-flight call returns promptly (must be proven natively; no adapter claims it yet)
}
/// Optional decoder capability: abort blocking work of ONE session from another thread without taking the
/// decoder's lock. Per-operation: a request for a session that is not the installed one is a no-op.
public protocol InterruptibleDecoder: AnyObject {
    var interruptCapability: InterruptCapability { get }
    func requestInterrupt(session: SessionID)
}

/// Per-session interrupt slot (pure, testable). `fire` runs under the slot lock, so a destroy that also
/// takes the lock cannot race a pending request. Installing a new session replaces the old one; requests
/// for any other session are ignored (stale-interrupt fence).
public final class SessionInterruptSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var session: UInt64?
    private var fire: (() -> Void)?
    public init() {}
    public func install(session: UInt64, fire: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        self.session = session; self.fire = fire
    }
    @discardableResult public func request(session: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard self.session == session, let f = fire else { return false }
        f(); return true
    }
    /// Call before freeing whatever `fire` touches.
    public func clear() { lock.lock(); session = nil; fire = nil; lock.unlock() }
}

/// Lease ledger for contract C1. Decoder adapter calls `allocated` and `released` (discard path);
/// presenter adapter calls `released` after it is done with a handle on EVERY path; the backend calls
/// `handedToPresenter` / `discardRequested`. "Handed" is not "released": only `released` closes a lease.
/// Memory bound: at most maxSessions * maxDecodeEvents entries (kept to detect double release); violation
/// lists keep the first 64 handles while `violations` stays exact.
public final class FrameLeaseLedger: @unchecked Sendable {
    public enum Stage: Equatable, Sendable { case allocated, handedToPresenter, discardRequested, released }
    /// Composite identity: the same handle number in another session is a different lease.
    public struct Key: Hashable, Sendable { public let session: UInt64; public let handle: UInt64 }
    private let lock = NSLock()
    private var stages: [Key: Stage] = [:]
    private var violationCount = 0
    private var violationsBySession: [UInt64: Int] = [:]
    private var doubleReleaseList: [UInt64] = []
    private var unknownReleaseList: [UInt64] = []
    private var duplicateAllocationList: [UInt64] = []
    public init() {}
    public func allocated(_ h: UInt64, session: UInt64) {
        lock.lock(); defer { lock.unlock() }
        let k = Key(session: session, handle: h)
        if stages[k] != nil { violationCount += 1; violationsBySession[session, default: 0] += 1; if duplicateAllocationList.count < 64 { duplicateAllocationList.append(h) } }
        else { stages[k] = .allocated }
    }
    public func handedToPresenter(_ h: UInt64, session: UInt64) {
        lock.lock(); defer { lock.unlock() }
        let k = Key(session: session, handle: h)
        if stages[k] == .allocated { stages[k] = .handedToPresenter }
    }
    public func discardRequested(_ h: UInt64, session: UInt64) {
        lock.lock(); defer { lock.unlock() }
        let k = Key(session: session, handle: h)
        if stages[k] == .allocated { stages[k] = .discardRequested }
    }
    public func released(_ h: UInt64, session: UInt64) {
        lock.lock(); defer { lock.unlock() }
        let k = Key(session: session, handle: h)
        switch stages[k] {
        case .none: violationCount += 1; violationsBySession[session, default: 0] += 1; if unknownReleaseList.count < 64 { unknownReleaseList.append(h) }
        case .some(.released): violationCount += 1; violationsBySession[session, default: 0] += 1; if doubleReleaseList.count < 64 { doubleReleaseList.append(h) }
        case .some: stages[k] = .released
        }
    }
    /// An adapter that detects a repeated release request before the first one took effect reports it here.
    public func noteDoubleRelease(_ h: UInt64, session: UInt64) {
        lock.lock(); defer { lock.unlock() }
        violationCount += 1; violationsBySession[session, default: 0] += 1
        if doubleReleaseList.count < 64 { doubleReleaseList.append(h) }
    }
    /// Immutable composite-key stage snapshot for queue-owned observers.
    public func stage(handle: UInt64, session: UInt64) -> Stage? {
        lock.lock(); defer { lock.unlock() }
        return stages[Key(session: session, handle: handle)]
    }
    public var outstanding: Int { lock.lock(); defer { lock.unlock() }; return stages.values.filter { $0 != .released }.count }
    public var violations: Int { lock.lock(); defer { lock.unlock() }; return violationCount }
    /// Violations attributed to one session (an old session's violation must not fail a newer session).
    public func violations(session: UInt64) -> Int { lock.lock(); defer { lock.unlock() }; return violationsBySession[session] ?? 0 }
    public func leaks(session: UInt64) -> [UInt64] {
        lock.lock(); defer { lock.unlock() }
        return stages.filter { $0.value != .released && $0.key.session == session }.map { $0.key.handle }.sorted()
    }
    /// Ledger teardown for one session. Outstanding (non-released) handles are
    /// returned as leaks; the session's entries are then dropped so a new session
    /// with the same id cannot inherit stale stages.
    public func close(session: UInt64) -> [UInt64] {
        lock.lock(); defer { lock.unlock() }
        let open = stages.filter { $0.value != .released && $0.key.session == session }.map { $0.key.handle }.sorted()
        stages = stages.filter { $0.key.session != session }
        return open
    }
}
// --- Below this line: AUTHORED_R2 completion (2026-10-16). The pinned extraction
// (7366B/429eaf4f...) is only partially held (lines 1-95 above, 5627B). This
// completion is new authored source; the whole file is NOT the pinned member.
// Contract source for the types below: DECODER-ONLY-TARGET-WIRING-r1 extraction
// ranges 85-117, 132-210, 267-278 (InterruptCapability/InterruptibleDecoder/
// SessionInterruptSlot/FrameLeaseLedger above; NativeFrame/DecodeEvent/
// LocalVideoDecoder below).

/// One decoded frame handle as passed across the decoder boundary. The handle is
/// session-composite: the same number in another session is a different frame.
/// Pixels are not copied into this value; it is a ledger identity plus metadata.
public struct NativeFrame: Equatable, Sendable {
    public let session: UInt64
    public let handle: UInt64
    public let pts: Int64?
    public let duration: Int64
    public let width: Int
    public let height: Int
    public let pixelFormatName: String
    public let isKeyFrame: Bool
    public init(session: UInt64, handle: UInt64, pts: Int64?, duration: Int64,
                width: Int, height: Int, pixelFormatName: String, isKeyFrame: Bool) {
        self.session = session; self.handle = handle; self.pts = pts; self.duration = duration
        self.width = width; self.height = height
        self.pixelFormatName = pixelFormatName; self.isKeyFrame = isKeyFrame
    }
}

/// Decoder progress events. `failed` carries a bounded diagnostic string; free-form
/// source strings or media identifiers are never attached (evidence privacy rule).
public enum DecodeEvent: Equatable, Sendable {
    case opened(videoCodec: String, width: Int, height: Int)
    case frameDecoded(NativeFrame)
    case endOfStream
    case interrupted(session: UInt64)
    case failed(code: Int, summary: String)
    /// Backpressure receipt: the bounded packet feed refused admission; the
    /// demuxed packet is held by the decoder (not dropped) and the reader must
    /// pull again after frames are consumed. Distinct from failure (Stage 3 P-09).
    case feedSaturated(pendingPackets: Int)
}

/// The decoder-only probe's decoder contract. Blocking C calls run on the
/// implementation's own serial context; this protocol's async surface is the only
/// public entry. `requestInterrupt` is ioOnly at best (see InterruptCapability) and
/// is per-session fenced by SessionInterruptSlot.
public protocol LocalVideoDecoder: AnyObject {
    var interruptCapability: InterruptCapability { get }
    /// Open a source for one session. Admission must already have passed
    /// DemuxerPolicy; this call performs the actual demux/decode setup.
    func open(source: SourceDescriptor, session: SessionID) async throws
    /// Pull the next event. Returns nil only after endOfStream/failed/interrupted
    /// has terminated the event stream for this session.
    func nextEvent(session: SessionID) async -> DecodeEvent?
    /// Release a previously delivered frame handle (contract C1: every path).
    func releaseFrame(handle: UInt64, session: SessionID) async
    /// Request abort of blocking I/O for this session. Stale sessions are a no-op.
    func requestInterrupt(session: SessionID)
    /// Definitive close: interrupt honored, input closed, codec freed, leases
    /// settled or reported as leaks. After close, no further events are emitted.
    func close(session: SessionID) async
}
