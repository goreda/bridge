// AUTHORED NEW (2026-10-17, K6): gorav playback core - Linux-testable.
// Pure Swift, no AppKit, no CFFmpeg. Derived from mpv 0.41.0 playloop/video
// timing (study-only, GPLv2+): mpv's video.c decides per frame between
// display, drop (late past vsync), or wait (early); audio is the sync
// master when present (mpv audio.c ao chain). gorav maps: this core owns
// the decisions and queues; the macOS shell owns NSWindow/CAMetalLayer
// display (mpv video/out/mac/*), CVDisplayLink pacing (common.swift), and
// AudioUnit output (ao_audiounit.m) as swappable sinks behind the
// protocols below, so everything decidable is testable off-Mac.
import Foundation
import Synchronization

/// LANE-0 CONTRACT item 3: nowSeconds() MUST be MONOTONIC (e.g.
/// CACurrentMediaTime). A wall-clock source violates the contract: wait,
/// drain and deadline arithmetic assumes time never jumps.
public protocol PlaybackClock: Sendable { func nowSeconds() -> Double }

public enum FrameDecision: Equatable, Sendable { case show, drop, wait(Double) }

/// Shared post-seek media/wall anchor (M4): ONE authority maps media pts to
/// wall time for BOTH video frame scheduling and the audio resume, so a
/// legitimate media offset (e.g. +100ms edit-list audio start) is preserved
/// as an actual A/V offset, never collapsed by independent arrival anchoring.
public struct MediaWallAnchor: Sendable, Equatable {
    public let mediaSeconds: Double
    public let wallSeconds: Double
    public init(mediaSeconds: Double, wallSeconds: Double) {
        self.mediaSeconds = mediaSeconds; self.wallSeconds = wallSeconds
    }
    public func scheduledWall(forMediaSeconds pts: Double) -> Double {
        wallSeconds + (pts - mediaSeconds)
    }
}

/// Sync master visibility (K6 review r2 item 5): audio-master sync is
/// NOT_IMPLEMENTED. mpv masters sync to audio when an audio track is live;
/// gorav's core currently decides against the wall/display clock only. The
/// seam is explicit so the shell cannot silently assume audio-mastered pts.
public enum SyncMaster: Sendable, Equatable {
    case clock
    case audioNotImplemented // NOT_IMPLEMENTED: do not select
}

public struct AVSyncDecider: Sendable {
    public let maxWaitSeconds: Double
    public let master: SyncMaster
    public init(maxWaitSeconds: Double = 1.0, master: SyncMaster = .clock) {
        self.maxWaitSeconds = maxWaitSeconds
        self.master = master
    }
    // mpv-flavored thresholds: a frame more than half a frame-duration late
    // is dropped; more than half early waits (clamped, K6 review r2 item 2);
    // inside the window it shows.
    public func decide(ptsSeconds: Double, nowSeconds: Double, frameDuration: Double) -> FrameDecision {
        let delta = ptsSeconds - nowSeconds
        if delta < -frameDuration / 2 { return .drop }
        if delta > frameDuration / 2 { return .wait(Swift.min(delta, maxWaitSeconds)) }
        return .show
    }
}

/// Optional pixel payload for display sinks. Pure value type; Linux tests
/// leave it nil, the macOS shell's FrameSource wrapper attaches RGBA bytes.
public struct PixelPayload: Sendable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8] // RGBA, width*4 stride
    public init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width; self.height = height; self.bytes = bytes
    }
}

public struct SourceFrame: Sendable {
    public let ptsSeconds: Double
    public let durationSeconds: Double
    public let digest: String
    public let pixelPayload: PixelPayload?
    public init(ptsSeconds: Double, durationSeconds: Double, digest: String, pixelPayload: PixelPayload? = nil) {
        self.ptsSeconds = ptsSeconds; self.durationSeconds = durationSeconds
        self.digest = digest; self.pixelPayload = pixelPayload
    }
}

/// LANE-0 CONTRACT item 3 (architect full verdict S3): the canonical
/// source states. `nil` is GONE - Optional could not distinguish a
/// transient starve from an end, and a starve that ENDS the pump strands
/// undelivered frames as a fake clean end (L6/L8 actual witnesses).
///
/// States:
///  - .frame: an admitted frame.
///  - .temporarilyUnavailable: a STARVE. The pump waits INSIDE the pull
///    with cancellation and bounded backoff. A starve NEVER ends the
///    clock, the segment, the pump, or any reset - ever.
///  - .ended(reason): a session-bound IDEMPOTENT terminal. After it, the
///    source must return the same terminal forever. EOS is ONLY the
///    explicit .endOfStream terminal after all prior admitted frames were
///    processed - never a nil, an empty read, or a cancel.
///  - .failed: a typed failure terminal (same idempotence).
public enum SourceEndReason: String, Sendable, Equatable {
    case endOfStream     // explicit EOS terminal (the ONLY EOS)
    case sourceEnded     // source exhausted WITHOUT explicit EOS (NOT EOS)
    case cancelled       // cancellation reached the source
}
public enum SourceEvent: Sendable {
    case frame(SourceFrame)
    case temporarilyUnavailable
    case ended(SourceEndReason)
    case failed(Int32)
}
public protocol FrameSource: Sendable { func nextEvent() async -> SourceEvent }

/// Verdict S5 rev6: TYPED seek-barrier receipt - the ACTUAL outcome of
/// a coordinated queue flush, never an assumed no-op.
public enum SeekBarrierOutcome: Sendable, Equatable {
    case flushed         // no frame produced under the old revision can surface on later pulls
    case unsupported     // the source cannot coordinate - typed refusal (fail closed)
    case failed(String)  // the barrier attempt itself failed - typed refusal
}
/// Verdict S5 rev6: a source with an internal production/decode QUEUE.
/// Frames decoded pre-seek can surface on LATER pulls, where the pump's
/// immutable pull-stamp cannot fence them - such a source MUST implement
/// a REAL barrier (drop or retag every pre-seek frame) and return its
/// typed receipt. Stateless sources declare nothing (no queue => the
/// barrier is trivially satisfied). THERE IS NO DEFAULT NO-OP: a
/// documented contract alone does not close production provenance.
public protocol QueuedFrameSource: FrameSource {
    func coordinateSeek(revision: UInt64) async -> SeekBarrierOutcome
}

