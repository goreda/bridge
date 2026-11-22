// LANE-0 CONTRACT (architect block 80b, 2026-10-25): the CANONICAL shared
// signatures every lane codes against. Base: trunk c5f06bd + the L1
// timing/lifecycle work (the integrated slice). The architect reviews THIS
// branch before any lane rebases onto it. No main merge, no kit, no
// acceptance claim.
//
// 1. FrameSink.show RETURNS Bool (PlaybackCore.swift) - SETTLED. true =
//    the frame was ADMITTED onto the display path; false = fenced/refused
//    (typed reason logged). Bool means ADMISSION, NOT GPU completion
//    (L2 r7 fact): no display-completion semantics are carried here.
//    The retired Void variant cannot express a fenced upload.
//    FramePump count semantics are pinned WITH the signature (L2 r7 fact):
//    shown counts only accepted shows; fencedShows is separate; dropped
//    counts decision drops; waits counts waits; a cancelled wait is a
//    typed cancel, never an elapsed wait; non-finite/out-of-order pts are
//    typed drops, never traps.
//    SourceFrame carries 8-bit RGBA ONLY (L2 r7 fact): no 16F/HDR carrier
//    exists in the slice; any HDR pixel claim for this slice is FALSE.
//
// 2. AudioSink (below): the canonical audio-output seam. Boundary refusals
//    are TYPED COUNTS, never traps; construction is failable, never
//    fatalError.
//
// 3. Clock: PlaybackClock.nowSeconds() MUST be MONOTONIC
//    (CACurrentMediaTime or equivalent). A wall-clock source is a
//    contract violation: waits, drains and deadlines assume time never
//    jumps.
//
// 4. Stop/close receipts: an orderly stop RETURNS EVIDENCE, not void.
//    Audio: PCMRingReceipt snapshotted BEFORE any ring reset. Decoder:
//    CloseReport via closeAndReport. A stop receipt with residual==0 is
//    LOCAL QUIESCENCE of a bounded drain (L2 r7 fact) - NOT a provider
//    guarantee about future callbacks; callback lifetime is governed by
//    the admission cell (constraint A), not by any SDK claim.
//    A teardown that cannot produce its receipt is TERMINAL.
//
// RESOURCE POLICY (architect 80b constraints A-D, summary):
///  A. Callback admission CAS (AdmissionCell): bit63 RETIRED + reader
///     count on one lock-free C cell. Post-retire callbacks touch NO
///     payload and render silence. Owner retires FIRST, then drains
///     admitted readers to zero before reset/reuse/dispose.
///  B. Shared rings are reused ONLY after retire + readers==0 + producer
///     join, in that order. Stale callbacks write NOTHING (no shared
///     event-ring producer across generations).
///  C. Tombstones hold the sink WEAKLY: a retired registration retains
///     only its small context, never the sink/rings/ledger. A
///     PROCESS-GLOBAL registry bounds retained terminal payloads
///     (count + byte estimate); start() refuses TYPED at the ceiling.
///     The ceiling VALUES (8 payloads / 64 MiB in AudioUnitSink) are
///     LANE-0 REVIEW VALUES - no approved numeric cap claim.
///  D. ANY teardown error/timeout: no reset, no reuse, no new start;
///     typed failed, payload retained + registered.
//
// SESSION IDENTITY (architect full verdict S4 - SETTLED): playback
// identity is OWNER-ISSUED and opaque, minted ONLY by
// PlaybackIdentityAuthority (GorAVCore), shared across
// decoder/audio/display/ledger for a run, with a SEPARATE
// seek/presentation revision (a seek bumps the revision, never the
// session). Issuance is atomic with TYPED EXHAUSTION at wrap. The
// SessionID public init carries NO authority (test fixtures only);
// per-lane minting, String->Int hashing, and fixed shell epochs are
// contract violations. The shell's fixed SessionID(epoch: 1/2) sites are
// migrated to authority issuance in this branch.
//
// SUBTITLES: L2's setSubtitlePlanAuthority exists with NO caller/wiring
// (OPEN). It is OUT of the first slice; no barrier is claimed closed.
import Foundation

