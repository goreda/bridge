// L1 timing/lifecycle deterministic model tests (architect delta 2026-10-25
// conditions 1,2,4,5,6 + negative mutants). Pure Swift over GorAVPlaybackCore
// with injected deterministic clocks: runs off-Mac (Linux swift 6.1.2) and on
// any Mac/CI runner. Every scenario asserts; any failure prints FAIL and the
// process exits non-zero. No wall-clock, no randomness, no I/O.
import Foundation
import GorAVPlaybackCore

final class FakeClock: PlaybackClock, @unchecked Sendable {
    var t = 0.0
    func nowSeconds() -> Double { t }
}
final class FakeSource: FrameSource, @unchecked Sendable {
    var frames: [SourceFrame]
    var i = 0
    init(_ frames: [SourceFrame]) { self.frames = frames }
    func nextEvent() async -> SourceEvent {
        guard i < frames.count else { return .ended(.sourceEnded) }
        defer { i += 1 }
        return .frame(frames[i])
    }
}
final class FakeSink: FrameSink, @unchecked Sendable {
    var shown: [String] = []
    var acceptShows = true
    func show(_ frame: SourceFrame) async -> Bool {
        if acceptShows { shown.append(frame.digest) }
        return acceptShows
    }
    // Explicit TEST-FAKE ticketed conformance (no protocol bypass
    // default - verdict S5 rev3).
    func show(_ frame: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool {
        await show(frame)
    }
}

var failures = 0
func check(_ cond: Bool, _ name: String, _ detail: String = "") {
    if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name) \(detail)") }
}

