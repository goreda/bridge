import Foundation

// Row 195b-55 (arch-195b): active-decoder inventory. A decoder instance is
// Metadata registry only: software adapters wire lifetime below; no container inventory is read.
// Callers must serialize mutations. Decoder instances can be
// tracked from registration to explicit deregistration; snapshots are typed,
// immutable, and generation-fenced. The cache answers "what is live right
// now" without touching decoder internals - the adapter registers on open and
// deregisters on close/deinit/failure.

public struct DecoderIdentity: Equatable, Hashable, Sendable {
    /// Session/generation the decoder belongs to (same fence as frames).
    public let session: UInt64
    /// Per-session decoder handle; unique within a session.
    public let handle: UInt64
    public init(session: UInt64, handle: UInt64) {
        self.session = session; self.handle = handle
    }
}

public enum DecoderKind: String, Equatable, Sendable {
    case videoSoftware, audioSoftware, videoHardware
}

public enum DecoderLifecycle: String, Equatable, Sendable {
    case open, draining, failed, closed
}

/// Typed snapshot of one tracked decoder at read time.
public struct DecoderSnapshot: Equatable, Sendable {
    public let identity: DecoderIdentity
    public let kind: DecoderKind
    /// Probe-admitted codec name (e.g. "h264", "aac"); never a free-form
    /// source string (evidence privacy rule).
    public let codec: String
    /// Opaque provider identity, never a file path/URL. Immutable OPEN facts,
    /// not a claim to mirror a later seek revision or enumerate container tracks.
    public let sourceID: String?
    public let revisionAtOpen: UInt64
    /// Mutated only by DecoderInventory (same file) on mark(); immutable to callers.
    public internal(set) var lifecycle: DecoderLifecycle
    /// Registration order, monotonic per inventory - a cheap total order for
    /// "oldest live decoder" without trusting clocks.
    public let registrationSeq: UInt64
}

public struct DecoderInventory: Sendable {

    public enum RegisterOutcome: Equatable, Sendable {
        case registered
        case refusedInvalidatedSession
        case refusedIdentityExhausted
        /// Same identity registered twice; the existing entry wins and the
        /// attempt is receipted.
        case duplicateRefused
    }

    public private(set) var entries: [DecoderIdentity: DecoderSnapshot] = [:]
    public private(set) var duplicateRegistrations = 0
    public private(set) var deregistrations = 0
    /// Sessions invalidated wholesale (reset/seek-restart); snapshots for
    /// them are never served again even if a stale decoder forgets to
    /// deregister.
    public private(set) var invalidatedSessions: Set<UInt64> = []
    private var nextSeq: UInt64 = 1

    public init() {}

    @discardableResult
    public mutating func register(_ id: DecoderIdentity, kind: DecoderKind,
                                  codec: String, sourceID: String? = nil,
                                  revisionAtOpen: UInt64 = 1) -> RegisterOutcome {
        guard !invalidatedSessions.contains(id.session) else { return .refusedInvalidatedSession }
        guard nextSeq < UInt64.max else { return .refusedIdentityExhausted }
        guard entries[id] == nil else {
            duplicateRegistrations += 1
            return .duplicateRefused
        }
        entries[id] = DecoderSnapshot(identity: id, kind: kind, codec: codec, sourceID: sourceID,
                                      revisionAtOpen: revisionAtOpen, lifecycle: .open, registrationSeq: nextSeq)
        nextSeq += 1
        return .registered
    }

    public mutating func mark(_ id: DecoderIdentity, _ lifecycle: DecoderLifecycle) {
        if entries[id] != nil { entries[id]!.lifecycle = lifecycle }
    }

    @discardableResult
    public mutating func deregister(_ id: DecoderIdentity) -> Bool {
        guard entries.removeValue(forKey: id) != nil else { return false }
        deregistrations += 1
        return true
    }

    /// Fence a whole session (seek-restart / reset): all its entries drop.
    public mutating func invalidateSession(_ session: UInt64) {
        invalidatedSessions.insert(session)
        entries = entries.filter { $0.key.session != session }
    }

    /// Live snapshot for one identity; nil for unknown, deregistered, or
    /// session-invalidated decoders. `lifecycle` filter: closed/failed
    /// entries are still returned (they happened) until deregistered.
    public func snapshot(_ id: DecoderIdentity) -> DecoderSnapshot? {
        guard !invalidatedSessions.contains(id.session) else { return nil }
        return entries[id]
    }

    /// All currently tracked decoders for a session, registration order.
    public func activeSnapshots(session: UInt64) -> [DecoderSnapshot] {
        guard !invalidatedSessions.contains(session) else { return [] }
        return entries.values
            .filter { $0.identity.session == session && $0.lifecycle != .closed }
            .sorted { $0.registrationSeq < $1.registrationSeq }
    }
}

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
