// GorAVSeekContract.swift v3 — shared seek contract, PROVIDER-ONLY scope (revise batch, v3 findings 1-8).
// Placement: Sources/GorAVNativeProbeKit/GorAVSeekContract.swift (explicit-sources target; Package.swift
// hunk by R2Y, sole Package.swift writer). Peer (goreda) sole-writes this file after Main's explicit start.
// Scope: the provider (FFmpeg) boundary only. Global commit / display reanchor / first-out / core ACK are
// NOT provider outcomes. NativeReady promises NATIVE REPOSITION + FLUSH ONLY - not target attainment,
// not a decoded PTS, never a global commit.

import Foundation

// MARK: - Errors

public enum SeekIssuanceError: Error, Sendable, Equatable {
    case exhausted            // ID/revision/generation space exhausted; typed refusal, NEVER a wrap
    case invalidIdentifier    // zero or otherwise invalid identity material
}

public enum SeekTimeError: Error, Sendable, Equatable {
    case invalidTimescale     // timescale <= 0: a TIME error, not an identity error
    case overflow             // checked rational arithmetic overflow
    case unknownOrigin        // conversion requested against an unknown stream origin
    case targetBeforeOrigin   // negative-position target before the stream start origin
}

// MARK: - Identity (roles never conflated; identity is COMPOSITE source+transaction)

public struct SeekCorrelationID: Hashable, Sendable {
    public let rawValue: UInt64   // nonzero
    public let queueTurn: UInt64  // owned and minted solely by the core queue; provider stores/echoes only
    public init(rawValue: UInt64, queueTurn: UInt64) throws {
        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }
        self.rawValue = rawValue
        self.queueTurn = queueTurn
    }
}

public struct SeekTransactionID: Hashable, Sendable, Comparable {
    public let rawValue: UInt64   // nonzero; meaningful only as part of SeekEventIdentity
    public init(rawValue: UInt64) throws {
        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }
        self.rawValue = rawValue
    }
    public static func < (l: SeekTransactionID, r: SeekTransactionID) -> Bool { l.rawValue < r.rawValue }
}

/// Composite identity (finding 5): a transaction ID is unique only within its source. Every receipt,
/// envelope and refusal that names a transaction names this composite.
public struct SeekEventIdentity: Hashable, Sendable {
    public let source: SourceToken
    public let transactionID: SeekTransactionID
    public init(source: SourceToken, transactionID: SeekTransactionID) {
        self.source = source
        self.transactionID = transactionID
    }
}

/// Provider-held, noncopyable, synchronized mint (finding 5). One instance per provider, held for the
/// provider's lifetime; value-type copies cannot duplicate issuance. Saturates to an explicit exhausted
/// state; never wraps.
public final class TransactionIDMint: @unchecked Sendable {  // NSLock-guarded mutable state
    private let lock = NSLock()
    private var next: UInt64 = 1
    private var exhausted = false
    public init() {}
    public func issue() throws -> SeekTransactionID {
        lock.lock(); defer { lock.unlock() }
        guard !exhausted else { throw SeekIssuanceError.exhausted }
        let id = try SeekTransactionID(rawValue: next)
        if next == UInt64.max { exhausted = true } else { next += 1 }
        return id
    }
}

public struct SeekSessionID: Hashable, Sendable {
    public let rawValue: UInt64   // nonzero
    public init(rawValue: UInt64) throws {
        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }
        self.rawValue = rawValue
    }
}

/// Source identity: provider-minted instance + open generation starting at 1, incrementing per open,
/// NEVER reset on reopen. Failed open consumes nothing and yields no token (typed error).
public struct SourceToken: Hashable, Sendable {
    public let instanceID: UInt64      // nonzero; provider-minted, never caller-supplied
    public let openGeneration: UInt64  // >= 1
    public init(instanceID: UInt64, openGeneration: UInt64) throws {
        guard instanceID != 0, openGeneration != 0 else { throw SeekIssuanceError.invalidIdentifier }
        self.instanceID = instanceID
        self.openGeneration = openGeneration
    }
}

/// Sole construction path for genuine source tokens (finding 4): the provider mints BOTH the instance
/// ID and the generation; caller-supplied instance IDs never establish identity. A failed open throws
/// and consumes neither an instance ID nor a generation.
public protocol SourceTokenIssuing: Sendable {
    func issueOpen() throws -> SourceToken
}

public struct SeekRevision: Hashable, Sendable, Comparable {
    public let rawValue: UInt64   // nonzero; 1 at open, first seek becomes 2
    public static let atOpen = try! SeekRevision(rawValue: 1)
    public init(rawValue: UInt64) throws {
        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }
        self.rawValue = rawValue
    }
    public func advanced() throws -> SeekRevision {
        let (v, ov) = rawValue.addingReportingOverflow(1)
        guard !ov, v != 0 else { throw SeekIssuanceError.exhausted }
        return try SeekRevision(rawValue: v)
    }
    public static func < (l: SeekRevision, r: SeekRevision) -> Bool { l.rawValue < r.rawValue }
}

