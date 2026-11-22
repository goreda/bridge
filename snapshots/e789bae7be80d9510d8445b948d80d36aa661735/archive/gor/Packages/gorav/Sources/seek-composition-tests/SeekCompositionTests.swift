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
final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    var n: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); value += 1; lock.unlock() }
}
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
    var onHeldAdmission: (() -> Void)? = nil
    var fenceGen: UInt64 = 1
    init(_ c: WallClock) { clock = c }
    var available: Int { l.lock(); defer { l.unlock() }; return max(0, pushedBytes - Int(clock.nowSeconds() * drainRate)) }  // virtual RT drain
    var currentFenceGeneration: UInt64 { l.lock(); defer { l.unlock() }; return fenceGen }
    var paused = false
    var pauseRefusals = 0
    var pausesApplied = 0
    var pushedChunks: [[UInt8]] = []
    var maxQueuedBytes = 0
    var maxChunkBytes = 0
    func push(_ pcm: [UInt8]) { l.lock(); if firstPushWall == nil { firstPushWall = clock.nowSeconds() }; pushedBytes += pcm.count; pushedChunks.append(pcm); l.unlock() }
    func pushIfUnpaused(_ pcm: [UInt8], expectedGeneration: UInt64) -> AudioPushAdmission {
        l.lock(); defer { l.unlock() }
        guard fenceGen == expectedGeneration else { return .stopped }
        guard !paused else {
            pauseRefusals += 1; pausesApplied += 1
            onHeldAdmission?()
            return .heldPaused
        }
        if firstPushWall == nil { firstPushWall = clock.nowSeconds() }
        pushedBytes += pcm.count; pushedChunks.append(pcm)
        maxChunkBytes = max(maxChunkBytes, pcm.count)
        maxQueuedBytes = max(maxQueuedBytes, max(0, pushedBytes - Int(clock.nowSeconds()*drainRate)))
        return .admitted
    }
    func resetRingForSeek() async -> UInt64? {
        l.lock(); resetCalls += 1; let r = resetResult; let hook = onReset; l.unlock()
        if let hook { _ = await hook() }
        return r
    }
    func stats() -> (Int, Double?, Int) { l.lock(); defer { l.unlock() }; return (pushedBytes, firstPushWall, resetCalls) }
    func chunks() -> [[UInt8]] { l.lock(); defer { l.unlock() }; return pushedChunks }
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
        guard let session = PlaybackIdentityAuthority.shared.issue() else { expect(false, "session issue"); return nil }
        let dec = FFmpegSoftwareAudioDecoder()
        do {
            try dec.pinLocalRoots([URL(fileURLWithPath: path).deletingLastPathComponent().path])
            try await dec.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: session)
        } catch { expect(false, "open \(error)"); return nil }
        guard let d = await dec.seekDescriptor(session: session) else { expect(false, "descriptor"); return nil }
        return (dec, session, d)
    }

    static func main() async {
        // Fixture resolution: explicit env wins; otherwise the bridge-style
        // in-repo fallback (GORAV_KIT, then cwd). Still typed NOT_RUN when
        // the fixtures are absent - composition success is never reported
        // without them.
        let env = ProcessInfo.processInfo.environment
        let kit = env["GORAV_KIT"] ?? FileManager.default.currentDirectoryPath
        let canonical = env["GORAV_CANONICAL"] ?? "\(kit)/fixtures/clip-bbb-10s.mov"
        let offset = env["GORAV_OFFSET100"] ?? "\(kit)/fixtures/clip-bbb-10s-audio-offset100ms.mov"
        guard FileManager.default.fileExists(atPath: canonical), FileManager.default.fileExists(atPath: offset) else {
            log("NOT_RUN missing_composition_audio_fixture")
            exit(2)
        }
        let zero = try! RationalTime(value: 0, timescale: 1)

        // Ordered control first: the exact unpaused full output becomes the
        // identity witness for every pause mode, never only "later differ".
        var controlOutput: [[UInt8]] = []
        if let (dec, ses, d) = await openReal(canonical) {
            let sink = FakeSink(WallClock())
            let out = await BoundAudioPump.run(decoder: dec, session: ses,
                binding: d.binding, correlation: nil, sink: sink)
            expect(out.terminal == .endOfStream, "ordered-control: EOS")
            controlOutput = sink.chunks()
            expect(!controlOutput.isEmpty, "ordered-control: output captured")
            // Deterministic witness log (queue item 20): the ordered-control
            // PCM is the identity witness for every pause mode - digest it
            // once here (FNV-1a, same recipe as the adapter frameDigest).
            // Wall-dependent quantities (pushed byte totals on timed legs,
            // first-push walls, high-water partials) stay out of the log.
            var fnv: UInt64 = 14695981039346656037
            var controlBytes = 0
            for chunk in controlOutput { for b in chunk { fnv = (fnv ^ UInt64(b)) &* 1099511628211 }; controlBytes += chunk.count }
            print("DIGEST control chunks=\(controlOutput.count) bytes=\(controlBytes) fnv=\(String(format: "%016llx", fnv))")
            _ = await dec.close(session: ses)
        }

        // Finite, event-driven control object. It performs one named
        // transition on each EXPLICIT control event; completion arms no
        // further control, so no timing/ns discriminator or overdrive cap
        // is load-bearing for correctness. Ordinary waits pass through.
        final class Drive: @unchecked Sendable {
            enum Event: String { case none, genericPause, heldAdmission, secondGenericPause, resumeHeldAdmission }
            let mode: String, sink: FakeSink, dec: FFmpegSoftwareAudioDecoder, binding: AudioSourceBinding
            var event: Event
            var controlWaits = 0
            init(_ mode: String, _ sink: FakeSink, _ dec: FFmpegSoftwareAudioDecoder, _ binding: AudioSourceBinding) {
                self.mode = mode; self.sink = sink; self.dec = dec; self.binding = binding
                event = mode == "atomicPause" ? .resumeHeldAdmission : .genericPause
                if mode == "atomicPause" { sink.paused = true }
            }
            func pauseQuery() async -> Bool {
                switch event {
                case .none: return false
                case .genericPause, .secondGenericPause: return true
                case .heldAdmission, .resumeHeldAdmission: return false
                }
            }
            func wait(_ ns: UInt64) async -> Bool {
                if ns != 10_000_000 { return true } // normal watermark waits untouched
                log("DRIVE \(mode) event=\(event.rawValue) wait=\(controlWaits) paused=\(sink.paused) refusals=\(sink.pauseRefusals) gen=\(sink.fenceGen)")
                switch event {
                case .none: return await BoundAudioPump.defaultWait(ns)
                case .genericPause:
                    controlWaits += 1
                    if controlWaits > 20 { expect(false, "\(mode): genericPause control overdrive"); return false }
                    expect(sink.chunks().isEmpty, "pause-between-pull-push: content held before wait")
                    switch mode {
                    case "descriptorPause":
                        sink.paused = true
                        event = .resumeHeldAdmission
                    case "seek": sink.fenceGen += 1; event = .none
                    case "bindingSeek":
                        let target = try! RationalTime(value: 0, timescale: 1)
                        let result = await dec.seek(binding: binding, videoRelativeTarget: target, correlation: 99)
                        if case .nativeReady = result {} else { expect(false, "pause-bindingSeek: real seek committed") }
                        event = .none
                    case "secondPauseSeek": sink.paused = true; event = .none
                    case "atomicPause": event = .none
                    default: event = .none
                    }
                    return mode != "cancelWait"
                case .heldAdmission:
                    controlWaits += 1
                    if controlWaits > 20 { expect(false, "\(mode): heldAdmission control overdrive"); return false }
                    sink.paused = true
                    event = .none
                    return true
                case .resumeHeldAdmission:
                    controlWaits += 1
                    if controlWaits > 20 { expect(false, "\(mode): resumeHeldAdmission overdrive"); return false }
                    expect(sink.pauseRefusals > 0, "descriptorPause: hold until atomic refusal observed")
                    sink.paused = false
                    event = .none
                    return true
                case .secondGenericPause:
                    controlWaits += 1
                    if controlWaits > 20 { expect(false, "\(mode): secondPause control overdrive"); return false }
                    sink.fenceGen += 1
                    event = .none
                    return true
                }
            }
        }
        for mode in ["resume", "cancel", "seek", "bindingSeek", "cancelWait", "descriptorPause", "atomicPause", "secondPauseSeek"] {
            if let (dec, ses, d) = await openReal(canonical) {
                let sink = FakeSink(WallClock())
                let drive = Drive(mode, sink, dec, d.binding)
                if mode == "secondPauseSeek" {
                    sink.onHeldAdmission = { drive.event = .secondGenericPause }
                }
                let out = await BoundAudioPump.run(decoder: dec, session: ses,
                    binding: d.binding, correlation: nil, sink: sink,
                    shouldStop: { mode == "cancel" && drive.event == .none },
                    shouldPause: { await drive.pauseQuery() },
                    waitNanos: { ns in await drive.wait(ns) })
                // Second generic pause must have been reached; arm it only
                // after the first admission returned heldPaused.
                if mode == "secondPauseSeek" {
                    expect(sink.pauseRefusals > 0 && sink.fenceGen == 2, "second pause reached after held admission and advanced generation")
                }
                if mode == "resume" {
                    expect(out.terminal == .endOfStream && out.pushed > 0, "pause-resume: held PCM resumes")
                } else if mode == "cancelWait" {
                    expect(out.terminal == .cancelled && out.pushed == 0, "pause-cancelWait: cancelled wait no push")
                } else if mode == "descriptorPause" || mode == "atomicPause" {
                    expect(out.terminal == .endOfStream && out.pushed > 0, "pause-\(mode): held PCM admitted after atomic unpaused boundary")
                    expect(sink.pauseRefusals > 0, "pause-\(mode): atomic sink admission refused while paused")
                } else {
                    expect(out.terminal == .stoppedEarly && out.pushed == 0, "pause-\(mode): no stale PCM push")
                    if mode == "seek" || mode == "bindingSeek" || mode == "secondPauseSeek" {
                        expect(out.fencedStale == 1, "pause-\(mode): stale fence counted")
                    }
                }
                log("WATERMARK mode=\(mode) peak=\(sink.maxQueuedBytes) maxChunk=\(sink.maxChunkBytes) outputBytes=\(out.pushed)")
                expect(sink.maxQueuedBytes <= 88200 + sink.maxChunkBytes, "queue bounded by high-water plus one admitted chunk")
                let actual = sink.chunks()
                if mode == "resume" || mode == "descriptorPause" || mode == "atomicPause" {
                    expect(actual == controlOutput, "pause-\(mode): FULL ordered output equals unpaused control")
                    expect(actual.first == controlOutput.first, "pause-\(mode): first held PCM byte identity")
                } else {
                    expect(actual.isEmpty, "pause-\(mode): terminal/stale mode admits no PCM")
                }
                _ = await dec.close(session: ses)
            }
        }

        // (a) ACTUAL pump, NIL-correlation open leg (r3 bug class): must push
        // with zero fenced; correlation 0 is the negative control (all fenced).
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock)
            let out = await BoundAudioPump.run(decoder: dec, session: ses, binding: d.binding, correlation: nil, sink: sink)
            let (pushed, _, _) = sink.stats()
            expect(out.terminal == .endOfStream, "nil-open: terminal endOfStream (got \(out.terminal))")
            expect(pushed > 0 && out.fencedStale == 0, "nil-open: pushed=\(pushed)>0 fencedStale=0 (got \(out.fencedStale))")
            print("DIGEST nilOpen terminal=\(out.terminal) fenced=\(out.fencedStale)")
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
                videoSeek: { false }, firstFrameAnchor: { nil },
                decoder: dec, session: ses, sink: sink,
                target: zero, targetSeconds: 0, correlation: 1,
                stopAndJoinProducer: { }, resumeProducer: { b, c, a, _ in rlog.resume(b, c, a); return true },
                closeAudio: { rlog.close() })
            let (resumes, closes) = rlog.snapshot()
            let revAfter = await dec.seekDescriptor(session: ses)?.binding.revision
            expect(out == .videoRefusedResumed, "video-refused outcome (got \(out))")
            expect(sink.stats().2 == 0, "video-refused: ring reset NOT called (sink state intact)")
            expect(closes == 0 && resumes.count == 1, "video-refused: resume same, no close")
            expect(resumes.first?.0 == d.binding && resumes.first?.1 == nil && resumes.first?.2 == nil, "video-refused: resumed SAME binding+correlation, no anchor")
            expect(revAfter == revBefore, "video-refused: provider cursor untouched (rev \(revAfter ?? 99))")
            print("DIGEST videoRefused out=\(out) resets=\(sink.stats().2) closes=\(closes) resumes=\(resumes.count)")
            _ = await dec.close(session: ses)
            log("video-refused: outcome=\(out) resets=0 rev unchanged")
        }

        // (c) ORDERING, video committed + ring reset REFUSED: typed mute, no resume, no provider seek.
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock); sink.resetResult = nil
            let rlog = ResumeLog()
            let out = await SeekOrchestration.coordinateSeekAudio(
                audioBinding: d.binding, audioCorrelation: nil,
                videoSeek: { true }, firstFrameAnchor: { MediaWallAnchor(mediaSeconds: 0, wallSeconds: 0) },
                decoder: dec, session: ses, sink: sink,
                target: zero, targetSeconds: 0, correlation: 1,
                stopAndJoinProducer: { }, resumeProducer: { b, c, a, _ in rlog.resume(b, c, a); return true },
                closeAudio: { rlog.close() })
            let (resumes, closes) = rlog.snapshot()
            expect(out == .ringResetRefusedMuted, "committed+resetRefused outcome (got \(out))")
            expect(sink.stats().2 == 1, "reset attempted once")
            expect(closes == 1 && resumes.isEmpty, "committed+resetRefused: audio CLOSED (typed mute), NO old-binding resume (A/V split class)")
            print("DIGEST resetRefused out=\(out) resets=\(sink.stats().2) closes=\(closes) resumes=\(resumes.count)")
            _ = await dec.close(session: ses)
            log("reset-refused-after-commit: outcome=\(out) closes=\(closes) resumes=\(resumes.count)")
        }

        // (c2) ORDERING, video committed + reset OK + REAL provider seek: resume new binding+correlation+anchor.
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock)
            let rlog = ResumeLog()
            let anchor = MediaWallAnchor(mediaSeconds: 0.0, wallSeconds: 0.0)
            let gateRev = RevBox()
            let out = await SeekOrchestration.coordinateSeekAudio(
                audioBinding: d.binding, audioCorrelation: nil,
                videoSeek: { true },
                firstFrameAnchor: {
                    // Accepted frame0 must precede ring reset, provider seek and resume.
                    gateRev.rev = await dec.seekDescriptor(session: ses)?.binding.revision
                    return anchor
                },
                decoder: dec, session: ses, sink: sink,
                target: zero, targetSeconds: 0, correlation: 1,
                stopAndJoinProducer: { }, resumeProducer: { b, c, a, _ in rlog.resume(b, c, a); return true },
                closeAudio: { rlog.close() })
            let (resumes, closes) = rlog.snapshot()
            expect(out == .nativeReady, "committed+resetOK outcome (got \(out))")
            expect(resumes.count == 1 && resumes.first?.0.revision == d.binding.revision + 1 && resumes.first?.1 == 1 && resumes.first?.2 == anchor,
                   "committed+resetOK: resumed NEW binding (rev+1), correlation 1, gate anchor")
            expect(gateRev.rev == d.binding.revision,
                   "committed+resetOK: gate observed the PRE-seek revision (order: frame0 -> reset -> seek -> resume)")
            expect(closes == 0, "committed+resetOK: no close")
            print("DIGEST resetOK out=\(out) resumes=\(resumes.count) closes=\(closes) rev=\(resumes.first?.0.revision ?? 0) corr=\(resumes.first?.1 ?? 99)")
            _ = await dec.close(session: ses)
            log("committed+resetOK: outcome=\(out) resume rev+1 corr=1 gate-anchored, gate pre-seek")
        }

        // (c3) RULES.md:69 gate TIMEOUT: video committed, no audio mutation,
        // but no first presented frame inside the gate window -> typed
        // firstFrameTimeoutMuted, audio CLOSED, producer NOT resumed.
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock)
            let rlog = ResumeLog()
            let out = await SeekOrchestration.coordinateSeekAudio(
                audioBinding: d.binding, audioCorrelation: nil,
                videoSeek: { true }, firstFrameAnchor: { nil },
                decoder: dec, session: ses, sink: sink,
                target: zero, targetSeconds: 0, correlation: 1,
                stopAndJoinProducer: { }, resumeProducer: { b, c, a, _ in rlog.resume(b, c, a); return true },
                closeAudio: { rlog.close() })
            let revision = await dec.seekDescriptor(session: ses)?.binding.revision
            let (resumes, closes) = rlog.snapshot()
            expect(out == .firstFrameTimeoutMuted, "gate-timeout outcome (got \(out))")
            expect(sink.stats().2 == 0 && revision == d.binding.revision, "gate-timeout: NO ring reset or decoder seek")
            expect(closes == 1 && resumes.isEmpty, "gate-timeout: audio CLOSED (typed mute), NO resume")
            _ = await dec.close(session: ses)
            log("gate-timeout: outcome=\(out) closes=\(closes) resumes=\(resumes.count)")
        }

        // (c4) PARKED seek (video paused): the RULES.md:69 gate is skipped -
        // firstFrameAnchor must NOT be consulted, the producer resumes with a
        // nil shared anchor, ring reset and decoder seek DO run, outcome is
        // nativeReady. This is the native87 delivery-lane finding: the old
        // unparked-only flow stalled the full gate window and muted audio for
        // a seek that is legal while paused.
        if let (dec, ses, d) = await openReal(canonical) {
            let clock = WallClock(); let sink = FakeSink(clock)
            let rlog = ResumeLog()
            let out = await SeekOrchestration.coordinateSeekAudio(
                audioBinding: d.binding, audioCorrelation: nil,
                videoSeek: { true },
                firstFrameAnchor: { fatalError("parked seek must not wait for frame0") },
                decoder: dec, session: ses, sink: sink,
                target: zero, targetSeconds: 0, correlation: 1,
                parkedVideo: true,
                stopAndJoinProducer: { }, resumeProducer: { b, c, a, _ in rlog.resume(b, c, a); return true },
                closeAudio: { rlog.close() })
            let revision = await dec.seekDescriptor(session: ses)?.binding.revision
            let (resumes, closes) = rlog.snapshot()
            expect(out == .nativeReady, "parked outcome (got \(out))")
            expect(sink.stats().2 == 1, "parked: ring reset ran once (got \(sink.stats().2))")
            expect(revision == d.binding.revision + 1, "parked: decoder seek ran (rev \(revision ?? 99))")
            expect(resumes.count == 1 && resumes.first?.2 == nil, "parked: resumed with NIL shared anchor")
            expect(closes == 0, "parked: no audio close, no mute")
            print("DIGEST parked out=\(out) resets=\(sink.stats().2) closes=\(closes) resumes=\(resumes.count) anchorNil=\(resumes.first?.2 == nil)")
            _ = await dec.close(session: ses)
            log("parked: outcome=\(out) gate skipped, nil-anchor resume, no mute")
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
                                               shouldStop: { calls.increment(); return calls.n > 3 })
            let (pushed, firstWall, _) = sink.stats()
            expect(out.terminal == .stoppedEarly, "cancel-wait: stoppedEarly (got \(out.terminal))")
            expect(pushed == 0 && firstWall == nil, "cancel-wait: zero pushes, no early PCM (pushed=\(pushed))")
            print("DIGEST cancelWait terminal=\(out.terminal) pushed=\(pushed)")
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
                                               shouldStop: { calls.increment(); return calls.n > 200 })
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
                videoSeek: { true }, firstFrameAnchor: { MediaWallAnchor(mediaSeconds: 0, wallSeconds: 0) },
                decoder: dec, session: ses, sink: sink,
                target: zero, targetSeconds: 0, correlation: 1,
                stopAndJoinProducer: { }, resumeProducer: { b, c, a, _ in rlog.resume(b, c, a); return true },
                closeAudio: { rlog.close() })
            expect(out == .nativeReady, "order: nativeReady (got \(out))")
            expect(revBox.rev == d.binding.revision, "order: provider cursor UNTOUCHED at ring reset time (rev \(revBox.rev ?? 99) vs \(d.binding.revision))")
            print("DIGEST order out=\(out) revAtReset=\(revBox.rev ?? 99) preRev=\(d.binding.revision)")
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
                    videoSeek: { true }, firstFrameAnchor: { MediaWallAnchor(mediaSeconds: 0, wallSeconds: 0) },
                    decoder: dec, session: ses, sink: sink,
                    target: zero, targetSeconds: 0, correlation: round,
                    stopAndJoinProducer: { }, resumeProducer: { b, c, a, _ in rlog.resume(b, c, a); return true },
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
            print("DIGEST repeated resets=\(sink.stats().2)")
            _ = await dec.close(session: ses)
            log("repeated: two rounds nativeReady, rev+2 total, resets=2")
        }

        // Master loss while offset-waiting fails typed, no NaN push.
        // Seek the REAL provider to zero so the first PCM timing exists;
        // a far anchor guarantees at least one offset wait, where the
        // injected clock then loses its master.
        final class NaNClock: PlaybackClock, @unchecked Sendable {
            var nanNow = false
            func nowSeconds() -> Double { nanNow ? .nan : 1.0 }
        }
        if let (dec, ses, d) = await openReal(offset) {
            let ar = await dec.seek(binding: d.binding, videoRelativeTarget: zero, correlation: 1)
            guard case .nativeReady(let nb, let corr, _, _) = ar else {
                expect(false, "master-loss: seek nativeReady"); _ = await dec.close(session: ses)
                exit(1)
            }
            let clock = NaNClock(); let sink = FakeSink(WallClock())
            let waits = Counter()
            let out = await BoundAudioPump.run(decoder: dec, session: ses,
                binding: nb, correlation: corr, sink: sink, clock: clock,
                sharedAnchor: MediaWallAnchor(mediaSeconds: 0, wallSeconds: 2),
                waitNanos: { _ in waits.increment(); clock.nanNow = true; return true })
            expect(waits.n == 1, "offset master loss: exactly one offset wait before fail-stop (got \(waits.n))")
            expect(out.terminal == .failed(-94) && out.pushed == 0, "offset master loss typed no push (got \(out.terminal) pushed=\(out.pushed))")
            print("DIGEST masterLoss waits=\(waits.n) terminal=\(out.terminal) pushed=\(out.pushed)")
            _ = await dec.close(session: ses)
        }
        // Initially lost master fails at the pre-wait finite gate too.
        if let (dec, ses, d) = await openReal(offset) {
            let ar = await dec.seek(binding: d.binding, videoRelativeTarget: zero, correlation: 1)
            guard case .nativeReady(let nb, let corr, _, _) = ar else {
                expect(false, "initial-master-loss: seek nativeReady"); _ = await dec.close(session: ses)
                exit(1)
            }
            let clock = NaNClock(); clock.nanNow = true
            let sink = FakeSink(WallClock())
            let out = await BoundAudioPump.run(decoder: dec, session: ses,
                binding: nb, correlation: corr, sink: sink, clock: clock,
                sharedAnchor: MediaWallAnchor(mediaSeconds: 0, wallSeconds: 2))
            expect(out.terminal == .failed(-94) && out.pushed == 0, "initial master loss typed no push")
            print("DIGEST initialMasterLoss terminal=\(out.terminal) pushed=\(out.pushed)")
            _ = await dec.close(session: ses)
        }
        if failures == 0 { log("ALL_CHECKS_PASS") } else { log("FAILURES=\(failures)") }
        // W-gdb-019: seek-vector pack replay runs BEFORE the media-leg exit
        // so the pure-vector acceptance stays runnable on decoder-minimal
        // hosts (skip notice + 0 when no flag).
        let seekVectorStatus = SeekVectorReplay.run(arguments: CommandLine.arguments)
        if seekVectorStatus != 0 { exit(seekVectorStatus) }
        exit(failures == 0 ? 0 : 1)
    }
}
