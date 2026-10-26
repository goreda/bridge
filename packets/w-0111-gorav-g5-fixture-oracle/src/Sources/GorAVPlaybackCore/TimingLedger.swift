// L1 REWORK v2 (architect PART1/PART2 verdict 2026-10-25, REVISION):
// bounded timing/lifecycle observability ("TimingLedger").
// Rework deltas against v1:
//  (finding 1/5) RTTransitionBuffer is REMOVED. The render callback posts
//    to SPSCEventRing (GorAVCAtomics-backed, preallocated, true SPSC with
//    acquire/release publication and a sticky overflow latch). An off-RT
//    fold stamps drained events with their POST-TIME clock reading, not
//    the drain time (finding 4).
//  (finding 5) QueueBoundEvidence.admissionBoundHolds now requires
//    overrun==0, recorded push count>0, maxAvail<=watermark+maxChunk, and
//    watermark+maxChunk<=capacity. The predicate lives HERE, in production
//    code - never asserted from tests.
//  (finding 8) Export is JSONEncoder-based (no manual interpolation), with
//    a versioned fixed header line, finite-value sanitization, bounded
//    notes (256 UTF-8 bytes) and a byte-bounded export with an explicit
//    truncation marker line. Non-finite clock readings refuse success.
//  (finding 3) OnceOnlyRelease is REMOVED: the sink lifecycle is a
//    per-generation state machine in the sink itself (re-armable across
//    start/stop cycles). GenerationFence is now atomic (GoravCAtomics).
import Foundation

public enum LedgerSegment: String, Sendable, Equatable, Codable { case open, pump, drain, teardown }
public enum LedgerSubsystem: String, Sendable, Equatable, Codable { case core, video, audio }
public enum LedgerKind: String, Sendable, Equatable, Codable {
    case ledgerOrigin
    // Typed lifecycle receipts (finding 4): attempt BEFORE the operation,
    // accepted AFTER it succeeded; a bare "happened" record is not a receipt.
    case audioStartAttempt, audioStartAccepted, audioStopAttempt, audioStopAccepted
    case videoPumpStart, videoPumpEnd
    case frameShown, frameDroppedLate, frameWait
    case displayAttempt, displayAccepted
    // PTS classification is OBSERVATION ONLY: no discontinuity PASS and no
    // general monotonic-PTS claim is derived from these (architect cond. 2).
    case ptsGapForward, ptsBackwardDrop, ptsNonFiniteDrop, presentationReset
    case audioPush, audioPushDrop
    case underrunStart, underrunEnd, staleCallbackFenced
    /// r3 S5: a show admission refused by the shared commit because the
    /// presentation revision moved (seek raced the pump). Typed fence,
    /// never an admission and never an end.
    case staleRevisionFenced
    case closeIntent, closeFenceSkip
    case drainStart, drainEnd
    case terminal, decodeError
    case stopCall, disposeCompleted
    case teardownStart, teardownComplete
    case rtOverflow, exportTruncated
}

public struct LedgerEvent: Sendable, Equatable, Codable {
    public let seq: UInt64
    public let session: UInt64
    public let generation: UInt64
    public let segment: LedgerSegment
    public let subsystem: LedgerSubsystem
    public let kind: LedgerKind
    public let tAbs: Double   // stamp on the shared origin clock (post time for RT folds)
    public let tRel: Double   // tAbs - origin
    public let pts: Double?
    public let bytes: Int
    public let note: String
}