// MARK: - Time (integer rational; normalized equality+hash consistent with Comparable; checked math)

public struct RationalTime: Sendable {
    public let value: Int64      // may be negative (negative stream origin)
    public let timescale: Int32  // > 0
    public init(value: Int64, timescale: Int32) throws {
        guard timescale > 0 else { throw SeekTimeError.invalidTimescale }
        self.value = value
        self.timescale = timescale
    }
    /// Canonical form (reduced by gcd, positive timescale). Hash/equality are defined on this form.
    public var normalized: RationalTime {
        let mag = value.magnitude
        let ts = UInt64(bitPattern: Int64(timescale))
        var a = mag, b = ts
        while b != 0 { let t = a % b; a = b; b = t }
        let g = a == 0 ? 1 : a
        let red = mag / g
        let nv: Int64
        if value < 0 { nv = red == (1 << 63) ? Int64.min : -Int64(red) } else { nv = Int64(red) }
        let nts = Int32(ts / g)
        return try! RationalTime(value: nv, timescale: nts)
    }
    /// Exact tick conversion for a REAL FFmpeg rational time_base (v4 delta 1): given a timebase
    /// num/den (e.g. 1001/30000: num=1001, den=30000 ticks per second), returns
    /// floor(value * den / (timescale * num)) - media-RELATIVE ticks from the stream start.
    /// Two-limb wide intermediate arithmetic; mathematical floor exact for negatives; overflow-checked;
    /// no Double, no dropped denominator. The caller then adds stream.start_time with a checked add
    /// (unknown origin and negative relative targets are refused BEFORE mutation at tryBegin).
    /// This is pure arithmetic - a successful av_seek_frame + flush does NOT prove exact or nearest
    /// landing; only BACKWARD keyframe request is supported, exact/ceil/incompatible flags are
    /// refused pre-mutation.
    public func floorTicks(toTimebaseNumerator num: Int64, denominator den: Int64) throws -> Int64 {
        guard num > 0, den > 0 else { throw SeekTimeError.invalidTimescale }
        // Unsigned 128-bit long division using two standard-library UInt64 limbs. Both
        // numerator (<2^127) and divisor (<2^95) fit without Int128 or OS-floor changes.
        let product = value.magnitude.multipliedFullWidth(by: UInt64(den))
        let divisor = UInt64(timescale).multipliedFullWidth(by: UInt64(num))
        var remHigh: UInt64 = 0, remLow: UInt64 = 0
        var qHigh: UInt64 = 0, qLow: UInt64 = 0
        for bit in stride(from: 127, through: 0, by: -1) {
            let incoming = bit >= 64 ? (product.high >> UInt64(bit - 64)) & 1 : (product.low >> UInt64(bit)) & 1
            remHigh = (remHigh << 1) | (remLow >> 63)
            remLow = (remLow << 1) | incoming
            if remHigh > divisor.high || (remHigh == divisor.high && remLow >= divisor.low) {
                let (low, borrow) = remLow.subtractingReportingOverflow(divisor.low)
                remLow = low
                remHigh = remHigh - divisor.high - (borrow ? 1 : 0)
                if bit >= 64 { qHigh |= UInt64(1) << UInt64(bit - 64) }
                else { qLow |= UInt64(1) << UInt64(bit) }
            }
        }
        guard qHigh == 0 else { throw SeekTimeError.overflow }
        if value >= 0 {
            guard qLow <= UInt64(Int64.max) else { throw SeekTimeError.overflow }
            return Int64(qLow)
        }
        let hasRemainder = remHigh != 0 || remLow != 0
        let limit = UInt64(1) << 63
        guard qLow <= limit, !(qLow == limit && hasRemainder) else { throw SeekTimeError.overflow }
        if qLow == limit { return Int64.min }
        return hasRemainder ? -Int64(qLow) - 1 : -Int64(qLow)
    }
    /// Convenience for integral timescales (1 second = ts ticks), same checked semantics.
    public func floorTicks(toTimescale ts: Int32) throws -> Int64 {
        try floorTicks(toTimebaseNumerator: 1, denominator: Int64(ts))
    }
    /// Checked composition with the stream origin: deltaTicks + startTimeTicks, overflow-checked.
    /// Unknown origin is refused by the caller pre-mutation; a negative ORIGIN is legal here.
    public static func checkedOriginSum(deltaTicks: Int64, startTimeTicks: Int64) throws -> Int64 {
        let (v, ov) = deltaTicks.addingReportingOverflow(startTimeTicks)
        guard !ov else { throw SeekTimeError.overflow }
        return v
    }
    /// Checked conversion to a target timescale (floor on inexact), negative-safe.
    public func rescaled(to ts: Int32) throws -> RationalTime {
        let ticks = try floorTicks(toTimescale: ts)
        return try RationalTime(value: ticks, timescale: ts)
    }
}

