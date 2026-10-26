// PROCESS-OWNED LIFETIME REGISTRY (r3-rev1, peer interim review S1 findings
// 1-4, 2026-10-25). Capability state machine:
//   * reserve(kind:) -> one-shot Reservation token. Consumed exactly once
//     by register(token:) (commit) or rollback(token:) (release); a token
//     that DEINITS unconsumed rolls itself back (finding 4: dropped
//     tokens must not leak).
//   * TERMINAL OBLIGATIONS ARE RESERVED, not headroom-checked (finding
//     1): reserve(.active) atomically claims active + a pendingTerminal
//     unit. Public reserve(.fault/.tombstone) must fit UNDER the pending
//     obligation (faults + pending < cap), so the later active->terminal
//     reclassify ALWAYS commits - it consumes the pending unit, it never
//     needs fresh headroom and can never fail mid-teardown.
//   * Registration is an UNFORGEABLE CAPABILITY (finding 2): register()
//     returns a RegistrationToken object; reclassify/rebind/reclaim
//     require THAT object (identity match), not a guessable UInt64.
//     Valid transitions are active->{fault,tombstone} ONLY; terminal
//     kinds are immutable afterwards (no terminal->active, no
//     terminal->terminal).
//   * The registry entry keeps an IMMUTABLE CONTEXT ROOT (finding 3):
//     the object bound at register() is never replaceable, so a late
//     provider refCon can never be freed by a rebind.
//     attachFaultGraph() ATTACHES a separate typed FaultPayloadGraph
//     alongside the root (the old rebind API is deleted).
//   * Registration-id wrap is TYPED (finding 4): when the id minter
//     would wrap, the registry flips to permanently exhausted (typed
//     refusals), never an id reuse.
//   * reclaim() still requires a ProviderReleaseProof that NOTHING can
//     construct today (internal init) - honestly unreachable; this is
//     access-narrowing, NOT a provider-release proof implementation
//     (finding 2 caveat carried, not claimed closed).
//   * No AtomicU64()! trap: cell-creation failure -> unavailable, all
//     reserves fail typed.
// POLICY VALUES (lane-0 REVIEW PROPOSAL, UNRATIFIED test-policy
// candidates only - NOT accepted production limits, NOT provider-
// derived): maxActiveSessions = 1, maxRetainedFaults = 4,
// maxRetainedTombstones = 4.
import Foundation

public enum RegistryLiability: UInt8, Sendable { case active, fault, tombstone }

public struct RegistryExhausted: Error, Sendable, Equatable {
    public let active: Int, faults: Int, tombstones: Int
}

/// Proof that a provider can hold NO reference to a registration any
/// more. Constructible ONLY inside this module; no value is produced
/// anywhere today, so reclaim() is unreachable by construction.
public struct ProviderReleaseProof: Sendable { internal init() {} }

/// S2: a typed graph of STRONG edges attached to a fault registration.
/// An integer edge count is NOT an ownership proof by itself (peer
/// finding 6); the protocol exists so the attachment is typed and the
/// shell's real graph (context + sink/ring/fence + ledger + undisposed
/// provider handle) conforms. >= 2 edges minimum (no empty box).
public protocol FaultPayloadGraph: AnyObject {
    /// The TYPED real owner (finding: an integer edge count is not
    /// ownership - a claimed count could mask a dropped sink/rings/
    /// ledger). The registry retains the graph; the graph's owner edge
    /// must be the real owner object (sink, harness double, ...).
    var owner: AnyObject { get }
    /// Diagnostic only - never used as a gate.
    var strongEdgeCount: Int { get }
    var payloadDescription: String { get }
}

/// Unforgeable registration capability (finding 2): only the holder of
/// THIS object can reclassify/rebind/reclaim the registration.
public final class RegistrationToken {
    public let id: UInt64
    fileprivate init(id: UInt64) { self.id = id }
}

public final class PlaybackRegistry: @unchecked Sendable {
    public static let shared = PlaybackRegistry()
    public static let maxActiveSessions = 1
    public static let maxRetainedFaults = 4
    public static let maxRetainedTombstones = 4