/// Bounded lifecycle ledger. append() is OFF-RT ONLY (it allocates and
/// takes a lock). The render callback path uses SPSCEventRing + fold().
public final class TimingLedger: @unchecked Sendable {
    /// Fixed, versioned export schema. Any field change bumps this.
    public static let exportSchema = "gorav.timing-ledger/4"
    /// Note bound (finding 8): notes are program-generated but still capped.
    public static let maxNoteUTF8 = 256
    private var events: [LedgerEvent] = []
    private let capacity: Int
    private var seq: UInt64 = 0
    public private(set) var overflowed = false
    public private(set) var droppedEventCount = 0
    /// Non-finite clock readings make the record untrustworthy: refuse success.
    public private(set) var invalidStampCount = 0
    public private(set) var truncatedNoteCount = 0
    private let lock = NSLock()
    private let clock: @Sendable () -> Double
    public let origin: Double
    /// Explicit run identity (finding 7/8): carried into the export header.
    public let runID: String
    public let cwd: String
    /// Freshness nonce (v5, architect item 6): the kit exports GORAV_NONCE
    /// and the header carries it, so a stale/foreign LEDGER (not just a
    /// stale result) can never back a PASS.
    public let nonce: String
    public init(capacity: Int = 8192, clock: @Sendable @escaping () -> Double,
                runID: String = "", cwd: String = "", nonce: String = "") {
        self.capacity = capacity
        self.clock = clock
        self.origin = clock()
        self.runID = runID
        self.cwd = cwd
        self.nonce = nonce
    }
    private static func boundedNote(_ s: String) -> (String, Bool) {
        let utf8 = Array(s.utf8)
        if utf8.count <= maxNoteUTF8 { return (s, false) }
        return (String(decoding: utf8[0..<maxNoteUTF8], as: UTF8.self) + "~", true)
    }
    /// OFF-RT ONLY: allocates and locks. Never call from the render callback.
    public func append(session: UInt64, generation: UInt64, segment: LedgerSegment,
                       subsystem: LedgerSubsystem, kind: LedgerKind,
                       pts: Double? = nil, bytes: Int = 0, note: String = "") {
        lock.lock()
        seq += 1
        if events.count >= capacity {
            overflowed = true
            droppedEventCount += 1
            lock.unlock()
            return
        }
        var t = clock()
        var noteOut = note
        if !t.isFinite {
            // Typed, visible corruption - never an origin-substituted event
            // that LOOKS good (finding 6). Success is refused.
            invalidStampCount += 1
            t = origin
            noteOut = "INVALID_STAMP:" + noteOut
        }
        var p = pts
        if let v = p, !v.isFinite { invalidStampCount += 1; p = nil; noteOut = "INVALID_PTS:" + noteOut }
        let (n, truncated) = Self.boundedNote(noteOut)
        if truncated { truncatedNoteCount += 1 }
        events.append(LedgerEvent(seq: seq, session: session, generation: generation,
                                  segment: segment, subsystem: subsystem, kind: kind,
                                  tAbs: t, tRel: t - origin, pts: p, bytes: bytes, note: n))
        lock.unlock()
    }
    /// Fold RT events (SPSCEventRing drain) into the ledger. EVENT-TIME
    /// stamps: each RTEvent carries the post-time clock reading captured on
    /// the RT thread; tRel is derived from the shared origin (finding 4 -
    /// drains no longer re-stamp at drain time).
    public func fold(rt evs: [RTEvent], session: UInt64, segment: LedgerSegment) {
        for e in evs {
            let kind: LedgerKind
            switch e.kind {
            case .underrunStart: kind = .underrunStart
            case .underrunEnd: kind = .underrunEnd
            case .staleFenced: kind = .staleCallbackFenced
            }
            lock.lock()
            seq += 1
            if events.count >= capacity {
                overflowed = true
                droppedEventCount += 1
                lock.unlock()
                continue
            }
            let t = e.tEvent.isFinite ? e.tEvent : origin
            if !e.tEvent.isFinite { invalidStampCount += 1 }
            // v4: unit-typed payload -> the ledger's bytes field only ever
            // carries BYTES; frame counts convert EXACTLY (4 B/frame) and
            // the original unit stays visible in the note.
            let bytes: Int
            let unitNote: String
            switch e.payload {
            case .bytes(let b): bytes = Int(clamping: b); unitNote = "rtPost unit=bytes"
            case .frames(let f): bytes = Int(clamping: f &* 4); unitNote = "rtPost unit=frames4"
            }
            events.append(LedgerEvent(seq: seq, session: session, generation: e.generation,
                                      segment: segment, subsystem: .audio, kind: kind,
                                      tAbs: t, tRel: t - origin, pts: nil,
                                      bytes: bytes, note: unitNote))
            lock.unlock()
        }
    }
    /// Fold an RT-side overflow latch into the ledger: success is refused.
    public func foldRTOverflow() {
        lock.lock(); overflowed = true; lock.unlock()
        append(session: 0, generation: 0, segment: .teardown, subsystem: .core, kind: .rtOverflow)
    }
    /// Overflow or invalid stamps mean the lifecycle record is incomplete
    /// and MUST NOT back a PASS (consumed by runMuxed - finding 7).
    public var allowsSuccess: Bool {
        lock.lock(); defer { lock.unlock() }
        return !overflowed && invalidStampCount == 0
    }
    public var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    public func snapshot() -> [LedgerEvent] { lock.lock(); defer { lock.unlock() }; return events }