extension RationalTime: Equatable {
    /// Cross-product equality on 128-bit products: a/b == c/d  <=>  a*d == c*b (b,d > 0).
    /// Agrees with `normalized`-based hashing: equal rationals normalize identically.
    public static func == (l: RationalTime, r: RationalTime) -> Bool {
        let lp = l.value.multipliedFullWidth(by: Int64(r.timescale))
        let rp = r.value.multipliedFullWidth(by: Int64(l.timescale))
        return lp.high == rp.high && lp.low == rp.low
    }
}

extension RationalTime: Hashable {
    public func hash(into hasher: inout Hasher) {
        let n = normalized
        hasher.combine(n.value)
        hasher.combine(n.timescale)
    }
}

extension RationalTime: Comparable {
    /// 128-bit cross-product comparison; exact for all inputs including negative origins.
    /// Consistent with Equatable: neither-less implies ==. No Double anywhere.
    public static func < (l: RationalTime, r: RationalTime) -> Bool {
        let lp = l.value.multipliedFullWidth(by: Int64(r.timescale))
        let rp = r.value.multipliedFullWidth(by: Int64(l.timescale))
        if lp.high != rp.high { return lp.high < rp.high }
        return lp.low < rp.low
    }
}

// MARK: - Target coordinate (finding 1: ONE coordinate, explicit)

/// The single target coordinate: MEDIA-RELATIVE rational seconds from the stream start (v4 delta 1).
/// Conversion: deltaTicks = position.floorTicks(toTimebaseNumerator: tb.num, denominator: tb.den)
/// for the stream's real rational time_base, then RationalTime.checkedOriginSum(deltaTicks:,
/// startTimeTicks: origin). A NEGATIVE relative target (before stream start) is rejected
/// (SeekTimeError.targetBeforeOrigin) BEFORE mutation; a negative ORIGIN is legal and exact; an
/// UNKNOWN origin is refused BEFORE mutation. Only BACKWARD keyframe request is supported:
/// exact/ceil/incompatible flags are refused PRE-MUTATION (tryBegin, .unsupported); av_seek_frame
/// BACKWARD + flush does not prove exact or nearest landing. A post-mutation miss is NEVER noMutation.
public enum SeekRounding: String, Sendable {
    case exact           // land on the exact tick or refuse PRE-MUTATION
    case floorToKeyframe // BACKWARD request only; nearest/exact landing is not promised
    case ceilToKeyframe  // nearest keyframe at or after the converted tick
}

public struct SeekTarget: Sendable {
    public let position: RationalTime      // media-timeline seconds (the ONE coordinate)
    public let rounding: SeekRounding
    public let requestedFlags: Int32       // whitelisted AVSEEK_FLAG_* bits; actual use recorded in facts
    public init(position: RationalTime, rounding: SeekRounding, requestedFlags: Int32) {
        self.position = position
        self.rounding = rounding
        self.requestedFlags = requestedFlags
    }
}

// MARK: - Request

public struct SeekRequest: Sendable {
    public let correlationID: SeekCorrelationID
    public let session: SeekSessionID
    public let source: SourceToken
    public let target: SeekTarget
    /// Core's expected current provider revision; provider validates expected == actual at queue-turn
    /// (mismatch => .stale) and computes next = expected.advanced().
    public let expectedRevision: SeekRevision
    public init(correlationID: SeekCorrelationID, session: SeekSessionID, source: SourceToken,
                target: SeekTarget, expectedRevision: SeekRevision) {
        self.correlationID = correlationID
        self.session = session
        self.source = source
        self.target = target
        self.expectedRevision = expectedRevision
    }
}

// MARK: - Descriptor + discovery (finding 4)

/// Renamed (finding 4): GorAVCore and NativeProbeKit both declare SourceDescriptor; this contract's
/// descriptor is SeekSourceDescriptor to keep decoder/open call sites unambiguous when a caller
/// imports both modules.
public struct SeekSourceDescriptor: Sendable {
    public let source: SourceToken
    public let seekable: Bool
    public let originKnown: Bool
    public let startOrigin: RationalTime?    // nil == unknown origin; conversions then refuse
    public let duration: RationalTime?
    public let videoStreamIndex: Int32?
    public let streamTimebase: RationalTime?
    public init(source: SourceToken, seekable: Bool, originKnown: Bool, startOrigin: RationalTime?,
                duration: RationalTime?, videoStreamIndex: Int32?, streamTimebase: RationalTime?) {
        self.source = source
        self.seekable = seekable
        self.originKnown = originKnown
        self.startOrigin = startOrigin
        self.duration = duration
        self.videoStreamIndex = videoStreamIndex
        self.streamTimebase = streamTimebase
    }
}

public struct SeekCapabilities: Sendable {
    public let seekable: Bool
    public let supportedRoundings: Set<SeekRounding>
    public let supportedFlags: Int32
    public let originKnown: Bool
    public init(seekable: Bool, supportedRoundings: Set<SeekRounding>, supportedFlags: Int32,
                originKnown: Bool) {
        self.seekable = seekable
        self.supportedRoundings = supportedRoundings
        self.supportedFlags = supportedFlags
        self.originKnown = originKnown
    }
}