/// r3 S6: SOURCE SESSION BINDING. Identity is (session, revision): the
/// owner-issued session id (S7 wiring point) plus the presentation
/// revision (a seek bumps the revision, never the session). Events from
/// any other binding are STALE - a typed violation, never silently
/// played.
public struct SourceSession: Sendable, Equatable, Hashable {
    public let session: UInt64
    public let revision: UInt64
    public init(session: UInt64, revision: UInt64) {
        self.session = session; self.revision = revision
    }
}

/// r3 S6: TERMINAL IDEMPOTENCE ENFORCED IN CODE (was comments only).
/// Wraps any FrameSource and guarantees the source contract at runtime:
///  - exactly ONE terminal ever reaches the consumer: the FIRST
///    .ended/.failed. Every event after a terminal (a second terminal,
///    a late frame, a starve) is a TYPED VIOLATION - counted, and the
///    same first terminal is replayed idempotently instead.
///  - a misbehaving source can never end a run twice or revive it.
/// Violations are observable (count + last kind), never hidden.
public final class IdempotentEventSource: FrameSource, @unchecked Sendable {
    /// Verdict S5 rev6: the wrapper is STATELESS and its inner source is
    /// stateless by construction (no internal decode queue): there is no
    /// pre-seek production left to fence on the wrapper's side - the
    /// barrier is TRIVIALLY satisfied; the pump's immutable pull-stamp
    /// covers any pull that crossed the ACK.
    public func coordinateSeek(revision: UInt64) async -> SeekBarrierOutcome { .flushed }