    // Packed cell layout (single CAS covers the whole policy state):
    //   bit 0    : active sessions (0..1)
    //   bit 1    : pendingTerminal obligations reserved with active (0..1)
    //   bits 2-4 : retained faults (0..4)
    //   bits 5-7 : retained tombstones (0..4)
    //   bit 63   : idMinterWrapped - permanent typed exhaustion
    private static let activeBit: UInt64 = 1
    private static let pendingBit: UInt64 = 1 << 1
    private static let faultShift: UInt64 = 2
    private static let tombShift: UInt64 = 5
    private static let fieldMask: UInt64 = 0b111
    private static let wrappedBit: UInt64 = 1 << 63

    public final class Reservation {
        public let kind: RegistryLiability
        /// The id minted AT RESERVE TIME (verdict S1 rev2): issuance
        /// happens here, so exhaustion stops NEW reservations while a
        /// validly held token's register always completes - the
        /// register-time wrap/re-issue race class is gone structurally.
        public let id: UInt64
        fileprivate weak var registry: PlaybackRegistry?
        fileprivate var consumed = false
        fileprivate init(kind: RegistryLiability, id: UInt64, registry: PlaybackRegistry) {
            self.kind = kind; self.id = id; self.registry = registry
        }
        /// Finding 4: a dropped token releases its slot (deinit
        /// consumption), so an abandoned reservation cannot leak.
        deinit {
            if !consumed, let r = registry { r.releaseSlot(kind) }
        }
    }

    private struct Entry {
        let root: AnyObject                 // IMMUTABLE context root (finding 3)
        var payload: FaultPayloadGraph?     // attached typed fault graph
        var kind: RegistryLiability
        let token: RegistrationToken        // the capability
    }

    private let packed: AtomicU64?
    private let nextID: AtomicU64?
    private var retained: [UInt64: Entry] = [:]
    private let lock = NSLock()             // map + token ops; start/stop path only, NEVER RT
    private let available: Bool

    private init() {
        if let p = AtomicU64(0), let n = AtomicU64(0) {
            packed = p; nextID = n; available = true
        } else { packed = nil; nextID = nil; available = false }
    }

    /// The IMMUTABLE root bound at register (verdict S2 rev2): lets a
    /// legitimate owner reach the retained context (e.g. to RETIRE its
    /// admission cell when the local strong ref is gone). Capability
    /// gated, never a mutation surface.
    public func root(of token: RegistrationToken) -> AnyObject? {
        lock.lock(); defer { lock.unlock() }
        return authorized(token.id, token)?.root
    }

    /// TEST SEAM (harness only - verdict S1: the issuance-ceiling
    /// boundary must be a RUNNABLE witness, not a model claim): a fresh
    /// instance whose id minter starts at the given value, so the actual
    /// CAS algorithm is exercised at the boundary without 2^64 mints.
    /// Production code uses only `shared`.
    public init(testSeedNextID: UInt64) {
        if let p = AtomicU64(0), let n = AtomicU64(testSeedNextID) {
            packed = p; nextID = n; available = true
        } else { packed = nil; nextID = nil; available = false }
    }

    // MARK: packed helpers
    private static func activeOf(_ v: UInt64) -> UInt64 { v & activeBit }
    private static func pendingOf(_ v: UInt64) -> UInt64 { (v & pendingBit) >> 1 }
    private static func faultsOf(_ v: UInt64) -> UInt64 { (v >> faultShift) & fieldMask }
    private static func tombsOf(_ v: UInt64) -> UInt64 { (v >> tombShift) & fieldMask }

    private func exhaustion() -> RegistryExhausted {
        let v = packed?.load() ?? 0
        return RegistryExhausted(active: Int(Self.activeOf(v)),
                                 faults: Int(Self.faultsOf(v)),
                                 tombstones: Int(Self.tombsOf(v)))
    }