/// Queue-owned, NON-BLOCKING open-binding discovery (finding 4): the genuine current source token,
/// session and revision, plus capability advertisement. tryBegin never blocks on discovery.
public protocol SeekProviderDiscovery: Sendable {
    func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)?
    func capabilities() -> SeekCapabilities
}

// MARK: - Typed refusals (admission-time ONLY; after admission every outcome is a receipt)

public enum SeekRefusal: Error, Sendable, Equatable {
    case busy(active: SeekEventIdentity)                     // active slot occupied; busy is observable
    case exhausted                                           // ID/revision/generation exhaustion; no wrap
    case stale(expected: SeekRevision, actual: SeekRevision) // revision mismatch at queue-turn
    case unsupported(String)                                 // incl. exact/ceil/flags refused PRE-MUTATION
    case closed                                              // session/source closed
    case legacyRejected(reason: String)                      // unenveloped/legacy event or handle refused
    case alreadyExecuted                                     // the ONLY post-admission throwing misuse
}

// MARK: - Provider stages, arbitration, mutation facts

public enum ProviderSeekStage: String, Sendable {
    case reserved, preSeek, inNativeSeek, nativeReturned, cleanedUp, receipted, retired
}

/// Cancel-vs-NativeReady arbitration: the FIRST recorded event wins; recorded once, never rewritten.
/// Kept SEPARATE from the actual reached cleanup stage (finding 8).
public enum SeekArbitration: String, Sendable {
    case none, cancellationRequested, nativeReadyObserved
}

public struct NativeSeekFacts: Sendable {
    public let avSeekReturn: Int32?              // actual av_seek_frame return code; nil if never entered
    public let flagsApplied: Int32
    public let resolvedStreamIndex: Int32?
    public let requestedTicks: Int64?            // target after origin+timebase conversion
    public let resolvedStreamTimebase: RationalTime?
    public let startOriginTicks: Int64?          // may be negative
    public let flushObserved: Bool
    public let packetFeedReset: Bool             // feed reset actually performed
    public let decoderReset: Bool
    public let packetsReleased: Int?             // explicit packet release count (nil if no mutation)
    public let packetAccountingReconciled: Bool  // admission/release ledger reconciled
    public init(avSeekReturn: Int32?, flagsApplied: Int32, resolvedStreamIndex: Int32?,
                requestedTicks: Int64?, resolvedStreamTimebase: RationalTime?,
                startOriginTicks: Int64?, flushObserved: Bool, packetFeedReset: Bool,
                decoderReset: Bool, packetsReleased: Int?, packetAccountingReconciled: Bool) {
        self.avSeekReturn = avSeekReturn
        self.flagsApplied = flagsApplied
        self.resolvedStreamIndex = resolvedStreamIndex
        self.requestedTicks = requestedTicks
        self.resolvedStreamTimebase = resolvedStreamTimebase
        self.startOriginTicks = startOriginTicks
        self.flushObserved = flushObserved
        self.packetFeedReset = packetFeedReset
        self.decoderReset = decoderReset
        self.packetsReleased = packetsReleased
        self.packetAccountingReconciled = packetAccountingReconciled
    }
}

public enum MutationState: String, Sendable {
    case none, partial, completedClean
}

/// Recovery paths (finding 8): nativeReady is the ONLY notRequired outcome and the ONLY one that
/// advances the revision and permits new output. Partial mutation, post-mutation cancellation and
/// session-IO escalation ALL require closeRequired - no flushOnly/resume loophole, no new seek or
/// reopen on the same session.
public enum RecoveryPath: String, Sendable {
    case notRequired    // nativeReady only
    case closeRequired  // mandatory for any mutated non-nativeReady outcome and session-IO escalation
}

public struct PoisonReport: Sendable {
    public let recoveryRequired: Bool   // true whenever mutation != .none and outcome != nativeReady
    public let recoveryPath: RecoveryPath
    public let detail: String
    public init(recoveryRequired: Bool, recoveryPath: RecoveryPath, detail: String) {
        self.recoveryRequired = recoveryRequired
        self.recoveryPath = recoveryPath
        self.detail = detail
    }
    /// Invariant helpers: the only two legal combinations for a mutated non-nativeReady outcome.
    public static let cleanNativeReady = PoisonReport(recoveryRequired: false, recoveryPath: .notRequired, detail: "")
    public static func closeRequired(_ detail: String) -> PoisonReport {
        PoisonReport(recoveryRequired: true, recoveryPath: .closeRequired, detail: detail)
    }
}

public enum ResumePolicy: String, Sendable {
    case resumeFromNativePosition // nativeReady only (provider success)
    case unchangedCoreGated       // noMutation outcomes: position/revision unchanged; the CORE gates
    case closedRequired           // every mutated non-nativeReady outcome
}