    public enum Violation: String, Sendable, Equatable {
        case eventAfterTerminal    // frame/starve/ended/failed post-terminal
    }
    private let inner: any FrameSource
    /// Async-safe scoped lock (Swift 6): NSLock is unavailable from
    /// async contexts; Mutex is the sanctioned primitive here.
    private struct ProtectedState: Sendable {
        var terminal: SourceEvent?     // latched FIRST terminal
        var violationCount = 0
        var lastViolation: Violation? = nil
    }
    private let protected = Mutex(ProtectedState())
    public var violationCount: Int { protected.withLock { $0.violationCount } }
    public var lastViolation: Violation? { protected.withLock { $0.lastViolation } }
    /// The binding this source runs under (observability; revision moves
    /// only via an explicit seek by the OWNER, who swaps the source).
    public let binding: SourceSession
    public init(_ inner: any FrameSource, binding: SourceSession) {
        self.inner = inner; self.binding = binding
    }
    public func nextEvent() async -> SourceEvent {
        // Terminal already latched: replay it idempotently. A source
        // that keeps being pulled after terminal is expected (the pump
        // stops pulling at terminal), so the replay itself is NOT a
        // violation; an inner post-terminal event can never leak
        // through because we never call inner again once latched.
        if let t = protected.withLock({ $0.terminal }) { return t }
        let ev = await inner.nextEvent()
        switch ev {
        case .ended, .failed:
            return protected.withLock { st in
                if st.terminal == nil { st.terminal = ev }
                return st.terminal!
            }
        case .frame, .temporarilyUnavailable:
            return ev
        }
    }
    /// Test/diagnostic hook: record a violation (used by the pump-side
    /// binding checks); production violations are latched internally.
    public func recordViolation(_ v: Violation) {
        protected.withLock { $0.violationCount += 1; $0.lastViolation = v }
    }
}
/// LANE-0 CONTRACT item 1 (SETTLED): show() returns whether the frame was
/// ACCEPTED onto the display path (finding 4): false = fenced/refused (the
/// sink logs the typed reason). This Bool signature is THE contract; the
/// retired Void variant cannot express a fenced upload.
public protocol FrameSink: Sendable {
    @discardableResult func show(_ frame: SourceFrame) async -> Bool
    /// Ticketed show (r3-rev2 S5, STRICT per verdict rev3): the pump
    /// hands the immutable per-frame admission ticket with the frame;
    /// the sink validates AND consumes it through the commit authority
    /// in the same critical section as the contents commit (ACK = no
    /// further commit). There is NO default forwarding implementation -
    /// a sink that cannot validate tickets is not a commit-wired sink,
    /// and a silent bypass is a contract violation (peer rev3: the
    /// default let unvalidated frames through).
    @discardableResult func show(_ frame: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool
}

/// r3 S5: the pump's end reason is TYPED, never a Stringly "failed:7".
public enum PumpEndReason: Sendable, Equatable {
    case none            // pre-finalization only; impossible after run()
    case endOfStream
    case sourceEnded
    case cancelled
    case failed(Int32)
    public var rawValue: String {
        switch self {
        case .none: return "none"
        case .endOfStream: return "endOfStream"
        case .sourceEnded: return "sourceEnded"
        case .cancelled: return "cancelled"
        case .failed(let c): return "failed:\(c)"
        }
    }
}

/// r3 S5: SHARED CANCEL/COMMIT CELL for show-admission serialization.
/// One C-owned packed cell: bit63 = cancelRequested, bits 32-62 =
/// presentation revision, bits 0-31 = admitted shows. The pump's
/// cancel-ACK and every show admission serialize on THIS cell: an
/// admission is a single CAS that fails if cancel was requested or the
/// revision moved, so a cancel/seek racing admission can never
/// interleave between a check and the admit. The same cell is what the
/// display side fences on (close AND cancel AND revision), closing the
/// check->await-show suspension gap an extra atomic bool cannot close.
public final class CancelCommit: @unchecked Sendable {
    /// r3-rev1 S5 (peer full verdict): the cell is
    /// [cancel:1][revision:31][admitted:32] with SATURATING counters -
    /// no wrap, ever:
    ///  - admissions saturate at 2^32-1 (further tryAdmit is a typed nil
    ///    refusal, `admissionExhausted` reads true; the count never
    ///    wraps into the revision field);
    ///  - bumpRevision saturates at 2^31-1 (further seeks are refused
    ///    typed - the return value does not move, `seekExhausted` reads
    ///    true; the bump never carries into the cancel bit);
    ///  - tryAdmit compares the caller revision EXACTLY (no mask on the
    ///    caller: an out-of-range revision is refused, never aliased).
    ///
    /// ADMISSION CONTRACT (architect-ruling shape): admission ISSUES an
    /// immutable per-frame ticket; the commit side validates that ticket
    /// IMMEDIATELY before the contents assignment, serialized on the
    /// display actor. The ACK point is requestCancel()/bumpRevision():
    /// after an ACK, NO further commit lands (mayFinish refuses) - an
    /// old-revision frame can never become visible after a seek, and no
    /// frame commits after cancel. Admission permits the ATTEMPT; the
    /// ticket bounds the COMMIT. (The looser allowed-finish-across-ACK
    /// variant was proposed and NOT ratified - do not reintroduce it
    /// without an architect ruling.)
    /// The immutable per-frame admission proof (verdict S5 rev2): a
    /// reference type BOUND to its issuing cell, consumable EXACTLY ONCE
    /// at the sink - no cross-cell validation, no replay, no
    /// source-agnostic sequence-range proxy.
    public final class AdmissionTicket: @unchecked Sendable {
        public let revision: UInt64     // revision this frame was admitted under
        public let sequence: UInt64     // 1-based admission sequence (genuineness)
        /// PRODUCER PROVENANCE (verdict S5 rev3): bound AT ADMISSION to
        /// the exact pulled frame (pts + digest) - the ticket can never
        /// authorize a DIFFERENT frame at commit.
        public let framePTS: Double
        public let frameDigest: String
        /// The issuing authority, RETAINED strongly (verdict S5 rev3):
        /// ObjectIdentifier address reuse can never alias a foreign
        /// cell, and the authority outlives any teardown ordering.
        private let issuer: CancelCommit
        /// Consume state, mutated ONLY inside the issuer's commitLock
        /// critical section - the consume and the contents assignment
        /// are ONE serialized act (no separate ticket lock).
        fileprivate var consumed = false
        fileprivate init(revision: UInt64, sequence: UInt64, framePTS: Double,
                         frameDigest: String, issuer: CancelCommit) {
            self.revision = revision; self.sequence = sequence
            self.framePTS = framePTS; self.frameDigest = frameDigest
            self.issuer = issuer
        }
        fileprivate func issued(by cell: CancelCommit) -> Bool { issuer === cell }
    }
    private static let cancelBit: UInt64 = 1 << 63
    private static let revShift: UInt64 = 32
    private static let revMask: UInt64 = 0x7FFFFFFF
    private static let admitMask: UInt64 = 0xFFFFFFFF
    private let cell: AtomicU64?
    /// The WHOLE-RUN identity this authority is bound to (verdict S5
    /// rev3 / identity finding): 0 = unbound harness cell.
    public let sessionEpoch: UInt64
    /// The SERIAL OWNER spanning ACK and COMMIT (verdict S5 rev3):
    /// requestCancel, bumpRevision and commitFrame/mayFinish ALL take
    /// this lock, so an external ACK and a contents assignment can
    /// never interleave - after an ACK returns, no pre-ACK frame can
    /// still land, and a commit section mid-assignment finishes before
    /// the ACK returns.
    private let commitLock = NSLock()
    public init(sessionEpoch: UInt64 = 0) {
        cell = AtomicU64(0); self.sessionEpoch = sessionEpoch
    }
    /// True when the C cell exists; a failed creation refuses ALL
    /// admissions (fail-closed), never admits on a missing cell.
    public var available: Bool { cell != nil }
    /// Verdict S5 rev6 REENTRY GUARD (actual, not documented): the
    /// section records its owning thread; a public entry ON THE SAME
    /// THREAD while the section is held (from the assign closure or a
    /// test hook) is a TYPED refusal, never a non-recursive-lock
    /// deadlock. Cross-thread stale reads are benign (the caller simply
    /// blocks on the lock, which is the correct serialization).
    private var sectionOwner: ObjectIdentifier? = nil
    private let reentryRefusals: AtomicU64? = AtomicU64(0)
    /// Witness-observable count of typed reentry refusals.
    public var reentrantRefusalCount: Int { Int(reentryRefusals?.load() ?? 0) }
    private func isReentrantCall() -> Bool {
        guard sectionOwner == ObjectIdentifier(Thread.current) else { return false }
        _ = reentryRefusals?.fetchAdd(1)
        return true
    }
    /// Idempotent, monotonic: once set it never clears.
    public func requestCancel() {
        guard let cell else { return }
        if isReentrantCall() { return }   // typed refusal, never a deadlock
        commitLock.lock()
        sectionOwner = ObjectIdentifier(Thread.current)
        defer { sectionOwner = nil; commitLock.unlock() }   // serialized with commits
        while true {
            let v = cell.load()
            if v & Self.cancelBit != 0 { return }
            if cell.compareExchange(expected: v, desired: v | Self.cancelBit) { return }
        }
    }
    public var isCancelled: Bool { (cell?.load() ?? Self.cancelBit) & Self.cancelBit != 0 }
    public var revision: UInt64 { ((cell?.load() ?? 0) >> Self.revShift) & Self.revMask }
    public var admitted: UInt64 { (cell?.load() ?? 0) & Self.admitMask }
    /// Typed exhaustion queries (no silent wrap anywhere).
    public var admissionExhausted: Bool { admitted == Self.admitMask }
    public var seekExhausted: Bool { revision == Self.revMask }
    /// Test-visible ceilings for the seeded boundary witnesses (RW29).
    public static var admitCeilingForTest: UInt64 { admitMask }
    public static var revisionCeilingForTest: UInt64 { revMask }
    /// Seek refusals are TYPED (verdict S5 rev2), never a silent no-move.
    public enum SeekRefusal: Error, Equatable { case unavailable, cancelled, exhausted, reentrant }
    /// Seek: bump the presentation revision, returning the new one.
    /// Verdict S5 rev6: this is INVALIDATION ONLY - it fences
    /// current-revision tickets; it is NOT a seek-COMPLETION claim
    /// (decoder-queued frames may still be in flight). The ONLY
    /// completion ACK is FramePump.resetPresentation, which runs the
    /// actual source queue barrier BEFORE this bump is published.
    /// SATURATING: at the 2^31-1 ceiling the bump is a typed
    /// `.exhausted` refusal - it never carries into the cancel bit.
    /// A cancelled cell is a typed `.cancelled` refusal.
    /// A same-thread reentrant call from inside the commit section is a
    /// typed `.reentrant` refusal - never a deadlock.
    @discardableResult
    public func bumpRevision() throws -> UInt64 {
        guard let cell else { throw SeekRefusal.unavailable }
        if isReentrantCall() { throw SeekRefusal.reentrant }
        commitLock.lock()
        sectionOwner = ObjectIdentifier(Thread.current)
        defer { sectionOwner = nil; commitLock.unlock() }   // serialized with commits
        while true {
            let v = cell.load()
            let cur = (v >> Self.revShift) & Self.revMask
            if v & Self.cancelBit != 0 { throw SeekRefusal.cancelled }
            if cur == Self.revMask { throw SeekRefusal.exhausted }
            let next = v &+ (1 &<< Self.revShift)
            if cell.compareExchange(expected: v, desired: next) { return (next >> Self.revShift) & Self.revMask }
        }
    }
    /// TEST SEAM (harness only): seed the cell's counters so the REAL
    /// ceiling/exhaustion algorithm is a runnable witness without
    /// 2^32 admissions or 2^31 seeks.
    public init(testSeedAdmissions admissions: UInt64, revision: UInt64, sessionEpoch: UInt64 = 0) {
        cell = AtomicU64((min(revision, Self.revMask) << Self.revShift) | min(admissions, Self.admitMask))
        self.sessionEpoch = sessionEpoch
    }
    /// SERIALIZED ADMISSION: one CAS. Returns an immutable per-frame
    /// AdmissionTicket, or nil (typed refusal) when cancelled, when the
    /// caller revision is not EXACTLY current (no mask alias), or when
    /// the admission count is saturated.
    public func tryAdmit(revision: UInt64, framePTS: Double = 0, frameDigest: String = "") -> AdmissionTicket? {
        guard let cell, revision <= Self.revMask else { return nil }
        while true {
            let v = cell.load()
            if v & Self.cancelBit != 0 { return nil }
            if (v >> Self.revShift) & Self.revMask != revision { return nil }
            let count = v & Self.admitMask
            if count == Self.admitMask { return nil }        // saturating, no wrap
            if cell.compareExchange(expected: v, desired: v &+ 1) {
                return AdmissionTicket(revision: revision, sequence: count &+ 1,
                                       framePTS: framePTS, frameDigest: frameDigest,
                                       issuer: self)
            }
        }
    }
    /// Genuineness only: the ticket was issued BY THIS CELL and its
    /// sequence was actually issued. Does NOT decide the commit -
    /// mayFinish does. (Cross-cell tickets are never genuine.)
    public func validate(ticket: AdmissionTicket) -> Bool {
        let a = admitted
        return ticket.issued(by: self)
            && ticket.sequence >= 1 && ticket.sequence <= a
    }
    /// HARNESS-ONLY (verdict S5 rev5): production commits go through
    /// commitFrame - ONE in-section check+consume+assign. This
    /// standalone consume exists only for harness arms that need the
    /// check WITHOUT an assignment; it is NOT a generic commit proof.
    /// COMMIT-TIME validity (the ACK contract), SINGLE-CONSUME: the
    /// ticket is genuine for THIS cell, the cell is NOT cancelled, the
    /// ticket's admission revision is STILL current, and the ticket has
    /// not been consumed before - a successful call BURNS the ticket, so
    /// exactly one commit can ever land per admission. Call on the
    /// display actor immediately before the contents assignment - the
    /// check/consume and the assignment serialize on that actor, so no
    /// cancel/seek can interleave between them.
    public func _testMayFinishConsume(ticket: AdmissionTicket) -> Bool {
        guard let cell else { return false }
        if isReentrantCall() { return false }
        commitLock.lock()
        sectionOwner = ObjectIdentifier(Thread.current)
        defer { sectionOwner = nil; commitLock.unlock() }
        let v = cell.load()
        guard v & Self.cancelBit == 0,
              ticket.revision == (v >> Self.revShift) & Self.revMask,
              ticket.issued(by: self), !ticket.consumed else { return false }
        ticket.consumed = true
        return true
    }

