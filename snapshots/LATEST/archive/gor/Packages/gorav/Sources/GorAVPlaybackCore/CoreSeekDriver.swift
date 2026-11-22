import Foundation
import GorAVCore
import GorAVNativeProbeKit

/// S5 integration (R2Y core lane): the CORE-side seek driver. The core owns correlation/queue-turn
/// minting and the commit ACK; the provider (peer) owns the native boundary. Contract invariants
/// enforced here:
///  - revision advances ONLY on nativeReady (the commit ACK); refused/cancelled no-mutation
///    outcomes leave the revision untouched and resume core-gated (never provider-success-gated);
///  - PINNED HANDSHAKE: the core ADOPTS the provider-issued reservedRevision; it never holds a
///    separately reserved revision;
///  - BACKWARD keyframe request only (flags bit 0); exact/ceil targets are not expressible here;
///  - provider receipts never carry a global commit - the ACK callback is the core's only commit.
public protocol CoreSeekProvider: Sendable {
    func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)?
    func tryBegin(_ request: SeekRequest) throws -> any SeekTransaction
}

public enum CoreSeekAdmissionRefusal: Sendable, Equatable {
    case noSource            // no current binding (nothing open / poisoned / closing)
    case busy                // an active transaction occupies the provider slot
    case stale               // core's expected revision != provider's current at queue-turn
    case closed
    case unsupported(String)
    case legacyRejected
    case correlationExhausted
}

public enum CoreSeekOutcome: Sendable {
    case committed(receipt: SeekReceipt)      // nativeReady: ACK fired with the adopted revision
    case noMutation(receipt: SeekReceipt)     // refused/cancelled: revision UNCHANGED, core-gated resume
    case failedPoisoned(receipt: SeekReceipt) // failed/cancelledAfterCleanup: poison, closeRequired
    case admissionRefused(reason: CoreSeekAdmissionRefusal)
}

public final class CoreSeekDriver: @unchecked Sendable {
    private let lock = NSLock()
    private var lastCorrelation: UInt64 = 0
    private var lastQueueTurn: UInt64 = 0
    private var active: (any SeekTransaction)?   // for core-initiated cancellation; never executed twice
    /// Lock-guarded activity read for the shell bridge: true while a transaction is in flight.
    public var hasActiveTransaction: Bool { lock.lock(); defer { lock.unlock() }; return active != nil }
    public init() {}
    /// TEST SEAM (harness only): seed the mint so exhaustion is a runnable witness. Production uses init().
    public init(testSeed correlation: UInt64, queueTurn: UInt64) {
        lastCorrelation = correlation; lastQueueTurn = queueTurn
    }
    /// Core-initiated cancellation of the in-flight transaction (e.g. user cancel during a held
    /// native call). Idempotent-safe: the provider arbitrates first-recorded winner; if no
    /// transaction is active this is a no-op, never an error.
    public func requestCancellationOfActive() {
        lock.lock(); let txn = active; lock.unlock()
        txn?.requestCancellation()
    }
    private func nextIDs() -> (UInt64, UInt64)? {
        lock.lock(); defer { lock.unlock() }
        let (c, oc) = lastCorrelation.addingReportingOverflow(1)
        let (t, ot) = lastQueueTurn.addingReportingOverflow(1)
        guard !oc, !ot else { return nil }   // saturating exhaustion, NEVER a wrap
        lastCorrelation = c; lastQueueTurn = t; return (c, t)
    }
    /// One core seek turn. `commitACK` fires EXACTLY once, only on nativeReady, with the adopted
    /// (provider-issued) revision - wire it to the PresentationRevision bump; no other outcome
    /// may advance any core-visible revision.
    public func seek(on provider: any CoreSeekProvider, position: RationalTime,
                     commitACK: @Sendable (SeekRevision, SeekReceipt) -> Void) async -> CoreSeekOutcome {
        guard let binding = provider.currentBinding() else { return .admissionRefused(reason: .noSource) }
        guard let ids = nextIDs(),
              let cid = try? SeekCorrelationID(rawValue: ids.0, queueTurn: ids.1) else {
            return .admissionRefused(reason: .correlationExhausted)
        }
        let target = SeekTarget(position: position, rounding: .floorToKeyframe, requestedFlags: 1)
        let request = SeekRequest(correlationID: cid, session: binding.session, source: binding.token,
                                  target: target, expectedRevision: binding.revision)
        let txn: any SeekTransaction
        do { txn = try provider.tryBegin(request) }
        catch SeekRefusal.busy { return .admissionRefused(reason: .busy) }
        catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
        catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
        catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
        catch { return .admissionRefused(reason: .unsupported("\(error)")) }
        let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
        lock.lock(); active = txn; lock.unlock()
        defer { lock.lock(); active = nil; lock.unlock() }
        do { try txn.execute() }
        catch {
            txn.requestCancellation()
            _ = await txn.completion()
            return .admissionRefused(reason: .unsupported("execute misuse: \(error)"))
        }
        let receipt = await txn.completion()
        switch receipt.outcome {
        case .nativeReady:
            commitACK(adopted, receipt)          // the ONLY advance path in the whole flow
            return .committed(receipt: receipt)
        case .refusedNoMutation, .cancelledNoMutation:
            return .noMutation(receipt: receipt) // revision untouched; resume is core-gated
        default:
            return .failedPoisoned(receipt: receipt)
        }
    }
}