public enum SeekFailureReason: Sendable, Equatable {
    case avError(code: Int32)
    case streamResolutionFailed
    case interruptCancelled
    case poisonedState
    case sessionClosed
    case descriptorUnsupported(String)
}

// MARK: - Receipt (exactly one immutable completion per ADMITTED reservation; never throws)

public struct SeekReceipt: Sendable {
    /// Why an ADMITTED reservation was refused at queue-turn WITHOUT mutation (v4 delta 2).
    /// Distinct from cancellation: the caller did not ask to cancel; the provider refused.
    public enum NoMutationRefusal: Sendable, Equatable {
        case stale(expected: SeekRevision, actual: SeekRevision)
        case closed
        case unsupported(String)
    }
    /// Why an admitted reservation was cancelled WITHOUT mutation.
    public enum CancelReason: String, Sendable {
        case requested   // explicit requestCancellation before execute
        case abandoned   // handle released without execute/cancel: lease-release settlement, no orphan
        case close       // close() settlement before execute
    }
    public enum Outcome: Sendable {
        /// Provider completion evidence ONLY: native reposition + flush promised, revision advances,
        /// new output permitted. NOT target attainment, NOT a decoded PTS, NOT a global commit/ACK.
        /// The ONLY outcome that advances nextRevision.
        case nativeReady(facts: NativeSeekFacts)
        /// Admitted, then REFUSED at queue-turn before any mutation: position and revision UNCHANGED.
        /// Resume is CORE-GATED (the core decides the next action) - NOT a provider success signal.
        case refusedNoMutation(reason: NoMutationRefusal)
        /// Caller-side settlement before any mutation (requested/abandoned/close). Position and
        /// revision UNCHANGED; resume is CORE-GATED. Exactly-one reservation release.
        case cancelledNoMutation(reason: CancelReason)
        /// Post-mutation cancel: native call ran to its own return, cleanup completed with resources
        /// alive. Poison is MANDATORY and is always closeRequired.
        case cancelledAfterCleanup(facts: NativeSeekFacts, poison: PoisonReport)
        /// Typed staged failure at the ACTUAL stage; poison MANDATORY, closeRequired when mutated.
        case failed(stage: ProviderSeekStage, reason: SeekFailureReason,
                    facts: NativeSeekFacts, poison: PoisonReport)
    }
    public let identity: SeekEventIdentity       // composite source+transaction
    public let correlationID: SeekCorrelationID
    public let session: SeekSessionID
    public let request: SeekRequest              // original target preserved verbatim
    public let previousRevision: SeekRevision
    public let nextRevision: SeekRevision        // advanced ONLY on nativeReady
    public let reachedStage: ProviderSeekStage   // actual cleanup stage reached
    public let arbitration: SeekArbitration      // first-recorded winner; separate from reachedStage
    public let mutation: MutationState
    public let resumePolicy: ResumePolicy
    public let outcome: Outcome
    public init(identity: SeekEventIdentity, correlationID: SeekCorrelationID, session: SeekSessionID,
                request: SeekRequest, previousRevision: SeekRevision, nextRevision: SeekRevision,
                reachedStage: ProviderSeekStage, arbitration: SeekArbitration, mutation: MutationState,
                resumePolicy: ResumePolicy, outcome: Outcome) {
        self.identity = identity
        self.correlationID = correlationID
        self.session = session
        self.request = request
        self.previousRevision = previousRevision
        self.nextRevision = nextRevision
        self.reachedStage = reachedStage
        self.arbitration = arbitration
        self.mutation = mutation
        self.resumePolicy = resumePolicy
        self.outcome = outcome
    }
}

// MARK: - Transaction handle (finding 7: after admission, NO throwing paths except duplicate execute)

/// Ownership and completion invariants:
/// - tryBegin admission is the only gate that refuses; every ADMITTED reservation produces exactly
///   one immutable SeekReceipt - including queue-time stale/closed discovery after admission,
///   cancel-before-execute, abandonment, and close settlement.
/// - execute() moves reserved -> in-flight exactly once; the ONLY throwing misuse is a duplicate
///   execute (.alreadyExecuted).
/// - completion() NEVER throws; repeated calls return the SAME receipt value. Calling it before
///   execute is legal: it suspends until execute, cancellation, abandonment or close settles the
///   transaction (no wait-forever: requestCancellation() or close() always settles a pre-execute
///   transaction as cancelledNoMutation). Abandonment is settlement by lease release: dropping an
///   un-executed handle is collected and completed as cancelledNoMutation(.abandoned) - never an
///   orphaned reservation.
/// - requestCancellation() is a REQUEST: pre-mutation => cancelledNoMutation; post-entry => the
///   native call is never abandoned/freed/reopened/superseded while active; after it returns,
///   cleanup completes with resources alive; receipt is cancelledAfterCleanup or failed.
public protocol SeekTransaction: Sendable {
    var identity: SeekEventIdentity { get }
    var correlationID: SeekCorrelationID { get }
    var session: SeekSessionID { get }
    var request: SeekRequest { get }
    /// Provider-issued reserved revision (= expectedRevision.advanced() as validated at queue-turn).
    /// PINNED HANDSHAKE (finding 2): the provider validates expected and computes next; the core
    /// ADOPTS this issued value before execute and does not hold a separately reserved revision.
    var reservedRevision: SeekRevision { get }
    func execute() throws
    func completion() async -> SeekReceipt
    func requestCancellation()
}