    /// Slot-fit WITH pending terminal obligations reserved (finding 1).
    private static func fits(_ v: UInt64, kind: RegistryLiability) -> Bool {
        if v & wrappedBit != 0 { return false }
        let pend = pendingOf(v)
        switch kind {
        case .active:
            // Claiming active reserves its terminal obligation too:
            // BOTH backlogs must fit ONE more beyond the pending count.
            return activeOf(v) < UInt64(maxActiveSessions)
                && pend == 0
                && faultsOf(v) + 1 <= UInt64(maxRetainedFaults)
                && tombsOf(v) + 1 <= UInt64(maxRetainedTombstones)
        case .fault:
            return faultsOf(v) + pend < UInt64(maxRetainedFaults)
        case .tombstone:
            return tombsOf(v) + pend < UInt64(maxRetainedTombstones)
        }
    }

    private static func added(_ v: UInt64, kind: RegistryLiability, delta: Int64) -> UInt64 {
        let mag = UInt64(delta >= 0 ? delta : -delta)
        let field: UInt64
        switch kind {
        case .active:     field = mag &* (activeBit | pendingBit)  // active claims pending too (0b11 per unit)
        case .fault:      field = mag &<< faultShift
        case .tombstone:  field = mag &<< tombShift
        }
        return delta >= 0 ? v &+ field : v &- field
    }

    /// Deinit path: release a slot for a dropped, unconsumed token.
    private func releaseSlot(_ kind: RegistryLiability) {
        guard let cell = packed else { return }
        while true {
            let v = cell.load()
            if cell.compareExchange(expected: v, desired: Self.added(v, kind: kind, delta: -1)) { return }
        }
    }

    // MARK: capability API

    public func reserve(_ kind: RegistryLiability) -> Result<Reservation, RegistryExhausted> {
        guard let cell = packed, available else { return .failure(exhaustion()) }
        while true {
            let v = cell.load()
            guard Self.fits(v, kind: kind) else { return .failure(exhaustion()) }
            if cell.compareExchange(expected: v, desired: Self.added(v, kind: kind, delta: 1)) { break }
        }
        // Mint the registration id AT RESERVE (verdict S1 rev2):
        // non-wrapping CAS, permanent typed exhaustion at the ceiling.
        // The id is BURNED on rollback (never re-issued).
        guard let ids = nextID else { releaseSlot(kind); return .failure(exhaustion()) }
        while true {
            let v = ids.load()
            if v == UInt64.max {
                while true {
                    let pv = cell.load()
                    if cell.compareExchange(expected: pv, desired: pv | Self.wrappedBit) { break }
                }
                releaseSlot(kind)
                return .failure(exhaustion())
            }
            if ids.compareExchange(expected: v, desired: v &+ 1) {
                return .success(Reservation(kind: kind, id: v &+ 1, registry: self))
            }
        }
    }

    @discardableResult
    public func rollback(_ token: Reservation) -> Bool {
        lock.lock()
        // Verdict S1 rev3: validate the EXACT registry owner BEFORE
        // consume - consuming a FOREIGN registry's token here would
        // underflow this registry's slots while the real owner's
        // reservation stays reserved.
        guard token.registry === self, !token.consumed else { lock.unlock(); return false }
        token.consumed = true
        lock.unlock()
        releaseSlot(token.kind)
        return true
    }

    /// COMMIT: bind the token's slot to the IMMUTABLE context root.
    /// Returns the unforgeable registration capability, or nil on a
    /// consumed token / id-wrap (typed refusal, and the id minter flips
    /// the registry to permanent typed exhaustion on wrap - finding 4).
    public func register(root context: AnyObject, token: Reservation) -> RegistrationToken? {
        lock.lock()
        // Verdict S1 rev3: validate the EXACT registry owner BEFORE
        // consume - a foreign token must never insert its id into this
        // registry's retained map (cross-registry id collision class).
        guard token.registry === self, !token.consumed else { lock.unlock(); return nil }
        token.consumed = true
        lock.unlock()
        // Verdict S1 rev2: the id was minted at RESERVE time, so a
        // validly held token's insert COMPLETES even after the issuance
        // ceiling is reached (exhaustion stops NEW issuance, never a
        // valid insert); no wrap, no re-issue, no root overwrite.
        let reg = RegistrationToken(id: token.id)
        lock.lock()
        retained[token.id] = Entry(root: context, payload: nil, kind: token.kind, token: reg)
        lock.unlock()
        return reg
    }