/// Canonical audio-output sink seam (lane-0 item 2). Pure Swift so every
/// lane can typecheck against it off-Mac; the macOS AudioUnitSink conforms.
public protocol AudioSink: AnyObject, Sendable {
    /// Push decoded PCM bytes. Bytes pushed while not running or after a
    /// producer witness (.joined OR .absent) are TYPED COUNTS on the sink,
    /// never silent and never a trap. The admission check and the ring
    /// write are serialized against stop/join/reset.
    func push(_ pcm: [UInt8])
    /// Live queue depth in bytes (post-stop: the reset ring's depth).
    var available: Int { get }
    /// Play the queue out, bounded, on a MONOTONIC clock. Cancellation is
    /// TYPED: a cancelled drain reports (remaining, cancelled: true),
    /// never masquerades as a completed drain.
    func drainBounded(maxSeconds: Double) async -> (remaining: Int, cancelled: Bool)
    /// Producer quiescence witness, GENERATION-BOUND: the AWAITED
    /// completion of the owned producer task (never a public flag).
    func markProducerJoined(generation g: UInt64)
    /// Explicit NO-PRODUCER declaration for sessions that never had one.
    func producerNotExpected(generation g: UInt64)
    /// Orderly stop: retire admission FIRST, teardown statuses all
    /// checked, readers drained to zero, receipt captured BEFORE any
    /// reset. Any unresolved step is TERMINAL (typed failed, retained).
    /// Returns the ONE typed teardown proof (architect full verdict S2):
    /// a Void stop plus nonatomic getters is not evidence.
    @discardableResult func stop() -> AudioStopOutcome
    /// The retired session's receipt (nil while the first session runs or
    /// after a terminal failure that retained evidence in place).
    var stoppedReceipt: PCMRingReceipt? { get }
    /// Lifecycle view; a FAILED session is terminal.
    var lifecycleState: SessionLifecycle.State { get }
}

/// The ONE typed stop proof (r3 S4): a stop returns a TYPED OUTCOME,
/// never a struct whose noop/zero fields masquerade as evidence.
///   .pending  - a stop/teardown is in flight; NO terminal evidence yet.
///   .noop     - nothing was running AND no prior terminal evidence
///               exists. A no-op stop carries NO evidence at all.
///   .complete - orderly teardown; the evidence value is the proof.
///   .failed   - TERMINAL failure; the evidence value is retained.
/// EVIDENCE PRESERVATION (verdict S4): a second stop() after a terminal
/// outcome returns the RETAINED first outcome (.complete/.failed with
/// the original evidence) - it is NEVER downgraded to .noop, which would
/// lose the failure.
public enum AudioStopOutcome: Sendable, Equatable {
    case pending
    case noop
    case complete(AudioStopEvidence)
    case failed(AudioStopEvidence)
    /// True ONLY for an orderly completed teardown. Callers MUST switch
    /// on this - "not failed" would wrongly accept .noop/.pending.
    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}

/// The immutable teardown evidence attached to a terminal stop outcome.
public struct AudioStopEvidence: Sendable, Equatable {
    public let generation: UInt64
    /// OSStatus-shaped statuses; NIL = step not attempted (skipped by
    /// an earlier failure or by the stop's shape) - explicit UNKNOWN,
    /// never a fabricated sentinel (verdict S4: -1000 was a fabrication).
    public let stopStatus: Int32?
    public let uninitStatus: Int32?
    public let disposeStatus: Int32?
    public let readersDrained: Bool
    public let producerWitnessed: Bool
    /// Bytes left in the ring at receipt snapshot, or NIL when no
    /// snapshot was taken (explicit UNKNOWN - a 0 here was a false
    /// "empty" claim in r2). A 0 value means measured-empty local
    /// bounded drain, still NOT a provider guarantee.
    public let drainResidual: Int?
    /// Process-registry id of the retained tombstone/fault registration.
    public let retainedRegistration: UInt64?
    public init(generation: UInt64, stopStatus: Int32?, uninitStatus: Int32?,
                disposeStatus: Int32?, readersDrained: Bool, producerWitnessed: Bool,
                drainResidual: Int?, retainedRegistration: UInt64?) {
        self.generation = generation; self.stopStatus = stopStatus
        self.uninitStatus = uninitStatus; self.disposeStatus = disposeStatus
        self.readersDrained = readersDrained; self.producerWitnessed = producerWitnessed
        self.drainResidual = drainResidual; self.retainedRegistration = retainedRegistration
    }
}

// SOURCE CONTRACT (architect full verdict S3 - SETTLED in code):
// FrameSource.nextEvent() -> SourceEvent replaces nextFrame()->Optional:
//   .frame / .temporarilyUnavailable (starve waits INSIDE the pull with
//   cancel+bounded backoff; a starve NEVER ends clock/segment/pump/reset)
//   / .ended(reason) (session-bound idempotent terminal; EOS is ONLY
//   explicit .endOfStream after prior admitted frames) / .failed(code).
// FramePump: SINGLE FINALIZATION - every exit emits exactly ONE
// videoPumpEnd with a typed endReason (cancelled-in-wait emitting no end
// was ruled a DEFECT); cancel is rechecked AFTER each await and BEFORE
// sink admission (cancel-ACK serializes admission; admitted frames count,
// no rollback). missingPTS releases the handle BEFORE the skip (S5).
//
// SEVERITY / RUN TERMINAL (S4 - SETTLED in code): the priority
// failure>cancel>close>early>sourceEnd>EOS is a DISPLAY SUMMARY ONLY
// (EndReason.combined); leg terminals, close intent, drain residual and
// teardown outcome travel separately in RunTerminal. isEOSSuccess is true
// ONLY when both legs ended explicit EOS + clean drain + clean teardown;
// sourceEnded is never EOS.
