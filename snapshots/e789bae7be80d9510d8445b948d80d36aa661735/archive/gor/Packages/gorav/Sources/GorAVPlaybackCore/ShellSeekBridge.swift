// ShellSeekBridge (S5 shell integration): the shell-facing seek entry point.
// Owns ONE CoreSeekDriver per provider open and maps the contract outcome to the
// shell's barrier/revision semantics. The bridge NEVER attests a flush the receipt
// does not evidence: a committed seek attests .flushed ONLY when the nativeReady
// facts are complete (flushObserved + packetFeedReset + decoderReset +
// packetAccountingReconciled). Anything mutated-but-not-ready, or any nativeReady
// with incomplete facts (provider attested ready but the barrier is not
// attestable from the receipt), fails closed as requiresClose.
import Foundation
import GorAVNativeProbeKit

public enum ShellSeekResult: Sendable {
    /// nativeReady with COMPLETE barrier facts. Attests the NATIVE cleanup (flush +
    /// packet-feed reset + decoder reset + accounting) and that every subsequently
    /// delivered frame carries its true EventOrigin (retained pre-seek handles keep
    /// their OLD origin, so stale frames are identifiable, never invisible).
    /// .flushed is truthful ONLY together with consumer-side fencing: the shell adopts
    /// adoptRevision EXACTLY ONCE (the provider-reserved revision, via the core ACK -
    /// no second shell-side bump) and drops any frame whose origin.providerRevision
    /// differs from the adopted revision. The bridge provides the fence input; the
    /// consumer-path enforcement is the shell's obligation (pump revision stamp).
    case committedFlushed(receipt: SeekReceipt, adoptRevision: SeekRevision)
    /// No mutation (refused/cancelled pre-entry): revision UNCHANGED; resume is
    /// core-gated - the shell continues the current presentation, no barrier needed.
    case noMutationCoreGated(receipt: SeekReceipt)
    /// Admission refused before any reservation: typed reason, no state change.
    case admissionRefused(reason: CoreSeekAdmissionRefusal)
    /// Mutated non-ready outcome (poison, closeRequired) OR a nativeReady whose facts
    /// do not evidence the full flush path. The shell MUST close; no barrier attestation.
    case requiresClose(receipt: SeekReceipt)
}

/// What anchored the current fence binding.
public enum SeekFenceAnchor: Sendable, Equatable {
    case initialOpen                 // actual provider currentBinding() read at attach (no seek yet)
    case committedSeek(SeekEventIdentity)  // an ACTUAL committed receipt, identity-bound
}
/// Explicit (provider identity, session, revision) fence binding. NEVER a numeric
/// coincidence with the pump's core revision: the two counters have independent
/// bases/epochs, so the mapping is recorded here from ACTUAL provider state, and
/// any mismatch fails closed (no binding -> nothing admits).
public struct SeekFenceBinding: Sendable, Equatable {
    public let source: SourceToken
    public let session: SeekSessionID
    public let providerRevision: SeekRevision
    public let anchor: SeekFenceAnchor
    /// A delivered event is playable ONLY under the exact binding: source identity,
    /// session, AND provider revision all match. Old-origin (pre-seek, retained or
    /// delayed) and cross-session events are rejected; the caller MUST releaseFrame
    /// every rejected handle exactly once.
    public func admits(_ origin: EventOrigin) -> Bool {
        origin.source == source && origin.session == session && origin.providerRevision == providerRevision
    }
}

/// M3 wiring outcome: the bridge result PLUS the pump-reset arbitration, with an explicit
/// recovery state. A committed provider seek whose pump reset is refused leaves the provider
/// advanced and the pump stale - resume is PROHIBITED (close or an explicit caller re-sync);
/// a ledger note alone would hide the inconsistency.
public enum ShellSeekWiringOutcome: Sendable {
    case committedAndReset(receipt: SeekReceipt)          // single pump bump published
    case committedButPumpRefused(receipt: SeekReceipt)    // resume PROHIBITED: close or re-sync
    case noChange                                         // noMutation / admissionRefused
    case requiresClose(receipt: SeekReceipt)              // poison / unattestable barrier
}