// MARK: - Provider surface

public protocol SeekProviding: Sendable {
    func descriptor(for source: SourceToken) throws -> SeekSourceDescriptor
    /// Admits at most one active transaction. Checks expectedRevision at queue-turn (.stale),
    /// capabilities (.unsupported PRE-MUTATION), slot (.busy). Throws SeekRefusal; after admission
    /// the transaction ALWAYS completes via a receipt.
    func tryBegin(_ request: SeekRequest) throws -> any SeekTransaction
    var activeTransaction: SeekEventIdentity? { get }
    /// Close ownership: provider-owned, exactly-once. Waits for any in-flight native call to return,
    /// then for outstanding retained-handle copy/release turns; completes every admitted-but-unsettled
    /// transaction exactly once (pre-mutation as cancelledNoMutation; in-flight after native return
    /// and cleanup as cancelledAfterCleanup or failed). No late continuation runs after close; no
    /// use-after-free. After close, all calls throw .closed and the event stream ends with .closed.
    func close() async throws
}

// MARK: - Provider events (finding 6: envelope the CONCRETE DecodeEvent surface + bound sentinels)

public enum RequestOrigin: Sendable, Hashable {
    case initialOpen
    case transaction(SeekTransactionID)   // composite with EventOrigin.source
}

public struct EventOrigin: Sendable, Hashable {
    public let session: SeekSessionID
    public let source: SourceToken
    public let providerRevision: SeekRevision
    public let requestOrigin: RequestOrigin
    public init(session: SeekSessionID, source: SourceToken, providerRevision: SeekRevision,
                requestOrigin: RequestOrigin) {
        self.session = session
        self.source = source
        self.providerRevision = providerRevision
        self.requestOrigin = requestOrigin
    }
}

/// The provider event stream: every variant of the concrete DecodeEvent surface, origin-bound, plus
/// explicit drained/closed sentinels. The read API never answers an untagged nil end: the stream
/// terminates only AFTER a terminal sentinel (endOfStream or failed or interrupted), then .drained
/// once all delivered handles are released or accounted, then .closed at close. Mixed legacy policy:
/// any event or handle lacking a full EventOrigin is REFUSED with .legacyRejected - never retagged.
public enum SeekProviderEvent<Frame: Sendable>: Sendable {
    case opened(EventOrigin, videoCodec: String, width: Int, height: Int)
    case frameDecoded(EventOrigin, Frame)
    case endOfStream(EventOrigin)
    case interrupted(EventOrigin)
    case failed(EventOrigin, code: Int32, summary: String)
    case feedSaturated(EventOrigin, pendingPackets: Int)
    case drained(EventOrigin)
    case closed(EventOrigin)
}

public protocol SeekEventReading: Sendable {
    associatedtype Frame: Sendable
    /// Suspends until the next event; the stream ends after .closed (subsequent calls return .closed).
    func nextEvent() async -> SeekProviderEvent<Frame>
}

/// Retained old-handle rule (finding 6): a retained handle stays copyable, readable and releasable
/// after a seek WHILE THE SAME OPEN GENERATION remains alive - this is generation-bound, NOT
/// seek-revision-bound. Release is exactly-once per handle.
public struct RetainedHandleMetadata: Sendable {
    public let origin: EventOrigin
    public let validWhileOpenGeneration: UInt64   // == origin.source.openGeneration
    public let releaseRequired: Bool
    public init(origin: EventOrigin, validWhileOpenGeneration: UInt64, releaseRequired: Bool) {
        self.origin = origin
        self.validWhileOpenGeneration = validWhileOpenGeneration
        self.releaseRequired = releaseRequired
    }
}

// MARK: - Interrupts (two kinds, two lifetimes)

public enum InterruptKind: String, Sendable {
    case requestCancel  // per-request; lifetime: until that request's receipt
    case sessionIO      // sticky UNTIL close/recovery; never reset by a new operation; closeRequired
}

public struct InterruptState: Sendable {
    public let kind: InterruptKind
    public let raisedBy: SeekEventIdentity?
    public let activeIOObserving: Bool
    public init(kind: InterruptKind, raisedBy: SeekEventIdentity?, activeIOObserving: Bool) {
        self.kind = kind
        self.raisedBy = raisedBy
        self.activeIOObserving = activeIOObserving
    }
}

// Cleanup ordering rule (contractual): post-mutation cleanup runs AFTER the native call returns,
// with provider resources alive; never concurrently with an executing FFmpeg call.

