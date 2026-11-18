# W-gdb-199g-in2tinct-31 - Bounded UTF8 ledger notes and valid origin
state: OPEN / unclaimed

LIVE-CALLER BOUND: ShellFrameSource.swift lines614/655 constructs TimingLedger. Exact ledger enums/event/class and RTEvent DTO compile. GenerationFence and C atomic sections are excluded. Native audio path NOT_RUN.
lab: in2tinct

Make boundedNote return at most maxNoteUTF8 bytes INCLUDING its truncation suffix, with valid UTF8 and no split scalar expansion. A nonfinite origin must cause allowsSuccess to refuse from creation. Preserve publication ordering, export-budget-only semantics and finite stamps. File is used by ShellFrameSource at lines614/655; this isolates the actual ledger class, excluding unrelated GenerationFence/C atomic sections.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199g-in2tinct-31",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/TimingLedger.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Make boundedNote return at most maxNoteUTF8 bytes INCLUDING its truncation suffix, with valid UTF8 and no split scalar expansion. A nonfinite origin must cause allowsSuccess to refuse from creation. Preserve publication ordering, export-budget-only semantics and finite stamps. File is used by ShellFrameSource at lines614/655; this isolates the actual ledger class, excluding unrelated GenerationFence/C atomic sections.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "LIVE-CALLER BOUND: ShellFrameSource.swift lines614/655 constructs TimingLedger. Exact ledger enums/event/class and RTEvent DTO compile. GenerationFence and C atomic sections are excluded. Native audio path NOT_RUN.",
    "callee": "Sources/GorAVPlaybackCore/TimingLedger.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199g/W-gdb-199g-in2tinct-31.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199g-in2tinct-31",
    "paths": [
      "Sources/GorAVPlaybackCore/TimingLedger.swift",
      "Tests/Architecture/199g/W-gdb-199g-in2tinct-31.py",
      "Tests/Architecture/199g/W-gdb-199g-in2tinct-31.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199g/W-gdb-199g-in2tinct-31.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/TimingLedger.swift",
        "block": "source1",
        "sha256": "cfbcffdee47c245f98d0a6f203004df08c494bdf0ad17000bf562cecfaa77b16",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199g/W-gdb-199g-in2tinct-31.py",
        "block": "fixtures1",
        "sha256": "ca73de002a7ea6df0372f590d1eead763fa38702b16e21455076dcf870d2dcae"
      },
      {
        "path": "Tests/Architecture/199g/W-gdb-199g-in2tinct-31.json",
        "block": "fixtures2",
        "sha256": "de62b76626ef8c3a7214a4d696197221c87f9847e2ce499f8a3b020024aee0a2"
      },
      {
        "path": "Sources/GorAVPlaybackCore/SPSC.swift",
        "block": "frozen_dependency_0",
        "sha256": "fcba3646ae6ce3430069c5153f26e3653d9692b97f1be61c7353b4f04919415a",
        "read_only_dependency": true,
        "role": "Full original provenance for pinned declaration extraction; not an edit lease or an extra compile input."
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "cc23ce5a1f5d5c5bf2268fd3c0d5d2448ac7ffe24187f3312ccbab86da9fbc95",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL UTF8 note bound includes suffix",
      "FAIL invalid origin cannot back success",
      ""
    ]
  },
  "classification": "LIVE-CALLER BOUND: ShellFrameSource.swift lines614/655 constructs TimingLedger. Exact ledger enums/event/class and RTEvent DTO compile. GenerationFence and C atomic sections are excluded. Native audio path NOT_RUN."
}
```

```swift id=source1
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
    /// M1: typed pause receipts (additive). Count/duration reconcile 1:1
    /// with PumpStats.pauses/pausedWallSeconds - never silent.
    case pauseEntered, pauseResumed
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
    /// r9 timed-close root fix: WHO closed is typed separately from the
    /// fact that the close-intent delegate path ran. A genuine user close
    /// stays userClose; the timed-close probe is a PROGRAMMATIC actor - its
    /// terminal is a typed cancelled teardown, never a user attribution
    /// (kit v2 timedCloseProbe: endReason=cancelled with
    /// windowClosedByUser=1; the r8 Mac run 2026-10-31 stamped userClose).
    public enum CloseActor: String, Sendable, Equatable {
        case none, user, probe
    }
    public static func from(audioTerminal t: AudioTerminalKind, closeIntent: Bool) -> EndReason {
        from(audioTerminal: t, closeActor: closeIntent ? .user : .none)
    }
    public static func from(audioTerminal t: AudioTerminalKind, closeActor: CloseActor) -> EndReason {
        switch t {
        case .endOfStream: return .endOfStream
        case .failed: return .decodeFailed
        case .sourceEnded: return .sourceEnded
        case .stoppedEarly:
            switch closeActor {
            case .none: return .stoppedEarly
            case .user: return .userClose
            case .probe: return .cancelled
            }
        case .cancelled: return .cancelled
        }
    }
    /// r9: the video-leg terminal derivation, extracted from the Mac shell
    /// (ShellFrameSource) so the mapping is Linux-testable. Semantics are
    /// the r8 shell derivation with ONE change: a probe-initiated close
    /// derives .cancelled (typed cancelled teardown) instead of .userClose.
    /// Priority order is unchanged: close intent > pump failure > pump
    /// cancel > source end state. The .stopped/.interrupted/.running arms
    /// keep .stoppedEarly; their r8 userClose arm was unreachable (a close
    /// intent always lands in the first branch).
    public static func videoTerminal(windowClosed: Bool, closeActor: CloseActor,
                                     pumpEnd: PumpEndReason, sourceEnd: VideoSourceEnd) -> EndReason {
        if windowClosed || closeActor != .none {
            return closeActor == .probe ? .cancelled : .userClose
        }
        if case .failed = pumpEnd { return .decodeFailed }
        if pumpEnd == .cancelled { return .cancelled }
        switch sourceEnd {
        case .endOfStream: return .endOfStream
        case .decodeFailed: return .decodeFailed
        case .stopped: return .stoppedEarly
        case .interrupted: return .stoppedEarly
        case .running: return .stoppedEarly
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

/// r9: close-ACTOR stamping state machine. FIRST ACTOR WINS: the probe
/// claims the actor only when its close actually lands through the
/// delegate AND no close intent was recorded before it fired; a vetoed or
/// non-firing probe close leaves no stamp, so a later EOS/failure/user
/// teardown is never misattributed to a close that did not happen. Lives
/// in the core so the full precedence matrix is Linux-testable; the Mac
/// display sink only drives it from probeUserClose/windowShouldClose.
public struct CloseActorStamp: Sendable, Equatable {
    /// Any close intent recorded through the delegate (user or probe).
    public private(set) var closeIntent = false
    /// The FIRST close actor; .none until a close intent lands.
    public private(set) var actor: EndReason.CloseActor = .none
    private var probePending = false
    public init() {}
    /// Timed-close probe fires. Returns false (do NOT perform the probe
    /// close) when a close intent already exists - a prior user close keeps
    /// the user actor.
    public mutating func probeFire() -> Bool {
        guard !closeIntent else { return false }
        probePending = true
        return true
    }
    /// The probe's performClose returned without the delegate recording a
    /// close intent (veto / no-fire): the stamp attempt is dropped.
    public mutating func probeCloseReturned() { probePending = false }
    /// The delegate recorded a close intent. A pending probe claims the
    /// actor; otherwise the actor is the user. Later intents never restamp.
    public mutating func recordCloseIntent() {
        if actor == .none { actor = probePending ? .probe : .user }
        probePending = false
        closeIntent = true
    }
}

/// r9: scalar mirror of the Mac shell source's end state for the
/// extracted videoTerminal derivation (raw values match
/// ShellFrameSource.EndState 1:1; the shell maps by rawValue).
public enum VideoSourceEnd: String, Sendable, Equatable {
    case running, endOfStream, decodeFailed, stopped, interrupted
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



```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(ROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+('private let fenceLock = NSLock()\nprivate var fence: SeekFenceBinding?\npublic init() {}\n' if cfg['source'].endswith('ShellSeekBridge.swift') else '')+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n');inputs=[str(source)]
 else:
  inputs=[str(ROOT/cfg['source'])]+[str(ROOT/p) for p in cfg['deps']]
  if cfg['support']:
   source=td/'Support.swift';source.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(source))
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith('ArchiveLibrary.swift') else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith('ArchiveLibrary.swift'):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "Sources/GorAVPlaybackCore/TimingLedger.swift",
  "markers": [
    "public enum LedgerSegment:",
    "public enum LedgerSubsystem:",
    "public enum LedgerKind:",
    "public struct LedgerEvent:",
    "public final class TimingLedger:"
  ],
  "wrapper": "",
  "support": "public struct RTEvent: Sendable, Equatable {\n    public enum Kind: UInt8, Sendable { case underrunStart = 1, underrunEnd = 2, staleFenced = 3 }\n    /// Unit-typed payload (v4-4): underrun events carry FRAMES;\n    /// staleFenced carries BYTES. The units are part of the type.\n    public enum Payload: Sendable, Equatable { case frames(UInt64), bytes(UInt64) }\n    public let kind: Kind\n    public let generation: UInt64   // session generation AT POST TIME (per-registration context)\n    public let tEvent: Double       // event-time stamp from the injected clock\n    public let payload: Payload\n    public init(kind: Kind, generation: UInt64, tEvent: Double, payload: Payload) {\n        self.kind = kind; self.generation = generation; self.tEvent = tEvent; self.payload = payload\n    }\n}",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet ledger=TimingLedger(clock:{1})\nledger.append(session:1,generation:0,segment:.open,subsystem:.core,kind:.ledgerOrigin,note:String(repeating:\"\ud83d\ude00\",count:100))\ncheck(ledger.snapshot()[0].note.utf8.count <= TimingLedger.maxNoteUTF8,\"UTF8 note bound includes suffix\")\nlet invalid=TimingLedger(clock:{Double.nan})\ncheck(!invalid.allowsSuccess,\"invalid origin cannot back success\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL UTF8 note bound includes suffix
FAIL invalid origin cannot back success


```

```swift id=frozen_dependency_0
// L1 rework v4 (architect PART1 + v2-review + full-review):
// true single-producer/single-consumer rings on C11 atomics.
//  v4-1: atomic CELLS are C-owned AND C-typed: gorav_acell_create()
//        (malloc + atomic_init + compile-time lock-free assertion +
//        runtime atomic_is_lock_free proof, NULL = typed refusal). No
//        Swift allocator, no Swift-typed storage under an atomic access.
//  v4-2: BOTH rings use raw allocated storage (no Array, no CoW, no
//        subscript, no lock, no alloc on either hot path).
//  v4-3: a STICKY drop latch (droppedAnything) is set by ANY drop -
//        frame drop, partial-tail refusal, or event-ring overflow. A
//        per-generation reset clears it; "==1" exact-count reads are gone.
//  v4-4: event payloads are UNIT-TYPED (frames vs bytes); no frames value
//        is ever stored in a bytes field.
//  v4-5: render takes UInt32 frames (the AudioUnit unit); all byte
//        arithmetic is range-checked before conversion.
import Foundation
import GorAVCAtomics

/// Atomic UInt64 on a C-owned, C-typed cell (v4-1). The cell is created
/// by C (malloc + atomic_init + lock-free proof) and destroyed by C.
/// Failable: a NULL cell is a typed refusal, never a silent fallback.
public final class AtomicU64: @unchecked Sendable {
    /// Opaque C-owned cell (an _Atomic uint64_t on the C heap). Never nil
    /// after a successful init - the failable init is the typed refusal.
    private let cell: UnsafeMutableRawPointer
    public init?(_ initial: UInt64 = 0) {
        guard let c = gorav_acell_create(initial) else { return nil }
        cell = c
    }
    deinit { gorav_acell_destroy(cell) }
    @inline(__always) public func load() -> UInt64 { gorav_aload(cell) }
    @inline(__always) public func store(_ v: UInt64) { gorav_astore(cell, v) }
    @discardableResult @inline(__always) public func fetchAdd(_ v: UInt64) -> UInt64 { gorav_afetch_add(cell, v) }
    /// Single-word CAS: true iff the cell held `expected` and now holds
    /// `desired`. The reservation primitive (S1d atomic reserve).
    @discardableResult @inline(__always) public func compareExchange(expected: UInt64, desired: UInt64) -> Bool {
        var e = expected
        return gorav_acas(cell, &e, desired) != 0
    }
    /// Saturating read for telemetry: never traps on conversion.
    public var intValue: Int { let v = load(); return v > UInt64(Int.max) ? Int.max : Int(v) }
}

/// LANE-0 / architect 80b constraint A: callback admission. One packed
/// C-owned cell (bit 63 RETIRED + reader count). A reader (RT callback)
/// enters ONLY while not retired; after retire it touches NO payload and
/// outputs silence. The owner retires FIRST, then drains admitted readers
/// to zero BEFORE any reset/reuse/dispose. This is a LOCAL payload
/// lifetime fence - NO provider-quiescence claim.
public final class AdmissionCell: @unchecked Sendable {
    private let cell: UnsafeMutableRawPointer
    public init?() {
        guard let c = gorav_acell_create(0) else { return nil }
        cell = c
    }
    deinit { gorav_acell_destroy(cell) }
    /// RT-safe, lock-free. true = admitted (MUST exit); false = retired.
    @inline(__always) public func enter() -> Bool { gorav_admit_enter(cell) != 0 }
    @inline(__always) public func exit() { gorav_admit_exit(cell) }
    /// Retire (idempotent); returns readers still inside at retire time.
    @discardableResult public func retire() -> UInt64 { gorav_admit_retire(cell) }
    public var readers: UInt64 { gorav_admit_readers(cell) }
    public var isRetired: Bool { gorav_admit_is_retired(cell) != 0 }
}

public struct RTEvent: Sendable, Equatable {
    public enum Kind: UInt8, Sendable { case underrunStart = 1, underrunEnd = 2, staleFenced = 3 }
    /// Unit-typed payload (v4-4): underrun events carry FRAMES;
    /// staleFenced carries BYTES. The units are part of the type.
    public enum Payload: Sendable, Equatable { case frames(UInt64), bytes(UInt64) }
    public let kind: Kind
    public let generation: UInt64   // session generation AT POST TIME (per-registration context)
    public let tEvent: Double       // event-time stamp from the injected clock
    public let payload: Payload
    public init(kind: Kind, generation: UInt64, tEvent: Double, payload: Payload) {
        self.kind = kind; self.generation = generation; self.tEvent = tEvent; self.payload = payload
    }
}

/// SPSC event ring. Writer: the RT render callback. Reader: off-RT drain.
/// v4-2: slots live in a raw allocated buffer; the write index publishes
/// with a release store after the slot is fully written; the reader
/// acquire-loads. No Array, no CoW, no lock, no allocation on the hot path.
public final class SPSCEventRing: @unchecked Sendable {
    private let buf: UnsafeMutablePointer<RTEvent>
    public let capacity: Int
    private let w: AtomicU64
    private let r: AtomicU64
    /// Monotonic per-generation overflow counter (diagnostic).
    public let overflowed: AtomicU64
    /// STICKY latch (v4-3): 1 once ANY event was dropped this generation.
    public let droppedAnything: AtomicU64
    private let clock: @Sendable () -> Double
    public init?(capacity requested: Int = 256, clock: @Sendable @escaping () -> Double) {
        // v5-1: C cells FIRST - a cell refusal leaves no raw buffer behind
        // (previously the buffer was allocated before the guard: a leak).
        guard let w = AtomicU64(), let r = AtomicU64(),
              let ov = AtomicU64(), let da = AtomicU64() else { return nil }
        self.w = w; self.r = r; self.overflowed = ov; self.droppedAnything = da
        let cap = Swift.max(1, Swift.min(requested, 1 << 16)) // clamp, never trap
        self.capacity = cap
        buf = UnsafeMutablePointer<RTEvent>.allocate(capacity: cap)
        buf.initialize(repeating: RTEvent(kind: .underrunEnd, generation: 0, tEvent: 0, payload: .frames(0)), count: cap)
        self.clock = clock
    }
    deinit { buf.deinitialize(count: capacity); buf.deallocate() }
    /// RT-safe. Single writer. `generation` comes from the caller's
    /// PER-REGISTRATION context, never from shared mutable sink state.
    public func post(_ kind: RTEvent.Kind, generation: UInt64, payload: RTEvent.Payload) {
        let wi = w.load()          // own index: exact
        let ri = r.load()          // reader's index: stale-low only
        // v5-2: counter-space exhaustion is a TYPED refusal BEFORE wrap -
        // no wrapping-arithmetic claim is made anywhere in this type.
        if wi >= UInt64.max - 1 { overflowed.fetchAdd(1); droppedAnything.store(1); return }
        if wi &- ri >= UInt64(capacity) { overflowed.fetchAdd(1); droppedAnything.store(1); return }
        let t = clock()            // event time at post
        buf[Int(wi % UInt64(capacity))] = RTEvent(kind: kind, generation: generation, tEvent: t, payload: payload)
        w.store(wi &+ 1)           // release: publishes the slot above
    }
    /// OFF-RT. Single reader.
    public func drain() -> [RTEvent] {
        let ri = r.load()
        let wi = w.load()
        let n = (wi >= ri) ? (wi - ri) : 0 // defined order + saturating
        guard n > 0 else { return [] }
        var out: [RTEvent] = []
        out.reserveCapacity(Int(Swift.min(n, UInt64(capacity))))
        for i in 0..<n { out.append(buf[Int((ri &+ i) % UInt64(capacity))]) }
        r.store(wi)
        return out
    }
    /// Generation reset: owner side only, while the RT poster is proven
    /// quiescent. Clears indices, the overflow counter AND the sticky latch.
    public func resetForNewGeneration() {
        r.store(0); w.store(0); overflowed.store(0); droppedAnything.store(0)
    }
}

/// Immutable admission evidence for one STOPPED session: captured BEFORE
/// resetForNewGeneration() so the retired session's records survive the
/// reset. Live queue state and retired-session evidence are SEPARATE.
public struct PCMRingReceipt: Sendable, Equatable {
    public let generation: UInt64
    public let requestedBytes: UInt64
    public let admittedBytes: UInt64
    public let droppedBytes: UInt64       // frame-drops AND refused partial tails, byte-exact
    public let partialTailDrops: UInt64   // count of refused 1-3 byte tails (NOT frames)
    public let pushedFrames: UInt64
    public let droppedFrames: UInt64
    public let consumedFrames: UInt64
    public let underrunFrames: UInt64
    public let pushCount: UInt64
    public let maxPushFrames: UInt64
    public let maxAvailAfterPushFrames: UInt64
    public let droppedAnything: Bool      // sticky latch at snapshot time
}

/// SPSC PCM ring, frame-quantized (4-byte s16le stereo frames).
/// Writer: the decoder-side producer (off-RT). Reader: the RT render
/// callback. Raw allocated storage: no Array subscript, no CoW, no lock,
/// no allocation on either hot path.
public final class SPSCPCMRing: @unchecked Sendable {
    public static let bytesPerFrame = 4
    /// Hard capacity bound: validated at init, clamped - never a trap.
    public static let maxCapacityFrames = 1 << 22
    private let buf: UnsafeMutablePointer<UInt8>
    public let capacityFrames: UInt64
    private let w: AtomicU64 // frames written (monotonic) - PRODUCER-owned
    private let r: AtomicU64 // frames read (monotonic) - CONSUMER-owned
    public let requestedBytes: AtomicU64
    public let admittedBytes: AtomicU64
    public let droppedBytes: AtomicU64
    public let partialTailDrops: AtomicU64
    public let pushedFrames: AtomicU64
    public let droppedFrames: AtomicU64
    public let consumedFrames: AtomicU64
    public let underrunFrames: AtomicU64
    public let pushCount: AtomicU64
    public let maxPushFrames: AtomicU64
    public let maxAvailAfterPushFrames: AtomicU64
    /// STICKY latch (v4-3): 1 once ANY byte or frame was refused.
    public let droppedAnything: AtomicU64
    public init?(capacityFrames requested: Int = 1 << 18) {
        // v5-1: C cells FIRST - a cell refusal leaves no raw buffer behind.
        guard let w = AtomicU64(), let r = AtomicU64(),
              let req = AtomicU64(), let adm = AtomicU64(), let drb = AtomicU64(),
              let ptd = AtomicU64(), let pf = AtomicU64(), let df = AtomicU64(),
              let cf = AtomicU64(), let uf = AtomicU64(), let pc = AtomicU64(),
              let mp = AtomicU64(), let ma = AtomicU64(), let da = AtomicU64() else { return nil }
        self.w = w; self.r = r
        self.requestedBytes = req; self.admittedBytes = adm; self.droppedBytes = drb
        self.partialTailDrops = ptd; self.pushedFrames = pf; self.droppedFrames = df
        self.consumedFrames = cf; self.underrunFrames = uf; self.pushCount = pc
        self.maxPushFrames = mp; self.maxAvailAfterPushFrames = ma
        self.droppedAnything = da
        let cap = Swift.max(1, Swift.min(requested, SPSCPCMRing.maxCapacityFrames))
        buf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap * SPSCPCMRing.bytesPerFrame)
        buf.initialize(repeating: 0, count: cap * SPSCPCMRing.bytesPerFrame)
        self.capacityFrames = UInt64(cap)
    }
    deinit { buf.deinitialize(count: Int(capacityFrames) * SPSCPCMRing.bytesPerFrame); buf.deallocate() }
    /// Approximate LIVE occupancy for observers (hb/telemetry): loads r
    /// BEFORE w with a saturating subtract - can never underflow; may
    /// overestimate by the frames consumed between the two loads.
    public var availableFrames: UInt64 {
        let ri = r.load(); let wi = w.load()
        return wi >= ri ? wi - ri : 0
    }
    /// Producer side (OFF-RT). Whole frames only; a trailing partial frame
    /// is REFUSED and counted byte-exactly (partialTailDrops/droppedBytes),
    /// never as a 4-byte frame drop. Drop policy when full: drop-newest at
    /// frame granularity. ANY refusal sets the sticky latch.
    @discardableResult
    public func push(_ pcm: UnsafeBufferPointer<UInt8>) -> (admittedFrames: UInt64, droppedFrames: UInt64, droppedTailBytes: UInt64) {
        let reqBytes = UInt64(pcm.count)
        requestedBytes.fetchAdd(reqBytes)
        let frames = reqBytes / UInt64(SPSCPCMRing.bytesPerFrame)
        let tail = reqBytes % UInt64(SPSCPCMRing.bytesPerFrame)
        if tail > 0 {
            partialTailDrops.fetchAdd(1)
            droppedBytes.fetchAdd(tail)
            droppedAnything.store(1)
        }
        guard frames > 0 else { return (0, 0, tail) }
        // v5-3: the chunk witness records EVERY attempted push, including
        // fully rejected ones (a refused large push is still evidence of
        // what the producer asked for).
        if frames > maxPushFrames.load() { maxPushFrames.store(frames) }
        let wi = w.load()                    // own: exact
        // v5-2: refuse BEFORE the monotonic counters can wrap - typed drop,
        // sticky latch; no wrapping-arithmetic claim is made.
        if wi > UInt64.max - UInt64(capacityFrames) - 1 {
            droppedFrames.fetchAdd(frames)
            droppedBytes.fetchAdd(frames &* UInt64(SPSCPCMRing.bytesPerFrame))
            droppedAnything.store(1)
            return (0, frames, tail)
        }
        let ri = r.load()                    // consumer's: stale-low only -> free-space UNDERestimate, safe
        let used = wi >= ri ? wi - ri : 0
        let free = used < capacityFrames ? capacityFrames - used : 0
        let admit = Swift.min(frames, free)
        let drop = frames - admit
        if admit > 0 {
            var idx = Int(wi % capacityFrames) &* SPSCPCMRing.bytesPerFrame
            var src = 0
            let n = Int(admit) &* SPSCPCMRing.bytesPerFrame
            let base = pcm.baseAddress!
            while src < n {
                buf[idx] = base[src]
                idx = (idx &+ 1) == bufCount ? 0 : idx &+ 1
                src &+= 1
            }
            // Admission witness BEFORE publication: the peak occupancy
            // attributable to this push, computed with a fresh consumer
            // read - never an after-publish underestimate.
            let witness = (wi &+ admit) &- r.load()
            if witness > maxAvailAfterPushFrames.load() { maxAvailAfterPushFrames.store(witness) }
            w.store(wi &+ admit)             // release: publishes the bytes above
            pushedFrames.fetchAdd(admit)
            pushCount.fetchAdd(1)
            admittedBytes.fetchAdd(admit &* UInt64(SPSCPCMRing.bytesPerFrame))
        }
        if drop > 0 {
            droppedFrames.fetchAdd(drop)
            droppedBytes.fetchAdd(drop &* UInt64(SPSCPCMRing.bytesPerFrame))
            droppedAnything.store(1)
        }
        return (admit, drop, tail)
    }
    private var bufCount: Int { Int(capacityFrames) &* SPSCPCMRing.bytesPerFrame }
    /// Consumer side (RT). Renders `frames` frames DIRECTLY into `dst`:
    /// real frames copied, shortfall zero-filled and counted as underrun.
    /// No allocation, no lock, no Array subscript. Returns underrun frames.
    /// v4-5: frames is UInt32 (the AudioUnit unit); byte arithmetic is
    /// range-checked, no UInt64->Int narrowing.
    @discardableResult
    public func render(into dst: UnsafeMutablePointer<UInt8>, frames: UInt32) -> UInt32 {
        let want = UInt64(frames)
        let ri = r.load()                    // own: exact
        let wi = w.load()                    // producer's: acquire; may equal/exceed ri
        let avail = wi >= ri ? wi - ri : 0   // saturating: never underflows
        let real = Swift.min(avail, want)
        if real > 0 {
            var idx = Int(ri % capacityFrames) &* SPSCPCMRing.bytesPerFrame
            var i = 0
            let n = Int(real) &* SPSCPCMRing.bytesPerFrame // real <= UInt32.max frames
            while i < n {
                dst[i] = buf[idx]
                idx = (idx &+ 1) == bufCount ? 0 : idx &+ 1
                i &+= 1
            }
            r.store(ri &+ real)              // release the consumed region
            consumedFrames.fetchAdd(real)
        }
        let total = Int(frames) &* SPSCPCMRing.bytesPerFrame
        var i = Int(real) &* SPSCPCMRing.bytesPerFrame
        while i < total { dst[i] = 0; i &+= 1 }
        let under = want - real
        if under > 0 { underrunFrames.fetchAdd(under) }
        return UInt32(under)
    }
    /// Capture this session's admission evidence. Preconditions (enforced
    /// by the sink's lifecycle, not by this type): producer AND consumer
    /// BOTH quiescent (stop completed, pump joined) - then every counter is
    /// stable and the snapshot is internally consistent.
    public func snapshotReceipt(generation: UInt64) -> PCMRingReceipt {
        PCMRingReceipt(generation: generation,
                       requestedBytes: requestedBytes.load(),
                       admittedBytes: admittedBytes.load(),
                       droppedBytes: droppedBytes.load(),
                       partialTailDrops: partialTailDrops.load(),
                       pushedFrames: pushedFrames.load(),
                       droppedFrames: droppedFrames.load(),
                       consumedFrames: consumedFrames.load(),
                       underrunFrames: underrunFrames.load(),
                       pushCount: pushCount.load(),
                       maxPushFrames: maxPushFrames.load(),
                       maxAvailAfterPushFrames: maxAvailAfterPushFrames.load(),
                       droppedAnything: droppedAnything.load() != 0)
    }
    /// Generation reset: called by the sink ONLY with BOTH writer and
    /// reader proven quiescent (producer task joined AND AudioUnit
    /// stop+uninit succeeded). The receipt MUST be snapshotted first.
    public func resetForNewGeneration() {
        r.store(0); w.store(0)
        requestedBytes.store(0); admittedBytes.store(0); droppedBytes.store(0)
        partialTailDrops.store(0)
        pushedFrames.store(0); droppedFrames.store(0)
        consumedFrames.store(0); underrunFrames.store(0)
        pushCount.store(0); maxPushFrames.store(0); maxAvailAfterPushFrames.store(0)
        droppedAnything.store(0)
    }
}

```

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Read-only caller bindings independently checked at cf3: ShellFrameSource ledger/bridge; MetalPresenter cue consumer; FFmpegSoftwareDecoder demux policy/lease table. B32 reduced wrapper/provider double and B31/B34 declaration extraction only, no full module claim. B33-35 malformed ingress hardening, not observed runtime incidents. Single production path plus own test, no adoption or runtime closure.