    private struct ExportHeader: Codable {
        let type: String
        let schema: String
        let runID: String
        let cwd: String
        let origin: Double
        /// v4 (full-review): events are emitted in PUBLICATION order (seq),
        /// each carrying its own event-time stamp. Publication sequence and
        /// event chronology are SEPARATE facts; no sort folds a late RT
        /// post backwards and rewrites the publication record.
        let order: String
        let nonce: String
    }
    private struct TruncationMarker: Codable {
        let type: String
        let omittedEvents: Int
        let writtenEvents: Int
        let maxBytes: Int
    }
    /// JSONL export v3 (finding 8 + v2-review finding 6): JSONEncoder,
    /// fixed schema header, byte bound with the truncation marker RESERVED
    /// up front (the marker always fits), events emitted in EVENT-TIME
    /// order (tAbs, seq tiebreak) so folded RT events with post-time stamps
    /// interleave chronologically, a header write failure is typed, and the
    /// truncation marker is a RECEIPT (written/omitted/cap).
    public private(set) var lastExportTruncated = false
    public private(set) var lastExportHeaderFailed = false
    public func jsonLines(maxBytes: Int = 750_000) -> String {
        let evs = snapshot() // publication order (seq) - never re-sorted
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        lock.lock()
        lastExportTruncated = false
        lastExportHeaderFailed = false
        lock.unlock()
        var out = ""
        func line<T: Encodable>(_ v: T) -> String? {
            guard let data = try? enc.encode(v), let s = String(data: data, encoding: .utf8) else { return nil }
            return s + "\n"
        }
        guard let header = line(ExportHeader(type: "header", schema: Self.exportSchema,
                                             runID: runID, cwd: cwd, origin: origin,
                                             order: "publication", nonce: nonce)) else {
            lock.lock(); lastExportHeaderFailed = true; lock.unlock()
            return ""
        }
        if header.utf8.count >= maxBytes {
            lock.lock(); lastExportHeaderFailed = true; lock.unlock()
            return ""
        }
        out += header
        // Reserve room for the worst-case truncation marker NOW; events
        // must fit in what remains.
        let markerProbe = line(TruncationMarker(type: "truncated", omittedEvents: evs.count,
                                                writtenEvents: 0, maxBytes: maxBytes)) ?? ""
        // L9 W1 / RW21a (architect-reviewed finding, FIXED): the budget
        // reserves BOTH the header AND the marker; subtracting the marker
        // alone let total = header + (maxBytes - marker) exceed maxBytes.
        // maxBytes < header + marker is a TYPED REFUSAL (headerFailed),
        // never a silent over-ceiling export.
        let budget = maxBytes - header.utf8.count - markerProbe.utf8.count
        if budget < 0 {
            lock.lock(); lastExportHeaderFailed = true; lock.unlock()
            return ""
        }
        var written = 0
        for e in evs {
            guard let l = line(e) else { break }
            if out.utf8.count + l.utf8.count > budget { break }
            out += l
            written += 1
        }
        if written < evs.count {
            // L9 W2 / RW21b (FIXED): an export-formatting budget truncates
            // the PRESENTATION ONLY. It never sets overflowed and never
            // flips allowsSuccess - ingestion-side record loss (capacity)
            // owns that verdict; a small export budget is not data loss.
            lock.lock(); lastExportTruncated = true; lock.unlock()
            if let marker = line(TruncationMarker(type: "truncated", omittedEvents: evs.count - written,
                                                  writtenEvents: written, maxBytes: maxBytes)) {
                out += marker
            }
        }
        return out
    }
    /// Required-event completeness (finding 6): overflow-freedom is NOT
    /// lifecycle completeness. A run's success additionally requires the
    /// named lifecycle events to be PRESENT; the caller folds the missing
    /// list into its verdict, so missing teardown/terminal events can never
    /// silently PASS.
    /// v4 (full-review): ORDERED, PER-SESSION/GENERATION completeness.
    /// `required` must appear as an IN-ORDER SUBSEQUENCE among events of
    /// EXACTLY this session+generation - a kind fulfilled by a foreign
    /// session, a different generation, or out of order does NOT count.
    public func missingSequence(session: UInt64, generation: UInt64,
                                required: [LedgerKind]) -> [LedgerKind] {
        let own = snapshot().filter { $0.session == session && $0.generation == generation }.map { $0.kind }
        var idx = 0
        var missing: [LedgerKind] = []
        for k in required {
            var found = false
            while idx < own.count {
                let cur = own[idx]; idx += 1
                if cur == k { found = true; break }
            }
            if !found { missing.append(k) }
        }
        return missing
    }
    /// Back-compat set-membership check (kept for older callers; new code
    /// uses missingSequence).
    public func missingKinds(_ required: [LedgerKind]) -> [LedgerKind] {
        let have = Set(snapshot().map { $0.kind })
        return required.filter { !have.contains($0) }
    }
}

