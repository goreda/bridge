// M4 seek-composition integration tests (Linux): drive the ACTUAL extracted
// BoundAudioPump.run + SeekOrchestration.coordinateSeekAudio with the REAL
// audio provider (73d2ea6c) and REAL fixtures. Covers: initial NIL
// correlation open (r3 bug class), video-refused sink-intact ordering,
// video-committed + ringResetRefused -> typed mute (r4b split-commit fix),
// video-committed + real provider seek resume, and the +100ms fixture's
// shared-anchor first-push delay vs canonical.
import Foundation
import GorAVCore
import GorAVPlaybackCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter
import GorAVSeekComposition

var failures = 0
func expect(_ c: Bool, _ m: String) { if !c { failures += 1; FileHandle.standardError.write(Data(("FAIL \(m)\n").utf8)) } }
func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }

final class WallClock: PlaybackClock, @unchecked Sendable {
    let t0 = Date()
    func nowSeconds() -> Double { Date().timeIntervalSince(t0) }
}
final class Counter: @unchecked Sendable { var n = 0 }
final class RevBox: @unchecked Sendable { var rev: UInt64? = nil }

final class FakeSink: AudioSinkControlling, @unchecked Sendable {
    private let l = NSLock()
    let clock: WallClock
    var pushedBytes = 0
    var firstPushWall: Double? = nil
    var resetCalls = 0
    var resetResult: UInt64? = 7
    var drainRate: Double = 88200 * 2
    var onReset: (() async -> Void)? = nil
    var fenceGen: UInt64 = 1
    init(_ c: WallClock) { clock = c }
    var available: Int { l.lock(); defer { l.unlock() }; return max(0, pushedBytes - Int(clock.nowSeconds() * drainRate)) }  // virtual RT drain
    var currentFenceGeneration: UInt64 { l.lock(); defer { l.unlock() }; return fenceGen }
    func push(_ pcm: [UInt8]) { l.lock(); if firstPushWall == nil { firstPushWall = clock.nowSeconds() }; pushedBytes += pcm.count; l.unlock() }
    func resetRingForSeek() async -> UInt64? {
        l.lock(); resetCalls += 1; let r = resetResult; let hook = onReset; l.unlock()
        if let hook { _ = await hook() }
        return r
    }
    func stats() -> (Int, Double?, Int) { l.lock(); defer { l.unlock() }; return (pushedBytes, firstPushWall, resetCalls) }
}
final class ResumeLog: @unchecked Sendable {
    private let l = NSLock()
    var resumes: [(AudioSourceBinding, UInt64?, MediaWallAnchor?)] = []
    var closes = 0
    func resume(_ b: AudioSourceBinding, _ c: UInt64?, _ a: MediaWallAnchor?) { l.lock(); resumes.append((b, c, a)); l.unlock() }
    func close() { l.lock(); closes += 1; l.unlock() }
    func snapshot() -> ([(AudioSourceBinding, UInt64?, MediaWallAnchor?)], Int) { l.lock(); defer { l.unlock() }; return (resumes, closes) }
}