public final class ShellSeekBridge: @unchecked Sendable {
    private let driver = CoreSeekDriver()
    private let fenceLock = NSLock()
    private var fence: SeekFenceBinding?
    /// The current fence binding; nil fails closed (after poison/close or before attach).
    public var currentFence: SeekFenceBinding? { fenceLock.lock(); defer { fenceLock.unlock() }; return fence }
    public init() {}
    /// Attach to an OPEN provider: establishes the initial binding from the ACTUAL
    /// currentBinding() (initialOpen anchor). Returns false (fail closed) when the
    /// provider has no current binding.
    @discardableResult
    public func attach(to provider: any CoreSeekProvider) -> Bool {
        guard let b = provider.currentBinding() else { return false }
        fenceLock.lock()
        fence = SeekFenceBinding(source: b.token, session: b.session, providerRevision: b.revision, anchor: .initialOpen)
        fenceLock.unlock()
        return true
    }
    /// Validate a committed receipt against the provider's ACTUAL current binding:
    /// identity source, session, and nextRevision must all be current, else fail closed.
    private func bindCommitted(_ receipt: SeekReceipt, _ provider: any CoreSeekProvider) -> Bool {
        guard let b = provider.currentBinding(),
              b.token == receipt.identity.source,
              b.session == receipt.session,
              b.revision == receipt.nextRevision else { return false }
        fenceLock.lock()
        fence = SeekFenceBinding(source: b.token, session: b.session, providerRevision: b.revision,
                                 anchor: .committedSeek(receipt.identity))
        fenceLock.unlock()
        return true
    }
    private func clearFence() { fenceLock.lock(); fence = nil; fenceLock.unlock() }
    /// Call-time validation for the shell barrier: the current fence must exist, anchor a
    /// COMMITTED seek, AND still match the provider's ACTUAL current binding (source identity,
    /// session, revision). Anything less fails closed. Used by ShellFrameSource.coordinateSeek
    /// so a superseded or cross-session anchor can never attest a flush.
    public func fenceMatchesProvider(_ provider: any CoreSeekProvider) -> Bool {
        guard let f = currentFence, case .committedSeek = f.anchor,
              let b = provider.currentBinding(),
              b.token == f.source, b.session == f.session, b.revision == f.providerRevision
        else { return false }
        return true
    }
    /// True while a seek transaction is in flight (for shell UI gating).
    public var hasActiveSeek: Bool { driver.hasActiveTransaction }
    /// Core-initiated cancellation of the in-flight seek (user cancel during a held call).
    /// No-op when idle; provider arbitration decides cancel-vs-ready.
    public func cancelActiveSeek() { driver.requestCancellationOfActive() }

    public func seek(on provider: any CoreSeekProvider, position: RationalTime,
                     commitACK: @Sendable (SeekRevision, SeekReceipt) -> Void) async -> ShellSeekResult {
        switch await driver.seek(on: provider, position: position, commitACK: commitACK) {
        case .committed(let receipt):
            guard case .nativeReady(let facts) = receipt.outcome,
                  facts.flushObserved, facts.packetFeedReset,
                  facts.decoderReset, facts.packetAccountingReconciled else {
                clearFence(); return .requiresClose(receipt: receipt) // barrier not attestable: fail closed
            }
            guard bindCommitted(receipt, provider) else {
                clearFence(); return .requiresClose(receipt: receipt) // commit/binding mismatch: fail closed
            }
            return .committedFlushed(receipt: receipt, adoptRevision: receipt.nextRevision)
        case .noMutation(let receipt):
            return .noMutationCoreGated(receipt: receipt)   // revision unchanged: fence stays valid
        case .failedPoisoned(let receipt):
            clearFence(); return .requiresClose(receipt: receipt)
        case .admissionRefused(let reason):
            return .admissionRefused(reason: reason)
        }
    }
}