/// Stale-generation fence on C11 atomics (finding 1): `active` is written
/// only by the non-RT owner (start/stop) and read by the RT callback with
/// an acquire load; `fencedCount` is RT-side. No locks on the RT path.
public final class GenerationFence: @unchecked Sendable {
    private let cell: AtomicU64
    private let fenced: AtomicU64
    public var active: UInt64 { cell.load() }
    public var fencedCount: Int { Int(fenced.load()) }
    public init() {
        // v4: C-owned cell allocation can be REFUSED (typed); at bring-up
        // the only honest failure is a loud one, never a non-atomic fallback.
        guard let cell = AtomicU64(1), let fenced = AtomicU64() else {
            fatalError("GenerationFence: C atomic cell allocation refused")
        }
        self.cell = cell; self.fenced = fenced
    }
    /// Non-RT owner side: advance at every stop boundary so any callback
    /// still carrying the previous generation goes stale.
    public func advance() { cell.fetchAdd(1) }
    /// Non-RT owner side: set the active generation explicitly at start
    /// commit. Release store; RT readers acquire-load.
    public func setActive(_ g: UInt64) { cell.store(g) }
    /// RT-safe: atomic acquire load + compare. Stale callers are counted.
    public func checkRT(_ generation: UInt64) -> Bool {
        if generation == cell.load() { return true }
        fenced.fetchAdd(1)
        return false
    }
}