@main
struct TimingLedgerTests {
    static func main() async {
        // T1: full lifecycle ordering on one origin (cond. 2).
        do {
            let fc = FakeClock()
            let ledger = TimingLedger(capacity: 64, clock: { fc.t })
            ledger.append(session: 1, generation: 1, segment: .open, subsystem: .core, kind: .ledgerOrigin)
            fc.t += 0.1; ledger.append(session: 2, generation: 1, segment: .open, subsystem: .audio, kind: .audioStartAccepted)
            fc.t += 0.1; ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .videoPumpStart)
            fc.t += 1.0; ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .frameShown, pts: 0.0)
            fc.t += 9.0; ledger.append(session: 2, generation: 1, segment: .pump, subsystem: .audio, kind: .terminal, note: "endOfStream")
            fc.t += 0.5; ledger.append(session: 2, generation: 1, segment: .drain, subsystem: .audio, kind: .drainEnd, bytes: 0)
            fc.t += 0.1; ledger.append(session: 2, generation: 1, segment: .teardown, subsystem: .audio, kind: .teardownComplete)
            let evs = ledger.snapshot()
            check(evs.map { $0.kind } == [.ledgerOrigin, .audioStartAccepted, .videoPumpStart, .frameShown, .terminal, .drainEnd, .teardownComplete], "T1 lifecycle order")
            check(evs.map { $0.seq } == Array(1...7), "T1 seq monotonic")
            var mono = true; for i in 1..<evs.count { if evs[i].tRel < evs[i-1].tRel { mono = false } }
            check(mono, "T1 tRel non-decreasing")
            check(ledger.allowsSuccess, "T1 allowsSuccess")
        }
        // T2: start-starve - silence is never consumed content (cond. 6 start-starve).
        do {
            let ring = PCMRingBuffer(capacity: 16)
            let r1 = ring.renderCounted(8)
            check(r1.underrun == 8 && ring.kitConsumedBytes == 0, "T2 start-starve silence not consumed")
            ring.push([1, 2, 3, 4])
            let r2 = ring.renderCounted(8)
            check(r2.underrun == 4 && ring.kitConsumedBytes == 4 && Array(r2.out[0..<4]) == [1, 2, 3, 4] && Array(r2.out[4..<8]) == [0, 0, 0, 0], "T2 real bytes before silence")
        }
        // T3: mid-starve counters.
        do {
            let ring = PCMRingBuffer(capacity: 16)
            ring.push([9, 9, 9, 9, 9, 9, 9, 9])
            let a = ring.renderCounted(8)
            let b = ring.renderCounted(4)
            check(a.underrun == 0 && b.underrun == 4 && ring.kitConsumedBytes == 8 && ring.underrunBytes == 4, "T3 mid-starve counters")
        }
        // T4: overrun drop-newest keeps ORDERED CONTENT IDENTITY, not just
        // byte balance (architect cond: byte-conserving mutant must fail).
        do {
            let ring = PCMRingBuffer(capacity: 16)
            let o1 = ring.pushCounted(Array(0..<16))
            check(o1.admitted == 16 && o1.dropped == 0, "T4 fill admitted")
            let o2 = ring.pushCounted([100, 101, 102, 103])
            check(o2.admitted == 0 && o2.dropped == 4 && ring.overrunDrops == 4, "T4 overflow dropped")
            let out = ring.renderCounted(16)
            check(Array(out.out) == Array(0..<16), "T4 retained content identity is the oldest ordered bytes")
        }
        // T5: watermark bound is derived from RECORDED maxima (cond. 1).
        do {
            let ring = PCMRingBuffer(capacity: 1024)
            let watermark = 256, chunk = 100
            for _ in 0..<30 {
                if ring.available <= watermark { _ = ring.pushCounted([UInt8](repeating: 7, count: chunk)) }
                else { _ = ring.renderCounted(88) }
            }
            let ev = QueueBoundEvidence(capacity: 1024, watermark: watermark,
                                        maxChunkBytes: ring.maxPushBytes,
                                        maxAvailAfterPush: ring.maxAvailAfterPush,
                                        overrunDrops: ring.overrunDrops,
                                        pushCount: ring.pushCount)
            check(ring.maxAvailAfterPush <= watermark + chunk, "T5 recorded maxAvail within watermark+chunk", "got \(ring.maxAvailAfterPush)")
            check(ev.admissionBoundHolds && ring.overrunDrops == 0, "T5 admission bound verified from records")
            let unrecorded = QueueBoundEvidence(capacity: 1024, watermark: 256, maxChunkBytes: 0, maxAvailAfterPush: 0, overrunDrops: 0, pushCount: 0)
            check(!unrecorded.admissionBoundHolds, "T5 no bound claim without recorded maxima")
            // finding 5 mutants: overrun>0 or maxAvail beyond watermark+chunk
            // must REFUSE the bound even when records exist.
            let overran = QueueBoundEvidence(capacity: 1024, watermark: 256, maxChunkBytes: 100, maxAvailAfterPush: 300, overrunDrops: 4, pushCount: 10)
            check(!overran.admissionBoundHolds, "T5 MUTANT overrun refuses bound")
            let overshot = QueueBoundEvidence(capacity: 1024, watermark: 256, maxChunkBytes: 100, maxAvailAfterPush: 400, overrunDrops: 0, pushCount: 10)
            check(!overshot.admissionBoundHolds, "T5 MUTANT maxAvail>watermark+chunk refuses bound")
        }
        // T6: same-actor upload fence decision + close-intent ordering (cond. 3).
        do {
            check(UploadFence.mayUpload(closeIntent: false) && !UploadFence.mayUpload(closeIntent: true), "T6 fence decision")
            let ledger = TimingLedger(capacity: 8, clock: { 0.0 })
            ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .closeIntent)
            ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .closeFenceSkip, pts: 5.0)
            let kinds = ledger.snapshot().map { $0.kind }
            check(kinds == [.closeIntent, .closeFenceSkip], "T6 close intent precedes fence skip")
        }
        // T7: cancel / decode error / EOS are DISTINCT end reasons (cond. 6).
        do {
            check(EndReason.from(audioTerminal: .endOfStream, closeIntent: false) == .endOfStream, "T7 eos")
            check(EndReason.from(audioTerminal: .failed, closeIntent: false) == .decodeFailed, "T7 decodeFailed")
            check(EndReason.from(audioTerminal: .sourceEnded, closeIntent: false) == .sourceEnded, "T7 sourceEnded")
            check(EndReason.from(audioTerminal: .stoppedEarly, closeIntent: true) == .userClose, "T7 userClose distinct")
            check(EndReason.from(audioTerminal: .stoppedEarly, closeIntent: false) == .stoppedEarly, "T7 bare stoppedEarly")
            let all: Set<EndReason> = [.endOfStream, .decodeFailed, .sourceEnded, .userClose, .stoppedEarly, .cancelled]
            check(all.count == 6, "T7 six distinct end reasons")
        }
        // T8: per-generation lifecycle v3 - DOUBLE_DISPOSE,
        // STOP_BEFORE_START, START_STOP_START, TEARDOWN_BLOCKS_START and
        // FAILED_SESSION_TERMINAL mutants (v2-review finding 2).
        do {
            let lc = SessionLifecycle()
            check(lc.beginStop() == .none && lc.noOpStopCount == 1, "T8 MUTANT stop-before-start is a no-op (guard not consumed)")
            let g1 = lc.beginStart()
            check(g1 == 1, "T8 first start reserves generation 1")
            check(lc.beginStart() == nil && lc.refusedStartCount == 1, "T8 MUTANT double start refused")
            check(lc.commitStart(1), "T8 commit")
            check(lc.beginStop() == .teardownOwned(1), "T8 stop owns teardown")
            // v3: the generation stays OCCUPIED while teardown runs - a new
            // start during teardown is refused (v2 admitted it).
            check(lc.beginStart() == nil && lc.refusedStartCount == 2, "T8 MUTANT start-during-teardown refused")
            check(lc.beginStop() == .none, "T8 MUTANT double dispose refused")
            lc.finishStop(1)
            check(lc.stopCount == 1, "T8 stop counted at quiescence, not at begin")
            let g2 = lc.beginStart()
            check(g2 == 2, "T8 start-stop-start RE-ARMS with generation 2")
            lc.abortStart(2)
            check(lc.abortedStartCount == 1 && lc.beginStart() == 3, "T8 aborted start rolls back and re-arms")
            // stop racing a start: startWillTearDown, commitStart false,
            // abortStart completes the raced stop.
            check(lc.beginStop() == .startWillTearDown(3), "T8 stop-races-start is typed, touches nothing")
            check(!lc.commitStart(3), "T8 raced start commit fails")
            lc.abortStart(3)
            check(lc.stopCount == 2 && lc.current == .idle, "T8 raced stop completed by start side")
            // FAILED session is TERMINAL: never overwritten.
            _ = lc.beginStart(); _ = lc.commitStart(4)
            _ = lc.beginStop()
            lc.failStop(4)
            check(lc.beginStart() == nil && lc.refusedStartFailedCount == 1, "T8 MUTANT start on FAILED session refused")
            check(lc.beginStop() == .none, "T8 stop on FAILED is a no-op")
        }
        // T9: stale-generation fence - EARLY_FREE_CALLBACK mutant must not
        // touch session resources (cond. 4/6).
        do {
            let fence = GenerationFence()
            check(fence.checkRT(1), "T9 current generation admitted")
            fence.advance() // stop() boundary
            check(!fence.checkRT(1), "T9 MUTANT stale-generation callback fenced")
            check(fence.fencedCount == 1, "T9 stale attempt recorded")
            check(fence.checkRT(2), "T9 new generation admitted")
        }
        // T10: bounded ledger overflow refuses success (cond. 5).
        do {
            let ledger = TimingLedger(capacity: 4, clock: { 0.0 })
            for _ in 0..<10 { ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .core, kind: .audioPush) }
            check(ledger.count == 4 && ledger.overflowed && ledger.droppedEventCount == 6 && !ledger.allowsSuccess, "T10 overflow refuses success")
        }
        // T11: SPSC event ring fold keeps EVENT-TIME stamps (finding 4) and
        // the overflow latch refuses success (cond. 5).
        do {
            let ledger = TimingLedger(capacity: 16, clock: { 0.0 })
            var t = 50.0
            final class TB: @unchecked Sendable { var v = 50.0 }
            let tb = TB(); tb.v = t
            guard let rt = SPSCEventRing(capacity: 2, clock: { tb.v }) else { check(false, "T11 init"); return }
            rt.post(.underrunStart, generation: 7, payload: .frames(512))
            tb.v = 55.0
            rt.post(.underrunEnd, generation: 7, payload: .frames(0))
            let drained = rt.drain()
            ledger.fold(rt: drained, session: 2, segment: .pump)
            let evs = ledger.snapshot()
            check(evs.map { $0.kind } == [.underrunStart, .underrunEnd], "T11 transitions folded")
            check(evs[0].tAbs == 50.0 && evs[1].tAbs == 55.0, "T11 EVENT-TIME stamps preserved, not drain time", "\(evs.map { $0.tAbs })")
            check(evs[0].generation == 7, "T11 post-time generation preserved")
            check(ledger.allowsSuccess, "T11 clean fold keeps success")
            guard let rt2 = SPSCEventRing(capacity: 1, clock: { 0.0 }) else { check(false, "T11 init2"); return }
            rt2.post(.staleFenced, generation: 1, payload: .bytes(0))
            rt2.post(.staleFenced, generation: 1, payload: .bytes(0)) // overflow latch
            check(rt2.overflowed.load() == 1, "T11 overflow latch set")
            ledger.fold(rt: rt2.drain(), session: 2, segment: .pump)
            if rt2.overflowed.load() == 1 { ledger.foldRTOverflow() }
            check(!ledger.allowsSuccess, "T11 RT overflow folds into ledger and refuses success")
            _ = t
        }
        // T12: pump PTS classification - forward gap recorded as observation,
        // backward and non-finite as typed drops; order of shown digests
        // preserved (cond. 2 + ordered content identity).
        do {
            let ledger = TimingLedger(capacity: 256, clock: { 0.0 })
            let clock = FakeClock()
            func fr(_ pts: Double, _ d: String) -> SourceFrame { SourceFrame(ptsSeconds: pts, durationSeconds: 0.04, digest: d) }
            let source = FakeSource([fr(0.00, "a"), fr(0.04, "b"), fr(0.20, "c"), fr(0.05, "X"), fr(0.24, "d")])
            let sink = FakeSink()
            let pump = FramePump(source: source, sink: sink, clock: clock,
                                 ledger: ledger, ledgerSession: 1, ledgerGeneration: 1,
                                 onWait: { d in clock.t += d; return true })
            let stats = await pump.run()
            check(stats.shown == 4 && stats.dropped == 0, "T12 shown count", "\(stats.shown)/\(stats.dropped)")
            check(sink.shown == ["a", "b", "c", "d"], "T12 shown order identity", "\(sink.shown)")
            // backward: feed one out-of-order frame in a second run segment
            let ledger2 = TimingLedger(capacity: 64, clock: { 0.0 })
            let clock2 = FakeClock()
            let source2 = FakeSource([fr(0.00, "a"), fr(0.04, "b"), fr(0.02, "BACK"), fr(0.08, "c")])
            let sink2 = FakeSink()
            let pump2 = FramePump(source: source2, sink: sink2, clock: clock2,
                                  ledger: ledger2, ledgerSession: 1, ledgerGeneration: 1,
                                  onWait: { d in clock2.t += d; return true })
            let stats2 = await pump2.run()
            check(stats2.outOfOrderDrops == 1 && sink2.shown == ["a", "b", "c"], "T12 backward typed drop", "\(stats2.outOfOrderDrops)")
            let kinds = ledger.snapshot().map { $0.kind }
            check(kinds.filter { $0 == .ptsGapForward }.count == 1, "T12 forward gap classified once", "\(kinds)")
            check(kinds.filter { $0 == .frameShown }.count == 4, "T12 frameShown events")
            let kinds2 = ledger2.snapshot().map { $0.kind }
            check(kinds2.contains(.ptsBackwardDrop), "T12 backward event recorded")
            // non-finite
            let ledger3 = TimingLedger(capacity: 64, clock: { 0.0 })
            let clock3 = FakeClock()
            let source3 = FakeSource([fr(Double.nan, "NAN"), fr(0.0, "ok")])
            let sink3 = FakeSink()
            let pump3 = FramePump(source: source3, sink: sink3, clock: clock3,
                                  ledger: ledger3, ledgerSession: 1, ledgerGeneration: 1,
                                  onWait: { d in clock3.t += d; return true })
            let stats3 = await pump3.run()
            check(stats3.nonFiniteDrops == 1 && sink3.shown == ["ok"], "T12 non-finite typed drop")
            check(ledger3.snapshot().map { $0.kind }.contains(.ptsNonFiniteDrop), "T12 non-finite event")
        }
        // T20: v4 missingSequence - ORDERED, PER-SESSION/GENERATION
        // completeness: foreign sessions and out-of-order kinds never count.
        do {
            let ledger = TimingLedger(capacity: 64, clock: { 0.0 })
            ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .videoPumpEnd) // WRONG order (end before start), s1
            ledger.append(session: 2, generation: 9, segment: .open, subsystem: .audio, kind: .audioStartAccepted) // foreign session
            ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .videoPumpStart)
            check(ledger.missingSequence(session: 1, generation: 1, required: [.videoPumpStart, .videoPumpEnd]).isEmpty == false,
                  "T20 out-of-order sequence is INCOMPLETE")
            check(ledger.missingSequence(session: 2, generation: 9, required: [.audioStartAccepted]).isEmpty,
                  "T20 own session ordered single kind complete")
            check(!ledger.missingSequence(session: 1, generation: 1, required: [.audioStartAccepted]).isEmpty,
                  "T20 foreign-session kind never counts")
        }
        // T21: v4 export order - PUBLICATION (seq), late RT fold with an
        // OLDER event-time stamp does NOT regress the emission order.
        do {
            let ledger = TimingLedger(capacity: 64, clock: { 100.0 })
            ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .videoPumpStart)
            let ev = RTEvent(kind: .underrunStart, generation: 3, tEvent: 1.0, payload: .frames(7)) // older stamp
            ledger.fold(rt: [ev], session: 2, segment: .pump)
            let lines = ledger.jsonLines().split(separator: "\n").map(String.init)
            let k1 = ((try? JSONSerialization.jsonObject(with: Data(lines[1].utf8))) as? [String: Any])?["kind"] as? String
            let k2 = ((try? JSONSerialization.jsonObject(with: Data(lines[2].utf8))) as? [String: Any])?["kind"] as? String
            check(k1 == "videoPumpStart" && k2 == "underrunStart",
                  "T21 publication order kept despite older folded stamp", "\(k1 ?? "?")/\(k2 ?? "?")")
            let e2 = (try? JSONSerialization.jsonObject(with: Data(lines[2].utf8))) as? [String: Any]
            check((e2?["tAbs"] as? Double) == 1.0 && (e2?["bytes"] as? Int) == 28 && (e2?["note"] as? String) == "rtPost unit=frames4",
                  "T21 folded event keeps event-time + EXACT frame->byte conversion", "\(String(describing: e2))")
        }
        // T22: v4 sticky latch - drops at count 1 AND >=2 both latched;
        // reset clears it.
        do {
            let ledger2 = TimingLedger(capacity: 64, clock: { 0.0 })
            guard let rt3 = SPSCEventRing(capacity: 1, clock: { 0.0 }) else { check(false, "T22 init"); return }
            rt3.post(.staleFenced, generation: 1, payload: .bytes(1))
            rt3.post(.staleFenced, generation: 1, payload: .bytes(1))
            rt3.post(.staleFenced, generation: 1, payload: .bytes(1)) // TWO overflows
            check(rt3.droppedAnything.load() == 1 && rt3.overflowed.load() == 2, "T22 sticky latch set with counter 2")
            rt3.resetForNewGeneration()
            check(rt3.droppedAnything.load() == 0 && rt3.overflowed.load() == 0, "T22 reset clears latch+counter")
            _ = ledger2
        }
        // T13: JSONL export v2 (finding 8) - versioned header, REAL JSON
        // parse of every line (no manual interpolation), byte bound with a
        // truncation marker, bounded notes, non-finite stamp refusal.
        do {
            let ledger = TimingLedger(capacity: 8, clock: { 1.5 }, runID: "t13", cwd: "/x")
            ledger.append(session: 1, generation: 2, segment: .pump, subsystem: .video, kind: .frameShown, pts: 0.04, bytes: 3, note: "quote\"and\\backslash")
            let lines = ledger.jsonLines().split(separator: "\n").map(String.init)
            check(lines.count == 2, "T13 header + one event")
            let h = (try? JSONSerialization.jsonObject(with: Data(lines[0].utf8))) as? [String: Any]
            check(h?["schema"] as? String == "gorav.timing-ledger/4" && h?["order"] as? String == "publication" && h?["runID"] as? String == "t13" && h?["cwd"] as? String == "/x", "T13 header", lines[0])
            let e = (try? JSONSerialization.jsonObject(with: Data(lines[1].utf8))) as? [String: Any]
            check(e?["kind"] as? String == "frameShown" && (e?["pts"] as? Double) == 0.04 && (e?["tAbs"] as? Double) == 1.5, "T13 event parses as real JSON", lines[1])
            check(e?["note"] as? String == "quote\"and\\backslash", "T13 escaping round-trips through JSONEncoder")
            // byte bound: tiny budget truncates with a marker last line.
            let l2 = TimingLedger(capacity: 64, clock: { 0.0 })
            for i in 0..<30 { l2.append(session: 1, generation: 1, segment: .pump, subsystem: .core, kind: .audioPush, bytes: i) }
            let out = l2.jsonLines(maxBytes: 400)
            let ls = out.split(separator: "\n").map(String.init)
            let last = (try? JSONSerialization.jsonObject(with: Data(ls.last!.utf8))) as? [String: Any]
            check(last?["type"] as? String == "truncated" && (last?["omittedEvents"] as? Int) ?? 0 > 0 && (last?["writtenEvents"] as? Int) != nil, "T13 truncation marker receipt is last line", ls.last ?? "")
            // L9 W2 (architect-reviewed): an export-formatting budget
            // truncates PRESENTATION only - it marks lastExportTruncated
            // but NEVER poisons the ingestion verdict.
            check(l2.lastExportTruncated && l2.allowsSuccess, "T13 truncated export marks truncation, verdict unpoisoned")
            // Ingestion-side capacity loss still refuses success (distinct path).
            let l2b = TimingLedger(capacity: 3, clock: { 0.0 })
            for i in 0..<6 { l2b.append(session: 1, generation: 1, segment: .pump, subsystem: .core, kind: .audioPush, bytes: i) }
            check(!l2b.allowsSuccess && l2b.overflowed, "T13 ingestion capacity overflow still refuses success")
            // note bound
            let l3 = TimingLedger(capacity: 4, clock: { 0.0 })
            l3.append(session: 1, generation: 1, segment: .pump, subsystem: .core, kind: .terminal, note: String(repeating: "z", count: 1000))
            check(l3.snapshot()[0].note.utf8.count == TimingLedger.maxNoteUTF8 + 1 && l3.truncatedNoteCount == 1, "T13 note byte-bound")
            // non-finite stamp refuses success
            let l4 = TimingLedger(capacity: 4, clock: { Double.nan })
            l4.append(session: 1, generation: 1, segment: .pump, subsystem: .core, kind: .audioPush)
            check(!l4.allowsSuccess && l4.invalidStampCount == 1, "T13 non-finite stamp refuses success")
        }
        // T14: a fenced (refused) show is NOT logged frameShown and NOT
        // counted as shown (finding 4: "frameShown even when closed" mutant).
        do {
            let ledger = TimingLedger(capacity: 32, clock: { 0.0 })
            let src = FakeSource([SourceFrame(ptsSeconds: 0.0, durationSeconds: 0.04, digest: "x")])
            let sink = FakeSink(); sink.acceptShows = false // window closed / fenced
            let pump = FramePump(source: src, sink: sink, clock: FakeClock(),
                                 ledger: ledger, ledgerSession: 1, ledgerGeneration: 1,
                                 onWait: { _ in true })
            let stats = await pump.run()
            check(stats.shown == 0 && stats.fencedShows == 1, "T14 refused show not counted shown")
            check(!ledger.snapshot().map { $0.kind }.contains(.frameShown), "T14 MUTANT frameShown on refused show absent")
        }
        print(failures == 0 ? "ALL MODEL TESTS PASS" : "MODEL TEST FAILURES: \(failures)")
        SPSC.run()
        Foundation.exit((failures == 0 && SPSC.failures == 0) ? 0 : 1)
    }
}