@main struct SeekCompositionTests {
    static func openReal(_ path: String) async -> (FFmpegSoftwareAudioDecoder, SessionID, AudioSeekDescriptor)? {
        guard let session = PlaybackIdentityAuthority.shared.issue() else { log("FAIL session issue"); return nil }
        let dec = FFmpegSoftwareAudioDecoder()
        do {
            try dec.pinLocalRoots([URL(fileURLWithPath: path).deletingLastPathComponent().path])
            try await dec.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: session)
        } catch { log("FAIL open \(error)"); return nil }
        guard let d = await dec.seekDescriptor(session: session) else { log("FAIL descriptor"); return nil }
        return (dec, session, d)
    }

    static func main() async {
        let canonical = ProcessInfo.processInfo.environment["GORAV_CANONICAL"] ?? "/tmp/g465kit/clip-bbb-10s.mov"
        let offset = ProcessInfo.processInfo.environment["GORAV_OFFSET100"] ?? "/tmp/handoff/fixtures/clip-bbb-10s-audio-offset100ms.mov"
        let zero = try! RationalTime(value: 0, timescale: 1)

        // (a) ACTUAL pump, NIL-correlation open leg (r3 bug class): must push
        // with zero fenced; correlation 0 is the negative control (all fenced).
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock)
            let out = await BoundAudioPump.run(decoder: dec, session: ses, binding: d.binding, correlation: nil, sink: sink)
            let (pushed, _, _) = sink.stats()
            expect(out.terminal == .endOfStream, "nil-open: terminal endOfStream (got \(out.terminal))")
            expect(pushed > 0 && out.fencedStale == 0, "nil-open: pushed=\(pushed)>0 fencedStale=0 (got \(out.fencedStale))")
            _ = await dec.close(session: ses)
            log("nil-open: pushed=\(pushed) fenced=\(out.fencedStale) terminal=\(out.terminal)")
        }
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock)
            let out = await BoundAudioPump.run(decoder: dec, session: ses, binding: d.binding, correlation: 0, sink: sink)
            let (pushed, _, _) = sink.stats()
            expect(pushed == 0 && out.fencedStale > 0, "negative control: correlation 0 fences all open envelopes (pushed=\(pushed) fenced=\(out.fencedStale))")
            _ = await dec.close(session: ses)
            log("negative-control: pushed=\(pushed) fenced=\(out.fencedStale)")
        }

        // (b) ORDERING, video refused: no ring reset, no provider seek, resume same.
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock); let rlog = ResumeLog()
            let revBefore = d.binding.revision
            let out = await SeekOrchestration.coordinateSeekAudio(
                audioBinding: d.binding, audioCorrelation: nil,
                videoSeek: { false }, commitAnchor: { nil },
                decoder: dec, session: ses, sink: sink,
                target: zero, targetSeconds: 0, correlation: 1,
                stopAndJoinProducer: { }, resumeProducer: { b, c, a in rlog.resume(b, c, a) },
                closeAudio: { rlog.close() })
            let (resumes, closes) = rlog.snapshot()
            let revAfter = await dec.seekDescriptor(session: ses)?.binding.revision
            expect(out == .videoRefusedResumed, "video-refused outcome (got \(out))")
            expect(sink.stats().2 == 0, "video-refused: ring reset NOT called (sink state intact)")
            expect(closes == 0 && resumes.count == 1, "video-refused: resume same, no close")
            expect(resumes.first?.0 == d.binding && resumes.first?.1 == nil && resumes.first?.2 == nil, "video-refused: resumed SAME binding+correlation, no anchor")
            expect(revAfter == revBefore, "video-refused: provider cursor untouched (rev \(revAfter ?? 99))")
            _ = await dec.close(session: ses)
            log("video-refused: outcome=\(out) resets=0 rev unchanged")
        }

        // (c) ORDERING, video committed + ring reset REFUSED: typed mute, no resume, no provider seek.
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock); sink.resetResult = nil
            let rlog = ResumeLog()
            let out = await SeekOrchestration.coordinateSeekAudio(
                audioBinding: d.binding, audioCorrelation: nil,
                videoSeek: { true }, commitAnchor: { nil },
                decoder: dec, session: ses, sink: sink,
                target: zero, targetSeconds: 0, correlation: 1,
                stopAndJoinProducer: { }, resumeProducer: { b, c, a in rlog.resume(b, c, a) },
                closeAudio: { rlog.close() })
            let (resumes, closes) = rlog.snapshot()
            expect(out == .ringResetRefusedMuted, "committed+resetRefused outcome (got \(out))")
            expect(sink.stats().2 == 1, "reset attempted once")
            expect(closes == 1 && resumes.isEmpty, "committed+resetRefused: audio CLOSED (typed mute), NO old-binding resume (A/V split class)")
            _ = await dec.close(session: ses)
            log("reset-refused-after-commit: outcome=\(out) closes=\(closes) resumes=\(resumes.count)")
        }

        // (c2) ORDERING, video committed + reset OK + REAL provider seek: resume new binding+correlation+anchor.
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock)
            let rlog = ResumeLog()
            let anchor = MediaWallAnchor(mediaSeconds: 0.0, wallSeconds: 0.0)
            let out = await SeekOrchestration.coordinateSeekAudio(
                audioBinding: d.binding, audioCorrelation: nil,
                videoSeek: { true }, commitAnchor: { anchor },
                decoder: dec, session: ses, sink: sink,
                target: zero, targetSeconds: 0, correlation: 1,
                stopAndJoinProducer: { }, resumeProducer: { b, c, a in rlog.resume(b, c, a) },
                closeAudio: { rlog.close() })
            let (resumes, closes) = rlog.snapshot()
            expect(out == .nativeReady, "committed+resetOK outcome (got \(out))")
            expect(resumes.count == 1 && resumes.first?.0.revision == d.binding.revision + 1 && resumes.first?.1 == 1 && resumes.first?.2 == anchor,
                   "committed+resetOK: resumed NEW binding (rev+1), correlation 1, actual anchor")
            expect(closes == 0, "committed+resetOK: no close")
            _ = await dec.close(session: ses)
            log("committed+resetOK: outcome=\(out) resume rev+1 corr=1 anchored")
        }

        // (d) SHARED ANCHOR with REAL fixtures: +100ms edit-list first push
        // delayed ~100ms vs canonical ~0, same anchor, ACTUAL pump after a
        // REAL provider seek to zero.
        for (path, name, minWait, maxWait) in [(canonical, "canonical", 0.0, 0.09), (offset, "offset100ms", 0.09, 4.0)] {
            if let (dec, ses, d) = await openReal(path) {
                let clock = WallClock(); let sink = FakeSink(clock)
                let ar = await dec.seek(binding: d.binding, videoRelativeTarget: zero, correlation: 1)
                guard case .nativeReady(let nb, let corr, _, _) = ar else { expect(false, "\(name): real seek nativeReady (got \(ar))"); continue }
                let out = await BoundAudioPump.run(decoder: dec, session: ses, binding: nb, correlation: corr,
                                                   sink: sink, clock: clock,
                                                   sharedAnchor: MediaWallAnchor(mediaSeconds: 0.0, wallSeconds: 0.0))
                let (pushed, firstWall, _) = sink.stats()
                expect(out.terminal == .endOfStream && pushed > 0, "\(name): pump ran to EOS pushed=\(pushed)")
                if let w = firstWall {
                    expect(w >= minWait && w < maxWait, "\(name): first push wall \(w)s in [\(minWait), \(maxWait)) - shared anchor offset")
                } else { expect(false, "\(name): first push wall recorded") }
                _ = await dec.close(session: ses)
                log("\(name): firstPushWall=\(firstWall ?? -1)s pushed=\(pushed)")
            }
        }

        // (e) CANCEL during the anchor wait (offset fixture, far anchor):
        // shouldStop flips -> typed stoppedEarly, ZERO pushes, no early PCM.
        if let (dec, ses, d) = await openReal(offset) {
            let clock = WallClock(); let sink = FakeSink(clock)
            let ar = await dec.seek(binding: d.binding, videoRelativeTarget: zero, correlation: 1)
            guard case .nativeReady(let nb, let corr, _, _) = ar else { expect(false, "cancel-wait: seek"); fatalError() }
            let calls = Counter()
            let out = await BoundAudioPump.run(decoder: dec, session: ses, binding: nb, correlation: corr,
                                               sink: sink, clock: clock,
                                               sharedAnchor: MediaWallAnchor(mediaSeconds: 0.0, wallSeconds: 30.0),
                                               shouldStop: { calls.n += 1; return calls.n > 3 })
            let (pushed, firstWall, _) = sink.stats()
            expect(out.terminal == .stoppedEarly, "cancel-wait: stoppedEarly (got \(out.terminal))")
            expect(pushed == 0 && firstWall == nil, "cancel-wait: zero pushes, no early PCM (pushed=\(pushed))")
            _ = await dec.close(session: ses)
            log("cancel-wait: terminal=\(out.terminal) pushed=\(pushed)")
        }

        // (f) CANCEL during high-water pacing (non-draining sink): typed
        // stoppedEarly, partial push, no hang.
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock); sink.drainRate = 0
            let calls = Counter()
            let out = await BoundAudioPump.run(decoder: dec, session: ses, binding: d.binding, correlation: nil,
                                               sink: sink,
                                               shouldStop: { calls.n += 1; return calls.n > 200 })
            let (pushed, _, _) = sink.stats()
            expect(out.terminal == .stoppedEarly, "cancel-highwater: stoppedEarly (got \(out.terminal))")
            expect(pushed >= 88200 && pushed < 1764000, "cancel-highwater: partial push bounded by watermark (\(pushed))")
            _ = await dec.close(session: ses)
            log("cancel-highwater: terminal=\(out.terminal) pushed=\(pushed)")
        }

        // (g) ORDER within commit: ring reset must run BEFORE the provider
        // seek - the sink records the provider revision AT reset time.
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock)
            let revBox = RevBox()
            sink.onReset = { revBox.rev = await dec.seekDescriptor(session: ses)?.binding.revision }
            let rlog = ResumeLog()
            let out = await SeekOrchestration.coordinateSeekAudio(
                audioBinding: d.binding, audioCorrelation: nil,
                videoSeek: { true }, commitAnchor: { nil },
                decoder: dec, session: ses, sink: sink,
                target: zero, targetSeconds: 0, correlation: 1,
                stopAndJoinProducer: { }, resumeProducer: { b, c, a in rlog.resume(b, c, a) },
                closeAudio: { rlog.close() })
            expect(out == .nativeReady, "order: nativeReady (got \(out))")
            expect(revBox.rev == d.binding.revision, "order: provider cursor UNTOUCHED at ring reset time (rev \(revBox.rev ?? 99) vs \(d.binding.revision))")
            _ = await dec.close(session: ses)
            log("order: revAtReset=\(revBox.rev ?? 99) (pre-seek), then nativeReady")
        }

        // (h) REPEATED seek: two real rounds, generations/correlations advance,
        // revisions +1/+2, second round resumes the NEW binding.
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock); sink.resetResult = 2
            let rlog = ResumeLog()
            var binding = d.binding
            var corr: UInt64? = nil
            for round: UInt64 in [1, 2] {
                let out = await SeekOrchestration.coordinateSeekAudio(
                    audioBinding: binding, audioCorrelation: corr,
                    videoSeek: { true }, commitAnchor: { MediaWallAnchor(mediaSeconds: 0, wallSeconds: 0) },
                    decoder: dec, session: ses, sink: sink,
                    target: zero, targetSeconds: 0, correlation: round,
                    stopAndJoinProducer: { }, resumeProducer: { b, c, a in rlog.resume(b, c, a) },
                    closeAudio: { rlog.close() })
                expect(out == .nativeReady, "repeated round \(round): nativeReady (got \(out))")
                let (resumes, _) = rlog.snapshot()
                if let last = resumes.last {
                    binding = last.0; corr = last.1
                    expect(last.0.revision == d.binding.revision + round, "repeated round \(round): revision +\(round)")
                    expect(last.1 == round, "repeated round \(round): correlation \(round)")
                }
            }
            expect(sink.stats().2 == 2, "repeated: one ring reset per committed seek")
            _ = await dec.close(session: ses)
            log("repeated: two rounds nativeReady, rev+2 total, resets=2")
        }

        if failures == 0 { log("ALL_CHECKS_PASS") } else { log("FAILURES=\(failures)") }
    }
}