/// Audio pump terminal classification shared with the core so the end-reason
/// mapping is testable off-Mac (architect cond. 6: cancel / decode error /
/// EOS are DISTINCT end reasons).
public enum AudioTerminalKind: String, Sendable, Equatable {
    case endOfStream, failed, sourceEnded, stoppedEarly, cancelled
}
public enum EndReason: String, Sendable, Equatable {
    case endOfStream, decodeFailed, sourceEnded, userClose, stoppedEarly, cancelled
    public static func from(audioTerminal t: AudioTerminalKind, closeIntent: Bool) -> EndReason {
        switch t {
        case .endOfStream: return .endOfStream
        case .failed: return .decodeFailed
        case .sourceEnded: return .sourceEnded
        case .stoppedEarly: return closeIntent ? .userClose : .stoppedEarly
        case .cancelled: return .cancelled
        }
    }
    /// Finding 6: combined A/V terminal with EXPLICIT priority. When the
    /// video pump and the audio pump end for different reasons the run's
    /// end reason is the highest-priority distinct reason, never whichever
    /// await happened to return last. Priority: failure > cancel > close >
    /// early stop > source end > EOS.
    ///
    /// ARCHITECT FULL VERDICT S4: this priority ordering is a DISPLAY
    /// SUMMARY, never a causal identity. The per-leg terminals, the close
    /// intent (with time), the cancel reason, the failures and the
    /// teardown outcomes are preserved SEPARATELY (RunTerminal) - nothing
    /// downstream may reconstruct causality from the summary alone.
    public static func combined(audio a: EndReason, video v: EndReason) -> EndReason {
        func rank(_ r: EndReason) -> Int {
            switch r {
            case .decodeFailed: return 5
            case .cancelled: return 4
            case .userClose: return 3
            case .stoppedEarly: return 2
            case .sourceEnded: return 1
            case .endOfStream: return 0
            }
        }
        return rank(a) >= rank(v) ? a : v
    }
}

/// r3 S4: scalar mirror of the audio stop OUTCOME (module-safe; the
/// enum itself lives on the lane-0 seam).
public enum StopOutcomeKind: String, Sendable, Equatable {
    case complete, failed, pending, noop, notRun
}

/// r3 S4: the DECODER CLOSE result carried as scalars (the adapter's
/// CloseReport must not cross into the core). A discarded close result
/// was an r2 defect; unknown = the whole value is nil, never zeroed.
public struct DecoderCloseSummary: Sendable, Equatable {
    public let leakedHandles: Int
    public let droppedPendingPackets: Int
    public let leaseTableLeaks: Int
    public let ledgerLeaks: Int
    /// Raw logical teardown state (absent/called/completed); logical
    /// invocation evidence only, NOT native free/refcount/leak proof.
    public let logicalTeardown: String
    public init(leakedHandles: Int, droppedPendingPackets: Int, leaseTableLeaks: Int,
                ledgerLeaks: Int, logicalTeardown: String) {
        self.leakedHandles = leakedHandles; self.droppedPendingPackets = droppedPendingPackets
        self.leaseTableLeaks = leaseTableLeaks; self.ledgerLeaks = ledgerLeaks
        self.logicalTeardown = logicalTeardown
    }
    /// Close clean = zero counted leaks AND a teardown that is not stuck
    /// at "called" (absent = nothing to tear down; completed = returned).
    public var clean: Bool {
        leakedHandles == 0 && leaseTableLeaks == 0 && ledgerLeaks == 0 && logicalTeardown != "called"
    }
}

/// S4: the run's typed terminal record. The summary (combined) travels
/// WITH the separated evidence; it never replaces it.
public struct RunTerminal: Sendable, Equatable {
    public let audio: EndReason
    public let video: EndReason
    /// Display summary only (S4) - NOT a causal identity.
    public let summary: EndReason
    public let closeIntent: Bool
    /// Drain residual bytes at stop (local bounded drain, NOT a provider
    /// guarantee); -1 when no audio leg ran.
    public let audioDrainResidual: Int
    /// Teardown clean = the audio stop outcome was .complete for the leg
    /// that ran (r3: "not failed" would wrongly accept pending/noop).
    public let teardownClean: Bool
    /// r3 S4: the typed audio stop outcome actually observed.
    public let audioStop: StopOutcomeKind
    /// r3 S4: the decoder close result (nil = no close report exists;
    /// that is UNKNOWN, never treated as clean).
    public let decoderClose: DecoderCloseSummary?
    /// r3 S4: the audio leg's typed failure code, when it failed.
    public let failureCode: Int?
    public init(audio: EndReason, video: EndReason, closeIntent: Bool,
                audioDrainResidual: Int, teardownClean: Bool,
                audioStop: StopOutcomeKind, decoderClose: DecoderCloseSummary?,
                failureCode: Int?) {
        self.audio = audio; self.video = video
        self.summary = EndReason.combined(audio: audio, video: video)
        self.closeIntent = closeIntent
        self.audioDrainResidual = audioDrainResidual
        self.teardownClean = teardownClean
        self.audioStop = audioStop
        self.decoderClose = decoderClose
        self.failureCode = failureCode
    }
    /// S4/r3: a run is an EOS SUCCESS only when every leg that ran ended
    /// in EXPLICIT EOS, the drain measured empty, the teardown COMPLETED,
    /// the decoder close report exists and is clean, and there was NO
    /// close intent and NO cancellation on either leg. sourceEnded is
    /// NEVER EOS (it is exhaustion without an explicit terminal).
    public var isEOSSuccess: Bool {
        teardownClean && audioDrainResidual == 0 && !closeIntent
            && audioStop == .complete
            && (decoderClose?.clean ?? false)
            && audio == .endOfStream && video == .endOfStream
    }
}