    /// TEST-ONLY witnesses (verdict S5 rev3): invoked INSIDE the commit
    /// critical section so a harness can hold the section and prove an
    /// external ACK blocks until the assignment completes. Always nil
    /// in production; ALWAYS nil'd after use - an armed leftover hook
    /// deadlocks the next commitFrame.
    /// REENTRANCY (verdict S5 rev5): commitLock is NON-RECURSIVE. A
    /// hook, the commitFrame `assign` closure, or ANY code running
    /// inside the section must NEVER call back into the commit
    /// (tryAdmit / commitFrame / requestCancel / bumpRevision /
    /// _testMayFinishConsume) - that is a self-deadlock, by design.
    public var _testBeforeConsume: (() -> Void)? = nil
    public var _testAfterConsumeBeforeAssign: (() -> Void)? = nil
    /// COMMIT-WITH-ASSIGNMENT (verdict S5 rev3 - the actual atomic
    /// ACK/commit boundary): the cancel check, the current-revision
    /// check, the ISSUER + FRAME-PROVENANCE binding, the single consume
    /// AND the caller's contents assignment ALL run inside the one
    /// critical section that cancel/seek ACKs take. `permit` is an
    /// additional caller-side fence evaluated inside the section (the
    /// display's close-intent gate). The ticket is consumed ONLY when
    /// every check passes and the assignment runs - a refused commit
    /// never burns its ticket, and a consumed ticket always carried its
    /// assignment.
    @discardableResult
    public func commitFrame(_ ticket: AdmissionTicket, framePTS: Double, frameDigest: String,
                            permit: (() -> Bool)? = nil, assign: () -> Void) -> Bool {
        guard let cell else { return false }
        if isReentrantCall() { return false }
        commitLock.lock()
        sectionOwner = ObjectIdentifier(Thread.current)
        defer { sectionOwner = nil; commitLock.unlock() }
        _testBeforeConsume?()
        let v = cell.load()
        guard v & Self.cancelBit == 0,
              ticket.revision == (v >> Self.revShift) & Self.revMask,
              ticket.issued(by: self), !ticket.consumed,
              ticket.framePTS == framePTS, ticket.frameDigest == frameDigest,
              permit?() ?? true else { return false }
        ticket.consumed = true
        _testAfterConsumeBeforeAssign?()
        assign()
        return true
    }
}

public struct PumpStats: Equatable, Sendable {
    public var shown = 0, dropped = 0, waits = 0
    /// Shows refused by the sink (close fence) - NOT counted as shown (finding 4).
    public var fencedShows = 0
    /// Verdict S5 rev6: pulls/events fenced by the post-await and
    /// after-wait provenance checks (stale stamp or barrier window).
    public var seekStalePulls = 0
    /// Pump observed task cancellation (finding 5): a CANCELLED pump is a
    /// typed end, never a fabricated EOS.
    public var cancelled = false
    public var outOfOrderDrops = 0
    public var nonFiniteDrops = 0
    public var digestsShown: [String] = []
    /// Starve waits entered (temporarilyUnavailable). Informational; a
    /// starve NEVER ends the pump (architect full verdict S3).
    public var starveWaits = 0
    /// THE pump's end reason (S3 single finalization, r3 S5 TYPED):
    /// set exactly once at the single finalization; .none is impossible
    /// after run() returns.
    public var endReason: PumpEndReason = .none
}

/// Typed boundary refusals (K6 review r2 items 1/4): provider data faults
/// are counted and dropped, never traps.

public actor FramePump {
    private let source: FrameSource; private let sink: FrameSink
    private let clock: PlaybackClock; private let decider: AVSyncDecider
    /// Seek pacing re-anchor (M4): maps stream pts onto the wall clock.
    /// Set at the FIRST frame decision of each presentation generation
    /// (pump start AND after every successful resetPresentation): that frame
    /// shows on arrival - the measured late-start gap is the REAL wall time
    /// it took to arrive, preserved, never smoothed - and later frames pace
    /// by their pts deltas off the anchor. Without it a post-seek pts (T)
    /// judged against raw wall time (W) freezes forward seeks (waits T-W)
    /// or drop-storms backward seeks to EOF.
    private var paceAnchorPts: Double? = nil
    private var paceAnchorWall: Double = 0
    /// The pace anchor currently in force (nil = arrival anchoring). Read by the
    /// composition so audio resumes off the ACTUAL commit anchor, not a
    /// pre-seek preparation timestamp.
    public var currentPaceAnchor: MediaWallAnchor? {
        guard let m = paceAnchorPts else { return nil }
        return MediaWallAnchor(mediaSeconds: m, wallSeconds: paceAnchorWall)
    }
    // Test hooks: onWait lets a fake clock advance; real shell sleeps.
    // v4: onWait reports whether the wait COMPLETED (true) or was
    // cancelled/interrupted (false) - a swallowed CancellationError can
    // never masquerade as an elapsed wait.
    private let onWait: @Sendable (Double) async -> Bool
    // L1 (architect delta 2026-10-25): optional TimingLedger sink. All
    // appends are off-RT (the pump is an async actor, never the render
    // callback). PTS records are classified observations - no discontinuity
    // PASS and no general monotonic-PTS claim (architect cond. 2).
    private let ledger: TimingLedger?
    private let ledgerSession: UInt64
    private let ledgerGeneration: UInt64
    /// r3 S5: shared cancel/commit cell. When present, show admissions
    /// serialize through it (cancel-ACK); when absent the pump falls
    /// back to Task.isCancelled checks only (test/simple paths).
    private let commit: CancelCommit?
    /// The presentation revision this pump admits under; resetPresentation
    /// adopts the commit's bumped revision on seek.
    private var presentationRevision: UInt64 = 0
    public init(source: FrameSource, sink: FrameSink, clock: PlaybackClock,
                decider: AVSyncDecider = AVSyncDecider(),
                ledger: TimingLedger? = nil, ledgerSession: UInt64 = 0, ledgerGeneration: UInt64 = 0,
                commit: CancelCommit? = nil,
                onWait: @escaping @Sendable (Double) async -> Bool) {
        self.source = source; self.sink = sink; self.clock = clock
        self.decider = decider; self.onWait = onWait
        self.ledger = ledger; self.ledgerSession = ledgerSession; self.ledgerGeneration = ledgerGeneration
        self.commit = commit
        self.presentationRevision = commit?.revision ?? 0
    }
    private var lastPts = -Double.infinity
    private var lastDuration = 0.0
    // Verdict S5 rev6: SEEK ORCHESTRATION. While a queued-source
    // barrier is in flight, pulls/admissions GATED: a pull that returns
    // has unknowable provenance, so it parks on the barrier and is then
    // fenced typed. Overlapping resets are generation-serialized; the
    // older is SUPERSEDED (publishes nothing). Waiters are released
    // once, by the gate owner, after the barrier resolves.
    private var seekBarrierInFlight: Bool = false
    private var seekGeneration: UInt64 = 0
    private var seekWaiters: [CheckedContinuation<Void, Never>] = []
    private func waitForSeekBarrier() async {
        await withCheckedContinuation { cc in seekWaiters.append(cc) }
    }
    private func releaseSeekWaiters() {
        let w = seekWaiters; seekWaiters.removeAll()
        for cc in w { cc.resume() }
    }

    /// Seek integration (K6 r3): the decoder restarts presentation order at
    /// the landing keyframe after a seek, so post-seek frames arrive with
    /// pts BELOW the pump's lastPts. Without a reset they would all be
    /// typed out-of-order drops. The shell must call this when it seeks.
    /// Between run() calls (pause/resume) the order memory persists.
    /// Seek integration. Verdict S5 rev3: the typed revision bump is
    /// attempted BEFORE any presentation-order state changes; a typed
    /// refusal (cancelled/exhausted) changes NOTHING, logs ONLY the
    /// refusal, and returns false - the caller must NOT treat it as a
    /// seek ACK and must NOT reset decoder/order state.
    /// Verdict S5 rev6: SEEK-COMPLETION ACK. Runs the actual source
    /// queue barrier FIRST; only on a `.flushed` receipt is the revision
    /// bump published (CancelCommit.bumpRevision itself is INVALIDATION
    /// ONLY). A typed barrier failure/refusal is a failed seek: NO bump,
    /// NO order reset, `false` - the caller must NOT treat this as a
    /// seek ACK (fail closed). Overlapping resets are generation-
    /// serialized: the older is SUPERSEDED and publishes nothing.
    /// Pulls/admissions GATED while the barrier is in flight.
    /// SEEK-FAILURE fail-closed (S5 shell integration): refuses every further admission/
    /// upload through the shared authority, effective IMMEDIATELY in the seek completion
    /// control path - after a refused post-commit reset or a poisoned seek, no stale frame
    /// may escape while the caller closes. Idempotent: requestCancel is monotonic.
    public func prohibitResumeAfterSeekFailure() {
        commit?.requestCancel()
    }
    /// seekAnchorSeconds: when set (seek path), the pace anchor is the SHARED
    /// one - media = seek target, wall = the commit moment - so the first
    /// post-seek frame schedules at anchor + (its pts - target): a legitimate
    /// pts gap (keyframe landing past target) is HONORED as a real wait, not
    /// flattened by arrival anchoring. nil (startup/tests) keeps arrival
    /// anchoring.
    @discardableResult
    public func resetPresentation(seekAnchorSeconds: Double? = nil) async -> Bool {
        seekGeneration &+= 1
        let gen = seekGeneration
        if let queued = source as? QueuedFrameSource {
            seekBarrierInFlight = true   // gate ALL pulls/admissions
            let target = (commit?.revision ?? presentationRevision) &+ 1
            let outcome = await queued.coordinateSeek(revision: target)
            guard gen == seekGeneration else {
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .presentationReset,
                               note: "seekSuperseded")
                return false   // the NEWER reset owns the gate and its waiters
            }
            seekBarrierInFlight = false
            if outcome != .flushed {
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .presentationReset,
                               note: "seekBarrierRefused:\(outcome)")
                releaseSeekWaiters()
                return false
            }
        }
        // The revision publish IS the seek-COMPLETION ACK: it lands only
        // after the actual queue barrier (or trivially, for stateless
        // sources, which have no cross-ACK production).
        if let commit {
            do {
                presentationRevision = try commit.bumpRevision()
            } catch {
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .presentationReset,
                               note: "seekRefused:\(error)")
                releaseSeekWaiters()
                return false   // no order reset, no successful-seek record
            }
        } else {
            presentationRevision &+= 1
        }
        lastPts = -Double.infinity
        lastDuration = 0.0
        if let a = seekAnchorSeconds {
            paceAnchorPts = a; paceAnchorWall = clock.nowSeconds()   // SHARED anchor (M4)
        } else {
            paceAnchorPts = nil   // arrival anchor: next frame owns the origin
        }
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .presentationReset)
        releaseSeekWaiters()
        return true
    }

    public func run() async -> PumpStats {
        var stats = PumpStats()
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .videoPumpStart)
        // S3 SINGLE FINALIZATION: every exit lands here exactly ONCE with
        // ONE typed end reason and ONE videoPumpEnd. There is no early
        // return anywhere below (cancelled-in-wait missing its end record
        // was an actual defect - architect ruling, L6 witness W1B).
        var reason: PumpEndReason = .none
        var starveBackoff = 0.002
        pumpLoop: while true {
            // Verdict 3g: the SHARED cell cancel is checked by the outer
            // loop too, not only Task cancellation.
            if Task.isCancelled || (commit?.isCancelled ?? false) {
                commit?.requestCancel()
                stats.cancelled = true
                reason = .cancelled
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: "cancelled")
                break
            }
            // Verdict S5 rev5: IMMUTABLE PRODUCER STAMP - the revision
            // is captured BEFORE the pull await, and the frame this pull
            // returns is admitted ONLY under that stamp. A seek ACK
            // landing DURING the pull (or during a later pacing wait for
            // the same frame) makes the stamp stale: the parked old
            // frame mints NO new-revision ticket and lands NO commit -
            // a typed fence, never a live rewind.
            // Cancel recheck AFTER the await, BEFORE any sink admission
            // (S3): a cancel observed here admits nothing further; frames
            // already admitted COUNT (no rollback).
            // Verdict S5 rev6: stamp with the LIVE revision at pull
            // start - post-ACK production on a stateless source admits;
            // a stamp that no longer matches post-await means the
            // revision moved DURING the pull (fenced typed below).
            let pullRevision = commit?.revision ?? presentationRevision
            let pulledEvent = await source.nextEvent()
            // Verdict S5 rev6: POST-AWAIT PROVENANCE GATE - immediately
            // after the await, BEFORE any EOS/failure/pts-order/drop/wait
            // semantic mutation. (i) A pull returning while a seek
            // barrier is in flight has unknowable provenance: park until
            // the barrier resolves, then fence the event typed and
            // re-pull. (ii) A stamp that no longer matches means the
            // revision moved DURING the pull: fence typed and re-pull.
            if seekBarrierInFlight {
                await waitForSeekBarrier()
                stats.seekStalePulls += 1
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .staleRevisionFenced, note: "barrierPullFence")
                continue
            }
            if pullRevision != (commit?.revision ?? presentationRevision) {
                stats.seekStalePulls += 1
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .staleRevisionFenced, note: "stalePullFence")
                continue
            }
            switch pulledEvent {
            case .temporarilyUnavailable:
                stats.starveWaits += 1
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .frameWait,
                               note: "starveWait_s=\(starveBackoff)")
                if await !onWait(starveBackoff) {
                    commit?.requestCancel()
                    stats.cancelled = true
                    reason = .cancelled
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .terminal, note: "cancelledInStarveWait")
                    break pumpLoop
                }
                // Verdict 3g: the wait COMPLETED but a shared-cell cancel
                // may have landed during it - without this check the
                // pump starves endlessly after the ACK.
                if commit?.isCancelled ?? false {
                    stats.cancelled = true
                    reason = .cancelled
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .terminal, note: "cancelledAfterStarveWait")
                    break pumpLoop
                }
                starveBackoff = min(starveBackoff * 2, 0.05)   // bounded backoff, never an end
                continue
            case .ended(let r):
                // r3 S5: a source-reported cancel sets the typed cancel
                // flag too (r2 defect: stats.cancelled stayed false).
                if r == .cancelled { commit?.requestCancel(); stats.cancelled = true }
                reason = (r == .endOfStream) ? .endOfStream : (r == .cancelled ? .cancelled : .sourceEnded)
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: r.rawValue)
                break pumpLoop
            case .failed(let code):
                reason = .failed(code)
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .terminal, note: reason.rawValue)
                break pumpLoop
            case .frame(let frame):
                starveBackoff = 0.002   // a delivered frame resets starve backoff
                if Task.isCancelled || (commit?.isCancelled ?? false) {
                    // Cancel arrived DURING the pull (task or shared
                    // commit): the frame is NOT admitted (cancel-ACK
                    // serializes admission, S3/S5).
                    commit?.requestCancel()
                    stats.cancelled = true
                    reason = .cancelled
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .terminal, note: "cancelledBeforeAdmission")
                    break pumpLoop
                }
            // (item 4) refuse non-finite provider timing at the boundary.
            guard frame.ptsSeconds.isFinite, frame.durationSeconds.isFinite, frame.durationSeconds > 0 else {
                stats.nonFiniteDrops += 1
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .ptsNonFiniteDrop)
                continue
            }
            // (item 1) out-of-order provider pts is a typed drop, not a trap.
            guard frame.ptsSeconds >= lastPts else {
                stats.outOfOrderDrops += 1
                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                               subsystem: .video, kind: .ptsBackwardDrop, pts: frame.ptsSeconds)
                continue
            }
            // L1 (architect cond. 2): a forward pts gap is a CLASSIFIED
            // OBSERVATION inside the reported segment. Behavior is unchanged;
            // the gap is recorded, never smoothed, and never claimed as a
            // discontinuity PASS.
            if lastPts > -Double.infinity, lastDuration > 0 {
                let gap = frame.ptsSeconds - (lastPts + lastDuration)
                if gap > lastDuration / 2 {
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .ptsGapForward, pts: frame.ptsSeconds,
                                   note: "gap_s=\(gap)")
                }
            }
            lastPts = frame.ptsSeconds // per-run tracking; resetPresentation() on seek
            lastDuration = frame.durationSeconds
            // (item 3) decision loop: after any wait, re-decide against the
            // CURRENT clock; a frame can become drop-late or still-early
            // while waiting. Bounded by maxWaitSeconds per iteration.
            var guardCount = 0
            while true {
                guardCount += 1
                if guardCount > 100 {
                    // Pathological clock: TYPED drop, never a silent one
                    // (r3 S5), and a cancel that arrived during the retry
                    // storm is still honored (r2 defect: ignored here).
                    stats.dropped += 1
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .frameDroppedLate, pts: frame.ptsSeconds,
                                   note: "pathologicalClockRetryLimit")
                    if Task.isCancelled || (commit?.isCancelled ?? false) {
                        commit?.requestCancel()
                        stats.cancelled = true
                        reason = .cancelled
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                       subsystem: .video, kind: .terminal, note: "cancelledAtRetryLimit")
                        break pumpLoop
                    }
                    break
                }
                if paceAnchorPts == nil { paceAnchorPts = frame.ptsSeconds; paceAnchorWall = clock.nowSeconds() }
                let pacedNow = paceAnchorPts! + (clock.nowSeconds() - paceAnchorWall)
                switch decider.decide(ptsSeconds: frame.ptsSeconds, nowSeconds: pacedNow, frameDuration: frame.durationSeconds) {
                case .show:
                    // r3 S5: when a shared commit is wired, admission is
                    // ONE CAS on it - a cancel or seek racing this point
                    // can never interleave between check and admit (the
                    // r2 check->await suspension gap). Without a commit,
                    // the Task.isCancelled recheck is the fallback.
                    if let commit {
                        // Verdict 3f: propagate Task cancellation to the
                        // cell BEFORE admission (a completed pacing wait
                        // did not propagate it).
                        if Task.isCancelled { commit.requestCancel() }
                        // Admission is ONE CAS returning an immutable
                        // per-frame ticket (rev2); nil = typed refusal.
                        if let ticket = commit.tryAdmit(revision: pullRevision,
                                                        framePTS: frame.ptsSeconds,
                                                        frameDigest: frame.digest) {
                            // The ticket TRAVELS WITH THE FRAME: the sink
                            // validates it on-actor immediately before the
                            // contents commit (ACK = no further commit).
                            let accepted = await sink.show(frame, admission: ticket)
                            if accepted {
                                stats.shown += 1; stats.digestsShown.append(frame.digest)
                                ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                               subsystem: .video, kind: .frameShown, pts: frame.ptsSeconds)
                            } else {
                                stats.fencedShows += 1
                            }
                            break
                        } else if commit.isCancelled {
                            stats.cancelled = true
                            reason = .cancelled
                            ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                           subsystem: .video, kind: .terminal, note: "cancelledBeforeShow")
                            break pumpLoop
                        } else {
                            // Stale revision (an external seek raced us)
                            // or a saturated admission count: TYPED fence,
                            // not an admission, not an end.
                            stats.fencedShows += 1
                            ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                           subsystem: .video, kind: .staleRevisionFenced, pts: frame.ptsSeconds,
                                           note: commit.admissionExhausted ? "admissionExhausted" : "staleRevision")
                            break
                        }
                    } else if Task.isCancelled {
                        stats.cancelled = true
                        reason = .cancelled
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                       subsystem: .video, kind: .terminal, note: "cancelledBeforeShow")
                        break pumpLoop
                    }
                    // Finding 4: frameShown is logged ONLY on an accepted
                    // show - a fenced upload (window closed) is not "shown".
                    let accepted = await sink.show(frame)
                    if accepted {
                        stats.shown += 1; stats.digestsShown.append(frame.digest)
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                       subsystem: .video, kind: .frameShown, pts: frame.ptsSeconds)
                    } else {
                        stats.fencedShows += 1
                    }
                case .drop:
                    stats.dropped += 1
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .frameDroppedLate, pts: frame.ptsSeconds)
                case .wait(let d):
                    stats.waits += 1
                    ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                   subsystem: .video, kind: .frameWait, pts: frame.ptsSeconds,
                                   note: "wait_s=\(d)")
                    // v4: a cancelled wait is TYPED - the pump ends
                    // cancelled, it does not re-decide as if time passed.
                    if await !onWait(d) {
                        commit?.requestCancel()
                        stats.cancelled = true
                        reason = .cancelled
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration,
                                       segment: .pump, subsystem: .video, kind: .terminal,
                                       note: "cancelledInWait")
                        break pumpLoop   // S3: single finalization - NO early return (was the W1B defect)
                    }
                    // Verdict S5 rev6: a COMPLETED wait re-validates
                    // the pull-stamp BEFORE re-deciding - a seek ACK or
                    // barrier landing during the wait fences the frame
                    // typed instead of re-admitting it under a new ticket.
                    if pullRevision != (commit?.revision ?? presentationRevision) || seekBarrierInFlight {
                        stats.seekStalePulls += 1
                        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                                       subsystem: .video, kind: .staleRevisionFenced, pts: frame.ptsSeconds,
                                       note: "staleWaitFence")
                        break
                    }
                    continue // re-decide after a COMPLETED wake
                }
                break
            }
            }
        }
        // THE single finalization: one end reason, one pumpEnd, no
        // after-end events from this pump.
        stats.endReason = reason
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .videoPumpEnd,
                       bytes: stats.shown, note: "shown=\(stats.shown) dropped=\(stats.dropped) endReason=\(reason.rawValue)")
        return stats
    }
}