// MARK: - Provider transaction state machine
// Synchronization is scoped to state snapshots. No native call, continuation resume,
// user executor or await runs while this lock is held.
public final class ProviderSeekReservation: @unchecked Sendable {
    public let identity: SeekEventIdentity
    public let request: SeekRequest
    public let reservedRevision: SeekRevision
    fileprivate var executed = false
    fileprivate var enteredNative = false
    fileprivate var cancellation: SeekReceipt.CancelReason?
    fileprivate var result: SeekReceipt?
    fileprivate var waiters: [CheckedContinuation<SeekReceipt, Never>] = []
    fileprivate init(identity: SeekEventIdentity, request: SeekRequest, revision: SeekRevision) {
        self.identity = identity; self.request = request; self.reservedRevision = revision
    }
}

public final class ProviderSeekCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let mint = TransactionIDMint()
    private var active: ProviderSeekReservation?
    private var closing = false
    private var poisoned = false
    private var coordinated = false
    private var legacyUsed = false
    private var binding: (SourceToken, SeekSessionID, SeekRevision)?
    private var descriptorValue: SeekSourceDescriptor?
    private var capabilityValue = SeekCapabilities(seekable: false, supportedRoundings: [], supportedFlags: 0, originKnown: false)
    private var lastCorrelation: UInt64 = 0
    public init() {}
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    // Called only after a successful native open. Token issuance is owned by the decoder.
    public func opened(token: SourceToken, session: SeekSessionID, descriptor: SeekSourceDescriptor,
                       capabilities: SeekCapabilities) {
        locked {
            precondition(active == nil)
            binding = (token, session, .atOpen); descriptorValue = descriptor
            capabilityValue = capabilities; closing = false; poisoned = false
            coordinated = false; legacyUsed = false; lastCorrelation = 0
        }
    }
    public func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)? {
        locked { guard !closing, !poisoned, let b = binding else { return nil }; return (b.0,b.1,b.2) }
    }
    public func capabilities() -> SeekCapabilities { locked { capabilityValue } }
    public func descriptor(for source: SourceToken) throws -> SeekSourceDescriptor {
        try locked {
            guard !closing, !poisoned, let d = descriptorValue, d.source == source else { throw SeekRefusal.closed }
            return d
        }
    }
    public var activeTransaction: SeekEventIdentity? { locked { active?.identity } }
    public var isCoordinated: Bool { locked { coordinated } }
    /// A source open chooses legacy or enveloped mode once. No retagging of legacy work.
    public func claimLegacy() -> Bool {
        locked {
            guard !coordinated, active == nil, !closing, !poisoned else { return false }
            legacyUsed = true; return true
        }
    }
    public func matches(session: UInt64) -> Bool { locked { binding?.1.rawValue == session } }
    public var outputAllowed: Bool { locked { !closing && !poisoned && active == nil } }
    public var isClosingOrPoisoned: Bool { locked { closing || poisoned } }
    /// Activates coordinated event mode before the first pull. Cannot downgrade until a new open.
    public func activateEvents() throws {
        try locked {
            guard !closing, !poisoned, binding != nil else { throw SeekRefusal.closed }
            guard !legacyUsed else { throw SeekRefusal.legacyRejected(reason: "legacy mode already used for this open") }
            coordinated = true
        }
    }
    public func tryBegin(_ request: SeekRequest,
                         executor: @escaping @Sendable (ProviderSeekReservation) -> Void) throws -> any SeekTransaction {
        let r: ProviderSeekReservation = try locked {
            guard !closing, !poisoned, let b = binding,
                  b.0 == request.source, b.1 == request.session else { throw SeekRefusal.closed }
            guard !legacyUsed else { throw SeekRefusal.legacyRejected(reason: "legacy mode already used for this open") }
            if let a = active { throw SeekRefusal.busy(active: a.identity) }
            guard request.expectedRevision == b.2 else { throw SeekRefusal.stale(expected: request.expectedRevision, actual: b.2) }
            guard request.correlationID.rawValue > lastCorrelation else { throw SeekRefusal.unsupported("replayed correlation") }
            guard capabilityValue.seekable, capabilityValue.originKnown,
                  request.target.rounding == .floorToKeyframe,
                  request.target.requestedFlags & ~Int32(1) == 0 else { throw SeekRefusal.unsupported("unsupported seek target or flags") }
            guard request.target.position.value >= 0 else { throw SeekTimeError.targetBeforeOrigin }
            let next = try b.2.advanced()
            let id = try mint.issue()
            let value = ProviderSeekReservation(identity: SeekEventIdentity(source: b.0, transactionID: id), request: request, revision: next)
            coordinated = true; lastCorrelation = request.correlationID.rawValue; active = value
            return value
        }
        return ProviderSeekHandle(owner: self, record: r, executor: executor)
    }
    fileprivate func execute(_ r: ProviderSeekReservation,
                             executor: @Sendable (ProviderSeekReservation) -> Void) throws {
        try locked {
            guard active === r, r.result == nil, !r.executed else { throw SeekRefusal.alreadyExecuted }
            r.executed = true
        }
        executor(r)
    }
    /// Linearizes native entry against cancellation. A cancellation after this point is
    /// conservatively post-entry even if the native function has not yet made its first mutation.
    public func enterNative(_ r: ProviderSeekReservation) -> Bool {
        locked {
            guard active === r, r.result == nil, r.cancellation == nil, !closing, !poisoned else { return false }
            r.enteredNative = true; return true
        }
    }
    public func cancellationRequested(_ r: ProviderSeekReservation) -> Bool {
        locked { r.cancellation != nil || closing }
    }
    public func queueRefusal(_ r: ProviderSeekReservation) -> SeekReceipt.NoMutationRefusal? {
        locked {
            guard !closing, !poisoned, let b = binding, b.0 == r.request.source,
                  b.1 == r.request.session else { return .closed }
            guard b.2 == r.request.expectedRevision else { return .stale(expected: r.request.expectedRevision, actual: b.2) }
            return nil
        }
    }
    public func cancel(_ r: ProviderSeekReservation, reason: SeekReceipt.CancelReason = .requested) {
        var continuations: [CheckedContinuation<SeekReceipt, Never>] = []
        var completed: SeekReceipt?
        locked {
            guard r.result == nil else { return }
            if r.cancellation == nil { r.cancellation = reason }
            if !r.executed {
                let receipt = noMutation(r, outcome: .cancelledNoMutation(reason: r.cancellation!), arbitration: .cancellationRequested)
                r.result = receipt; completed = receipt
                continuations = r.waiters; r.waiters = []
                if active === r { active = nil }
            }
        }
        if let completed { for c in continuations { c.resume(returning: completed) } }
    }
    private func noMutation(_ r: ProviderSeekReservation, outcome: SeekReceipt.Outcome,
                            arbitration: SeekArbitration) -> SeekReceipt {
        SeekReceipt(identity: r.identity, correlationID: r.request.correlationID, session: r.request.session,
                    request: r.request, previousRevision: r.request.expectedRevision,
                    nextRevision: r.request.expectedRevision, reachedStage: .preSeek,
                    arbitration: arbitration, mutation: .none, resumePolicy: .unchangedCoreGated, outcome: outcome)
    }
    /// Single linearization point for cancellation versus nativeReady. The builder is a pure value
    /// constructor; native work MUST already have returned and cleanup must already be complete.
    public func finish(_ r: ProviderSeekReservation,
                       build: (Bool) -> SeekReceipt) {
        var receipt: SeekReceipt?
        var continuations: [CheckedContinuation<SeekReceipt, Never>] = []
        locked {
            guard r.result == nil, active === r else { return }
            let value = build(r.cancellation != nil || closing || poisoned)
            precondition(value.identity == r.identity && value.session == r.request.session)
            if case .nativeReady = value.outcome {
                precondition(value.mutation == .completedClean && value.nextRevision == r.reservedRevision)
                if let b = binding { binding = (b.0,b.1,r.reservedRevision) }
            } else if value.mutation != .none { poisoned = true }
            r.result = value; receipt = value
            continuations = r.waiters; r.waiters = []; active = nil
        }
        if let receipt { for c in continuations { c.resume(returning: receipt) } }
    }
    public func waitUntilSettled() async {
        let record = locked { active }
        if let record { _ = await completion(record) }
    }
    fileprivate func completion(_ r: ProviderSeekReservation) async -> SeekReceipt {
        await withCheckedContinuation { c in
            let value: SeekReceipt? = locked {
                if let v = r.result { return v }
                r.waiters.append(c); return nil
            }
            if let value { c.resume(returning: value) }
        }
    }
    /// Session I/O escalation invalidates output immediately. The decoder separately raises the
    /// matching session interrupt while native state stays retained until native return/close.
    public func poisonSession() { locked { poisoned = true } }
    public func requestClose() {
        let r = locked { () -> ProviderSeekReservation? in closing = true; return active }
        if let r { cancel(r, reason: .close) }
    }
}

private final class ProviderSeekHandle: SeekTransaction, @unchecked Sendable {
    private let owner: ProviderSeekCoordinator
    private let record: ProviderSeekReservation
    private let executor: @Sendable (ProviderSeekReservation) -> Void
    init(owner: ProviderSeekCoordinator, record: ProviderSeekReservation,
         executor: @escaping @Sendable (ProviderSeekReservation) -> Void) {
        self.owner = owner; self.record = record; self.executor = executor
    }
    var identity: SeekEventIdentity { record.identity }
    var correlationID: SeekCorrelationID { record.request.correlationID }
    var session: SeekSessionID { record.request.session }
    var request: SeekRequest { record.request }
    var reservedRevision: SeekRevision { record.reservedRevision }
    func execute() throws { try owner.execute(record, executor: executor) }
    func completion() async -> SeekReceipt { await owner.completion(record) }
    func requestCancellation() { owner.cancel(record) }
    deinit { owner.cancel(record, reason: .abandoned) }
}