/// Same-actor upload fence decision (architect cond. 3): evaluated ON the
/// uploading actor immediately before the layer contents assignment, so a
/// frame that passed the pump-side stop check but races a close intent is
/// still fenced. Pure decision; the DisplaySink wires it on MainActor.
public enum UploadFence {
    public static func mayUpload(closeIntent: Bool) -> Bool { !closeIntent }
    /// r3 S5: the on-actor upload decision fences on close intent AND
    /// the shared cancel commit AND the presentation revision - the r2
    /// fence covered close only, so a cancel/seek racing an in-flight
    /// upload could still land a stale frame on the layer.
    public static func mayUpload(closeIntent: Bool, cancelled: Bool,
                                 frameRevision: UInt64, currentRevision: UInt64) -> Bool {
        !closeIntent && !cancelled && frameRevision == currentRevision
    }
}

/// Architect cond. 1 + finding 5: the watermark is NOT a queue bound until
/// chunk admission is proven from RECORDED maxima. The predicate lives in
/// THIS production type; tests only exercise it. A bound claim requires:
/// recorded pushes (pushCount>0 and maxChunkBytes>0), zero overrun drops,
/// maxAvail within watermark+maxChunk, and watermark+maxChunk within capacity.
public struct QueueBoundEvidence: Sendable, Equatable {
    public let capacity: Int
    public let watermark: Int
    public let maxChunkBytes: Int
    public let maxAvailAfterPush: Int
    public let overrunDrops: Int
    public let pushCount: Int
    public init(capacity: Int, watermark: Int, maxChunkBytes: Int, maxAvailAfterPush: Int,
                overrunDrops: Int, pushCount: Int) {
        self.capacity = capacity; self.watermark = watermark
        self.maxChunkBytes = maxChunkBytes; self.maxAvailAfterPush = maxAvailAfterPush
        self.overrunDrops = overrunDrops; self.pushCount = pushCount
    }
    public var admissionBoundHolds: Bool {
        // v3-4: reject invalid inputs instead of trapping or silently
        // accepting negative/overflowing arithmetic.
        guard capacity > 0, watermark >= 0, maxChunkBytes >= 0, maxAvailAfterPush >= 0,
              overrunDrops >= 0, watermark <= capacity, maxChunkBytes <= capacity,
              maxAvailAfterPush <= capacity else { return false }
        // Overflow-free comparison (v5 item 5): never ADD two Ints whose
        // sum can exceed Int.max - compare by subtraction instead.
        let boundHolds = maxAvailAfterPush <= watermark
            || (maxAvailAfterPush - watermark) <= maxChunkBytes
        // watermark+maxChunk<=capacity without addition:
        // maxChunkBytes <= capacity - watermark (both sides non-negative).
        let boundWithinCapacity = maxChunkBytes <= capacity - watermark
        return maxChunkBytes > 0 && pushCount > 0
            && overrunDrops == 0
            && boundWithinCapacity
            && boundHolds
    }
    public var summary: String {
        "capacity=\(capacity) watermark=\(watermark) maxChunk=\(maxChunkBytes) maxAvailAfterPush=\(maxAvailAfterPush) overrunDrops=\(overrunDrops) pushes=\(pushCount) admissionBound=\(admissionBoundHolds ? 1 : 0)"
    }
}