/// yuv420p -> RGBA, BT.601 limited range (K6 shell display path). Pure
/// Swift so it is Linux-testable; the macOS DisplaySink calls this.
/// Stride-explicit: callers pass each plane's stride; never assume
/// stride == width on provider-side buffers.
public enum YUV420Converter {
    public static func rgbaFromYUV420p(y: UnsafePointer<UInt8>, yStride: Int,
                                       u: UnsafePointer<UInt8>, uStride: Int,
                                       v: UnsafePointer<UInt8>, vStride: Int,
                                       width: Int, height: Int) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        func clamp8(_ x: Int) -> UInt8 { UInt8(Swift.max(0, Swift.min(255, x))) }
        for row in 0..<height {
            for col in 0..<width {
                let yv = Int(y[row * yStride + col])
                let uv = Int(u[(row / 2) * uStride + col / 2]) - 128
                let vv = Int(v[(row / 2) * vStride + col / 2]) - 128
                let c = yv - 16
                let o = (row * width + col) * 4
                out[o]     = clamp8((298 * c + 409 * vv + 128) >> 8)
                out[o + 1] = clamp8((298 * c - 100 * uv - 208 * vv + 128) >> 8)
                out[o + 2] = clamp8((298 * c + 516 * uv + 128) >> 8)
            }
        }
        return out
    }
}

