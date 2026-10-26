import Foundation
import GorAVCAtomics

/// No media bytes, credentials or runtime player are part of this Stage 0 contract.
///
/// IDENTITY AUTHORITY (architect full verdict S4): a SessionID's public
/// init carries NO authority. Production playback identity is issued ONLY
/// by PlaybackIdentityAuthority - one owner-issued opaque identity shared
/// across decoder/audio/display/ledger for a run, with a separate
/// seek/presentation revision. Per-lane minting (String+UInt64 forms,
/// hashes, fixed shell epochs) is a contract violation; explicit-epoch
/// construction remains for TEST FIXTURES ONLY and mints nothing.
public struct SessionID: Hashable, Sendable {
    public let epoch: UInt64
    /// S7: NOT a mint. Production identities come ONLY from
    /// PlaybackIdentityAuthority.issue() (one owner-issued opaque
    /// identity per run). This unchecked constructor exists for
    /// REFUSAL/FOREIGN-SESSION TESTS, which must fabricate arbitrary
    /// unissued ids to prove they are refused; naming it unchecked
    /// keeps forgery out of production call sites by inspection.
    public init(uncheckedEpoch: UInt64) { self.epoch = uncheckedEpoch }
}

/// The single owner of playback identity issuance (S4). Monotonic atomic
/// issuance; wrap is TYPED EXHAUSTION (nil), never a recycled identity.
public final class PlaybackIdentityAuthority: @unchecked Sendable {
    public static let shared = PlaybackIdentityAuthority()
    /// C-owned atomic cell (GorAVCAtomics); failable alloc = typed refusal.
    private let lastIssued: UnsafeMutableRawPointer?
    private init() { lastIssued = gorav_acell_create(0) }
    deinit { if let c = lastIssued { gorav_acell_destroy(c) } }
    /// Issue the next opaque session identity, or nil at typed exhaustion.
    public func issue() -> SessionID? {
        guard let c = lastIssued else { return nil }     // typed cell refusal
        while true {
            let last = gorav_aload(c)
            if last == UInt64.max { return nil }         // typed exhaustion, never wrap
            var e = last
            if gorav_acas(c, &e, last &+ 1) != 0 { return SessionID(uncheckedEpoch: last &+ 1) }
        }
    }
    /// Seek/presentation revision (S4): separate from session identity.
    /// A seek NEVER mints a new session; it bumps the run's revision.
    public final class PresentationRevision: @unchecked Sendable {
        private let cell: UnsafeMutableRawPointer?
        public init() { cell = gorav_acell_create(0) }
        deinit { if let c = cell { gorav_acell_destroy(c) } }
        public var current: UInt64 { guard let c = cell else { return 0 }; return gorav_aload(c) }
        public func bump() -> UInt64 { guard let c = cell else { return 0 }; return gorav_afetch_add(c, 1) &+ 1 }
    }
}

public struct SourceDescriptor: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case local, remote, webTorrent, iptv }
    public let id: String
    public let kind: Kind
    public let seekable: Bool
    public init(id: String, kind: Kind, seekable: Bool) {
        self.id = id; self.kind = kind; self.seekable = seekable
    }
}

public enum StopReason: Equatable, Sendable { case user, replaced, endOfFile, failure }
public enum Lifecycle: Equatable, Sendable {
    case idle, opening, ready, playing, paused, buffering, ended(StopReason), failed
}
public struct SessionSnapshot: Equatable, Sendable {
    public let id: SessionID
    public let source: SourceDescriptor
    public let lifecycle: Lifecycle
    public init(id: SessionID, source: SourceDescriptor, lifecycle: Lifecycle) {
        self.id = id; self.source = source; self.lifecycle = lifecycle
    }
}

/// A backend can be an mpv adapter first. Native demux/decode and render backends
/// are later implementations, not capabilities asserted by this interface.
public protocol PlaybackBackend: AnyObject {
    func open(_ source: SourceDescriptor, session: SessionID) async throws
    func stop(session: SessionID, reason: StopReason) async
    func seek(seconds: Double, session: SessionID, requestID: UInt64) async throws
    func snapshot(session: SessionID) async -> SessionSnapshot?
}

/// Pure epoch gate for callbacks from async backends. Source/event correlation
/// remains backend-specific and must not be inferred from arrival order alone.
public struct SessionGate: Sendable {
    public private(set) var active: SessionID?
    public init() {}
    /// S7: the gate CONSUMES an owner-issued identity; it never mints
    /// one (PlaybackIdentityAuthority is the single issuance owner).
    @discardableResult public mutating func begin(_ id: SessionID) -> SessionID {
        active = id
        return id
    }
    public mutating func stop() { active = nil }
    public func accepts(_ id: SessionID) -> Bool { active == id }
}