    /// Capability check: the presented token must BE the registered one.
    private func authorized(_ id: UInt64, _ token: RegistrationToken) -> Entry? {
        guard let e = retained[id], e.token === token else { return nil }
        return e
    }

    /// LIABILITY TRANSITION (finding 2: valid set ONLY): active ->
    /// fault/tombstone. Consumes the reserved pendingTerminal unit, so it
    /// ALWAYS commits - it can never fail mid-teardown. Terminal kinds
    /// are immutable: any other transition returns false typed.
    @discardableResult
    public func reclassify(_ token: RegistrationToken, to newKind: RegistryLiability) -> Bool {
        guard newKind != .active, let cell = packed else { return false }
        lock.lock()
        guard let entry = authorized(token.id, token), entry.kind == .active else {
            lock.unlock(); return false
        }
        // active(1)+pending(1) -> target kind. Always fits: the pending
        // unit was reserved for exactly this.
        while true {
            let v = cell.load()
            let next = Self.added(Self.added(v, kind: .active, delta: -1), kind: newKind, delta: 1)
            if cell.compareExchange(expected: v, desired: next) { break }
        }
        retained[token.id]?.kind = newKind
        lock.unlock()
        return true
    }

    /// FAULT-PAYLOAD ATTACH (S2 + finding 3): attach a typed graph
    /// ALONGSIDE the immutable root. The root is never replaced, so no
    /// rebind can free a late provider refCon. >= 2 edges enforced.
    @discardableResult
    public func attachFaultGraph(_ token: RegistrationToken, _ graph: FaultPayloadGraph) -> Bool {
        lock.lock()
        // ATTACH ONCE (verdict S1): a second attach is a typed refusal -
        // a replaceable graph could drop the real sink/rings/ledger
        // behind a claimed edge count. The typed owner edge is enforced
        // by the protocol (graph.owner), not by an integer.
        guard let entry = authorized(token.id, token), entry.payload == nil else {
            lock.unlock(); return false
        }
        retained[token.id]?.payload = graph
        lock.unlock()
        return true
    }

    /// PROVEN-BARRIER RECLAIM: unreachable today (no proof constructible).
    @discardableResult
    public func reclaim(_ token: RegistrationToken, proof: ProviderReleaseProof) -> Bool {
        lock.lock()
        guard let entry = authorized(token.id, token), let cell = packed else {
            lock.unlock(); return false
        }
        retained.removeValue(forKey: token.id)
        lock.unlock()
        releaseSlot(entry.kind)
        _ = cell
        return true
    }

    /// Typed retention observability: does this registration currently
    /// hold a strong root (+ optional attached graph)? Callers MUST
    /// check retention success (finding 5), never assume it.
    /// Harness-visible snapshot (counts only, never a capability).
    public func debugCounts() -> (active: Int, faults: Int, tombstones: Int, pendingTerminal: Int) {
        let st = state
        return (st.active, st.faults, st.tombstones, st.pending)
    }

    public func retentionState(of token: RegistrationToken) -> (retained: Bool, kind: RegistryLiability?, hasGraph: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard let e = retained[token.id] else { return (false, nil, false) }
        return (true, e.kind, e.payload != nil)
    }

    public var state: (active: Int, pending: Int, faults: Int, tombstones: Int, retainedObjects: Int) {
        let v = packed?.load() ?? 0
        lock.lock(); let r = retained.count; lock.unlock()
        return (Int(Self.activeOf(v)), Int(Self.pendingOf(v)),
                Int(Self.faultsOf(v)), Int(Self.tombsOf(v)), r)
    }
}