/// Admission decision of one PCM push (L1, architect cond. 1).
public struct PushOutcome: Sendable, Equatable {
    public var admitted = 0
    public var dropped = 0
    public var availBefore = 0
    public var availAfter = 0
    public init(availBefore: Int) { self.availBefore = availBefore }
}

/// PCM ring buffer for audio output sinks (K6 shell audio path). Pure
/// Swift, Linux-testable: the macOS AudioUnitSink render callback pulls
/// from this; the decoder side pushes. mpv 0.41.0 ao_audiounit.c pulls
/// from its own buffer the same way; underrun renders silence.
/// Single producer + single consumer, each side serialized by its caller
/// (decoder queue / AudioUnit render thread) - internal NSLock guards the
/// shared indices.
public final class PCMRingBuffer: @unchecked Sendable {
    private var ring: [UInt8]
    private var readPos = 0, writePos = 0, avail = 0
    private let lock = NSLock()
    private var kitConsumed = 0
    public var kitConsumedBytes: Int { lock.lock(); defer { lock.unlock() }; return kitConsumed }
    public private(set) var overrunDrops = 0
    public private(set) var underrunBytes = 0
    // L1 (architect cond. 1): admission accounting. The queue-capacity bound
    // may only be claimed from these RECORDED maxima (QueueBoundEvidence),
    // never from the watermark constant alone.
    public private(set) var pushCount = 0
    public private(set) var maxPushBytes = 0
    public private(set) var maxAvailAfterPush = 0
    public init(capacity: Int = 1 << 20) { ring = [UInt8](repeating: 0, count: capacity) }
    /// Push decoded PCM; DROP-NEWEST: when the ring is full, incoming bytes
    /// are dropped and counted (overrunDrops), oldest bytes are retained.
    /// Whether drop-newest vs drop-oldest is right for the product core is
    /// a policy decision; this probe pins drop-newest (team2 OBS-1).
    public func push(_ pcm: [UInt8]) { _ = pushCounted(pcm) }
    /// L1: push with admission accounting. Behavior is identical to push()
    /// (drop-newest on a full ring); the returned outcome records the
    /// admission decision so the queue bound can be VERIFIED per run.
    @discardableResult
    public func pushCounted(_ pcm: [UInt8]) -> PushOutcome {
        lock.lock(); defer { lock.unlock() }
        var out = PushOutcome(availBefore: avail)
        for b in pcm {
            if avail == ring.count { overrunDrops += 1; out.dropped += 1; continue }
            ring[writePos] = b
            writePos = (writePos + 1) % ring.count
            avail += 1
        }
        out.admitted = pcm.count - out.dropped
        out.availAfter = avail
        pushCount += 1
        maxPushBytes = Swift.max(maxPushBytes, pcm.count)
        maxAvailAfterPush = Swift.max(maxAvailAfterPush, avail)
        return out
    }
    /// Pull n bytes into freshly rendered output; shortfall is silence.
    public func render(_ n: Int) -> [UInt8] { renderCounted(n).out }
    /// L1: same render, plus the underrun byte count of THIS call, so the
    /// (off-callback) transition detector can classify underrun start/end
    /// without re-reading counters. Underrun silence is NEVER counted as
    /// consumed content: kitConsumed only advances on real bytes.
    public func renderCounted(_ n: Int) -> (out: [UInt8], underrun: Int) {
        lock.lock(); defer { lock.unlock() }
        var out = [UInt8](repeating: 0, count: n)
        var under = 0
        for i in 0..<n {
            if avail == 0 { underrunBytes += 1; under += 1 } else {
                out[i] = ring[readPos]
                readPos = (readPos + 1) % ring.count
                avail -= 1
                kitConsumed += 1
            }
        }
        return (out, under)
    }
    public var available: Int { lock.lock(); defer { lock.unlock() }; return avail }
}