/// Per-generation session lifecycle v3 (v2-review finding 2). The state
/// machine SERIALIZES start/stop: a new start is admitted ONLY from idle;
/// stop moves active->stopping and the generation stays occupied until
/// teardown completes (finishStop) or fails closed (failStop -> failed,
/// terminal: a leaked session is never overwritten by a new start).
/// stop during starting does NOT touch the unit or the retain: the start
/// side observes commitStart()==false and performs the teardown itself.
/// r3-rev1 S4 (peer findings 7-9): GENERATION-BOUND stop-outcome
/// publication, serialized BEFORE the lifecycle transition.
///  - a cached outcome is returned ONLY for the current generation
///    (a new start invalidates the previous generation's cache);
///  - while a stop is IN FLIGHT the idle query returns .pending, never
///    a stale cached outcome and never a bare .noop;
///  - publication happens BEFORE lifecycle.failStop/finishStop, so a
///    new start can never overwrite an unpublished outcome.
/// The sink delegates here; the policy is testable off-Mac.
public final class StopOutcomeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var published: (generation: UInt64, outcome: AudioStopOutcome)?
    private var stopInFlight = false
    private var latestGeneration: UInt64 = 0
    public init() {}
    /// A new session start invalidates the previous generation's cache.
    public func noteStart(generation g: UInt64) {
        lock.lock(); latestGeneration = g; published = nil; stopInFlight = false; lock.unlock()
    }
    /// Mirror of the lifecycle's stopping state (set when a teardown is
    /// owned, cleared on publication).
    public func noteStopInFlight() { lock.lock(); stopInFlight = true; lock.unlock() }
    /// Publish the terminal outcome for generation g. Call BEFORE the
    /// lifecycle transition (finding 9). A STALE-generation publish is a
    /// TYPED REFUSAL (verdict S4): it must not overwrite the new
    /// generation's cache nor clear its in-flight marker.
    @discardableResult
    public func publish(generation g: UInt64, outcome: AudioStopOutcome) -> Bool {
        lock.lock()
        guard g == latestGeneration else { lock.unlock(); return false }
        published = (g, outcome); stopInFlight = false; lock.unlock()
        return true
    }
    /// Idle-path query: .pending while a stop is in flight; the cached
    /// outcome only when it belongs to the current generation; else
    /// .noop (no evidence exists).
    public func idleOutcome() -> AudioStopOutcome {
        lock.lock(); defer { lock.unlock() }
        if stopInFlight { return .pending }
        if let p = published, p.generation == latestGeneration { return p.outcome }
        return .noop
    }
}

public final class SessionLifecycle: @unchecked Sendable {
    public enum State: Equatable, Sendable { case idle, starting(UInt64), active(UInt64), stopping(UInt64), failed(UInt64) }
    public enum StopBegin: Equatable, Sendable {
        case teardownOwned(UInt64)      // caller performs the hardware teardown
        case startWillTearDown(UInt64)  // stop raced a start: fence only; start tears down
        case none                       // no-op: nothing consumed, nothing released
    }
    private var state: State = .idle
    private var nextGeneration: UInt64 = 1
    /// v4: the RUNNING flag lives INSIDE this lock. commitStart sets it in
    /// the SAME atomic transition that activates the session; beginStop
    /// clears it in the SAME transition that begins teardown - there is no
    /// window where a stop can tear down and a late `running = true` can
    /// resurrect a stopped session.
    private var runningGeneration: UInt64? = nil
    private let lock = NSLock()
    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    public private(set) var refusedStartCount = 0
    public private(set) var refusedStartFailedCount = 0 // starts refused on a FAILED session
    public private(set) var noOpStopCount = 0
    public private(set) var abortedStartCount = 0
    public private(set) var failedSessionCount = 0
    public init() {}
    public var current: State { lock.lock(); defer { lock.unlock() }; return state }
    /// Reserve a generation for a new session. nil = busy (starting/active/
    /// stopping) or terminal (failed); the caller MUST NOT touch hardware.
    /// `onStart` runs INSIDE the lifecycle lock when a generation is
    /// born (verdict S4 rev2): the sink binds its outcome cache to the
    /// new generation ATOMICALLY with the birth - a stop racing the
    /// beginStart->bind window can never mark/clear the WRONG cache
    /// generation. Lock order is always lifecycle -> cache.
    public func beginStart(andThen onStart: ((UInt64) -> Void)? = nil) -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        switch state {
        case .idle:
            let g = nextGeneration
            nextGeneration &+= 1
            state = .starting(g)
            onStart?(g)
            return g
        case .failed:
            refusedStartFailedCount += 1
            return nil
        default:
            refusedStartCount += 1
            return nil
        }
    }
    /// Start succeeded; the session is live. false = a stop raced the start
    /// (state stopping): the caller tears its just-started unit down itself
    /// and then calls finishStop.
    @discardableResult public func commitStart(_ g: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard case .starting(let s) = state, s == g else { return false }
        state = .active(g)
        runningGeneration = g   // running is born WITH the active transition
        startCount += 1
        return true
    }
    /// The single atomic running query (producer gate): non-nil ONLY while
    /// the session is active AND no teardown has begun.
    public var runningGen: UInt64? { lock.lock(); defer { lock.unlock() }; return runningGeneration }
    /// Start failed partway: roll back to idle so the next start re-arms.
    /// If a stop raced (state stopping), the rollback completes that stop.
    public func abortStart(_ g: UInt64) {
        lock.lock(); defer { lock.unlock() }
        switch state {
        case .starting(let s) where s == g:
            abortedStartCount += 1
            state = .idle
        case .stopping(let s) where s == g:
            abortedStartCount += 1
            stopCount += 1
            runningGeneration = nil
            state = .idle
        default:
            break
        }
    }
    /// v4: a partial start whose OWN cleanup could not be proven (uninit or
    /// dispose status ignored is NOT acceptable): ANY unresolved teardown
    /// is TERMINAL - the instance fails closed and refuses future starts
    /// rather than risking a leaked unit being overwritten.
    public func failStart(_ g: UInt64) {
        lock.lock(); defer { lock.unlock() }
        switch state {
        case .starting(let s) where s == g, .stopping(let s) where s == g:
            failedSessionCount += 1
            runningGeneration = nil
            state = .failed(g)
        default:
            break
        }
    }
    /// Begin teardown. The generation stays OCCUPIED (stopping) until
    /// finishStop/failStop - no new start is admitted while teardown runs.
    /// `onStopTransition` runs INSIDE the lifecycle lock whenever the
    /// decision starts a teardown (owned or start-owned): the sink marks
    /// its outcome cache in-flight ATOMICALLY with the transition -
    /// verdict S4: a marker taken AFTER beginStop leaves a noop gap.
    public func beginStop(onStopTransition: (() -> Void)? = nil) -> StopBegin {
        lock.lock(); defer { lock.unlock() }
        switch state {
        case .active(let g):
            runningGeneration = nil  // running dies WITH the stop transition
            state = .stopping(g)
            onStopTransition?()
            return .teardownOwned(g)
        case .starting(let g):
            state = .stopping(g)
            onStopTransition?()
            return .startWillTearDown(g)
        case .stopping, .failed, .idle:
            if case .idle = state { noOpStopCount += 1 }
            return .none
        }
    }
    /// Teardown completed with proven quiescence: generation retires.
    public func finishStop(_ g: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard case .stopping(let s) = state, s == g else { return }
        stopCount += 1
        state = .idle
    }
    /// Teardown FAILED (stop/uninit error, or in-flight callback join
    /// timeout): the session is TERMINAL. The unit and the strong retain
    /// are kept (a logged leak, never a UAF); future starts are refused so
    /// a new session can never overwrite the held resources.
    public func failStop(_ g: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard case .stopping(let s) = state, s == g else { return }
        failedSessionCount += 1
        state = .failed(g)
    }
}

