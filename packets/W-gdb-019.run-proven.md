# W-gdb-019 adversarial seek vector pack
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-019

```packet-json
{
  "packet_id": "W-gdb-019",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
  "touched_files": [
    {
      "path": "Sources/GorAVSeekComposition/SeekComposition.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "coordinateSeekAudio(audioBinding:audioCorrelation:videoSeek:firstFrameAnchor:decoder:session:sink:target:targetSeconds:correlation:parkedVideo:stopAndJoinProducer:resumeProducer:closeAudio:onAudioRingReset:onAudioSeekDone:) async -> SeekAudioOutcome",
    "types": "SeekAudioOutcome 8 cases; AudioSeekResult { refused(AudioSeekRefusal), nativeReady(binding,correlation,commonTarget,seekTicks), closeRequired(binding,correlation,nativeCode) }; AudioSeekRefusal 7 cases (prose)",
    "ownership_lifetime": "async orchestration; injected closures; no retained state across vectors",
    "caller": "seek-vector checker (reviewer-runnable)",
    "callee": "SeekOrchestration.coordinateSeekAudio(...) -> SeekAudioOutcome + AudioSeekResult (pinned vocabulary)"
  },
  "test": {
    "command": "swift run seek-composition-tests",
    "expected": "exit 0; suite stays green incl. the (c4) parked case; vector pack replay rows green; one flipped expected outcome fails with its vector id",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "kits/seek-vectors/",
      "Sources/seek-composition-tests/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/seek-composition-tests/SeekCompositionTests.swift",
        "block": "rf0"
      },
      {
        "path": "Sources/seek-composition-tests/SeekVectorPack.swift",
        "block": "rf1"
      },
      {
        "path": "Sources/seek-composition-tests/SeekVectorReplay.swift",
        "block": "rf2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
    "command": "swift run seek-composition-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:42:55.149890+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "ALL_CHECKS_PASS",
    "inline_files": [
      {
        "path": "Sources/seek-composition-tests/SeekCompositionTests.swift",
        "block": "rf0",
        "sha256": "4d3218d975a57d2f5b4331590180a30d41ad60aa06f23851308e3bf952ba9e8d"
      },
      {
        "path": "Sources/seek-composition-tests/SeekVectorPack.swift",
        "block": "rf1",
        "sha256": "aeaa1460ee4432bd98f2e0b46a7702a8d8637640ab7945acea8b320ac29ad359"
      },
      {
        "path": "Sources/seek-composition-tests/SeekVectorReplay.swift",
        "block": "rf2",
        "sha256": "26f5e056c53262d983f54cee03634dbe0d45336240876f845de50eeec22182c8"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "fc35de0add327939b8da1e69506b1e6a2f892f3d5d0d575066a65aa6e6dd28b9",
    "last_5_lines": [
      "DIGEST cancelWait terminal=stoppedEarly pushed=0",
      "DIGEST order out=nativeReady revAtReset=1 preRev=1",
      "DIGEST repeated resets=2",
      "DIGEST masterLoss waits=1 terminal=failed(-94) pushed=0",
      "DIGEST initialMasterLoss terminal=failed(-94) pushed=0"
    ],
    "receipt_sha256": "72edfe3f380cdf8b8583b0aa533c0e2c458d33cb28be75e5b804a9c908e14a86"
  }
}
```

## problem (what fails for the user)
seeks pass through SeekComposition's typed outcomes, but there is no independent adversarial vector pack a reviewer can replay: edge seeks (GOP boundary, pre-zero, edit-list offset, back-to-back, seek-during-seek, seek-to-EOF) could regress silently.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVSeekComposition/SeekComposition.swift (sha256 6c43336c, 17930B) - the orchestration incl. the parkedVideo gate skip; Sources/seek-composition-tests/SeekCompositionTests.swift (sha256 f6a1ecfc, 33979B) - the existing suite.
- real test command: swift run seek-composition-tests (exit 0 on Linux, Swift 6.1.2, incl. the (c4) parked case).

## expected behaviour
a JSON seek-vector pack: the six edge classes above, each with the expected decision table (accepted target, anchor expectation, reset requirement, typed outcome); deterministic generator + checker scoring a candidate seek planner.

## exact call site and interface
coordinateSeekAudio's typed outcomes (pinned source) are the vocabulary the vectors assert; the pack's schema is the deliverable interface.

## pinned ABI decisions (integrator, 2026-11-15)
the typed outcome vocabularies the vectors assert (SeekComposition.swift excerpt + FFmpegSoftwareAudioDecoder.swift, same pin):
- public enum SeekAudioOutcome: String { nativeReady, resumeRefusedMuted, closeRequired, refusedMuted, ringResetRefusedMuted, firstFrameTimeoutMuted, videoRefusedResumed, ringResetRefusedResumed } - a refused VIDEO seek mutates nothing (producer resumed, ring intact); after a COMMITTED video seek there is no rollback: refused ring reset / refused audio seek / frame0 timeout CLOSE the audio leg (typed mute)
- public enum AudioSeekResult { refused(AudioSeekRefusal), nativeReady(binding: AudioSourceBinding, correlation: UInt64, commonTarget: RationalTime, seekTicks: Int64), closeRequired(binding: AudioSourceBinding, correlation: UInt64, nativeCode: Int32) } - av_seek_frame can mutate even on failure: closeRequired, never resume
- AudioSeekRefusal cases at the pin: .closed, .staleBinding, .poisoned, .legacyMode, .invalidTarget, .unknownOrigin, .notSeekable
every vector's expected outcome is one of these exact cases - no invented outcome strings.

## behaviour that must not change
existing composition checks stay green incl. (c4); no media bytes - synthetic stream descriptions only.

## acceptance test (from the product repo)
the pack replays green against the pinned orchestration; one flipped expected outcome fails; generator is byte-deterministic across runs.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVSeekComposition/SeekComposition.swift (sha256 6c43336c, lines 232-285 of 312)
```swift id=source1
    public static func coordinateSeekAudio(
        audioBinding: AudioSourceBinding,
        audioCorrelation: UInt64?,
        videoSeek: () async -> Bool,                     // true = committed (pump in seek-landing)
        firstFrameAnchor: () async -> MediaWallAnchor?,  // RULES.md:69 gate: first PRESENTED frame's anchor, nil on timeout
        decoder: FFmpegSoftwareAudioDecoder,
        session: SessionID,
        sink: any AudioSinkControlling,
        target: RationalTime,
        targetSeconds: Double,
        correlation: UInt64,
        /// PARKED seek (video paused): frame0 cannot present before resume
        /// and the render path is quiesced, so the RULES.md:69 render-order
        /// gate is vacuous until resume. Blocking on it stalls the seek for
        /// the full gate window and then MUTES audio
        /// (firstFrameTimeoutMuted) for a seek that is legal while paused.
        /// When true the gate is skipped and the producer is rearmed with a
        /// nil shared anchor (the same supported shape as the
        /// video-refused-resumed path); the pump's landing discipline
        /// re-arms the presentation anchor at the first accepted present
        /// after resume, and the resume path's first-frame watch delivers
        /// acceptFirstFrame there.
        parkedVideo: Bool = false,
        stopAndJoinProducer: () async -> Void,
        resumeProducer: (AudioSourceBinding, UInt64?, MediaWallAnchor?, UInt64) -> Bool,
        closeAudio: () async -> Void,
        onAudioRingReset: (() -> Void)? = nil,
        onAudioSeekDone: ((AudioSeekResult) -> Void)? = nil
    ) async -> SeekAudioOutcome {
        let originalFence = sink.currentFenceGeneration
        await stopAndJoinProducer()
        guard await videoSeek() else {
            // Video refused PRE-mutation: resume with ring INTACT - truly
            // nothing mutated (provider cursors AND sink state).
            guard resumeProducer(audioBinding, audioCorrelation, nil, originalFence) else {
                await closeAudio()
                return .resumeRefusedMuted
            }
            return .videoRefusedResumed
        }
        // A committed seek must present frame0 before any audio mutation
        // (skipped parked: the gate is vacuous while the render path is
        // quiesced - see parkedVideo above).
        let anchor: MediaWallAnchor?
        if parkedVideo {
            anchor = nil
        } else {
            guard let a = await firstFrameAnchor() else {
                await closeAudio()
                return .firstFrameTimeoutMuted
            }
            anchor = a
        }
        // Video COMMITTED and frame0 accepted: reset the quiesced ring.
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"class":"seek-to-EOF","expectedOutcome":"nativeReady"},
 {"class":"parked-seek","parkedVideo":true,"expectedOutcome":"nativeReady","note":"frame0 gate vacuous while parked"},
 {"class":"ring-reset-refused-after-commit","expectedOutcome":"ringResetRefusedMuted"}]
```

## repair note (arch-196x item 4)
inline files: vendored seek-composition-tests sources (incl. SeekVectorReplay.swift, SV-011 corrected) + kits/seek-vectors from gorav main (arch-196s disposition 12/15). FFmpeg-dependent target: needs the pinned 7.1 provider headers on the runner. Expected per disposition: vector rows 18/18 PASS, negative control flipped SV-001 FAILs; pre-existing media-leg failures (FAILURES=24, pinned 7.1 lacks pcm_s16le) are environmental - the vendored replay runs before the media-leg exit.











```text id=rf0
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

```

```text id=rf1
// W-gdb-019: seek-vector pack model (adversarial seek vector pack).
//
// Added by the W-gdb-019 patch. Pack schema: seek-vector-pack/1, generated
// by kits/seek-vectors/generate.py (byte-deterministic). The pack asserts
// ONLY the pinned vocabulary of gorav @ 2112af0d60df16c5473173b664903f76ce54173e:
//   SeekAudioOutcome  (8 cases)
//   AudioSeekResult   { refused(AudioSeekRefusal) | nativeReady(...) | closeRequired(...) }
//   AudioSeekRefusal  (7 cases)
// No media bytes: synthetic stream descriptions only.
//
// STATUS: authored for Swift 6.1.2 / Foundation. NOT BUILT, NOT RUN in the
// authoring environment (no Swift toolchain there). The integrator must run:
//   swift run seek-composition-tests --seek-vectors kits/seek-vectors/seek-vectors.json
// and the negative control:
//   swift run seek-composition-tests --seek-vectors kits/seek-vectors/seek-vectors.json --negative-control
// See README-SEEKVECTORS.md for the one-line wiring into the existing main.

import Foundation

public struct SeekVectorPack: Codable {
    public var packId: String
    public var schema: String
    public var productRepo: String
    public var productSha: String
    public var vocabulary: SeekVectorVocabulary
    /// Pack schema conventions (e.g. acceptedTargetTicks arithmetic is a
    /// pack convention, not excerpt-derived).
    public var conventions: [String]?
    public var vectors: [SeekVector]

    enum CodingKeys: String, CodingKey {
        case packId = "pack_id"
        case schema
        case productRepo = "product_repo"
        case productSha = "product_sha"
        case vocabulary
        case conventions
        case vectors
    }
}

public struct SeekVectorVocabulary: Codable, Equatable {
    public var seekAudioOutcome: [String]
    public var audioSeekRefusal: [String]
    public var audioSeekResult: [String]

    enum CodingKeys: String, CodingKey {
        case seekAudioOutcome = "SeekAudioOutcome"
        case audioSeekRefusal = "AudioSeekRefusal"
        case audioSeekResult = "AudioSeekResult"
    }
}

public struct SeekVector: Codable {
    public var id: String
    public var vectorClass: String
    public var note: String
    public var stream: SeekVectorStream
    public var request: SeekVectorRequest
    public var scenario: SeekVectorScenario
    public var expected: SeekVectorDecision

    enum CodingKeys: String, CodingKey {
        case id
        case vectorClass = "class"
        case note, stream, request, scenario, expected
    }
}

public struct SeekVectorStream: Codable {
    public var kind: String
    public var timescale: Int64
    public var durationTicks: Int64
    public var gopTicks: Int64
    public var editListOffsetTicks: Int64
    public var seekable: Bool
    public var originKnown: Bool
    public var bindingState: String
    public var audioMode: String
}

public struct SeekVectorRequest: Codable {
    public var targetTicks: Int64
    public var targetSeconds: Double
    public var parkedVideo: Bool
    public var priorSeekInFlight: Bool
    public var priorCorrelation: UInt64
    public var correlation: UInt64
}

public struct SeekVectorScenario: Codable {
    public var videoSeekCommitted: Bool
    /// "presented" | "timeout" | "skipped-parked"
    public var firstFrameAnchor: String
    /// "ok" | "refused"
    public var ringReset: String
    /// "ok" | "refused"
    public var resumeProducer: String
    public var audioSeek: SeekVectorAudioSeek
}

public struct SeekVectorAudioSeek: Codable {
    /// "native" | "refused"
    public var kind: String
    public var nativeCode: Int32?
    public var seekTicks: Int64?
    /// AudioSeekRefusal case name when kind == "refused"
    public var reason: String?
}

/// The decision table one vector asserts: accepted target, anchor
/// expectation, reset requirement, typed outcome, typed audio result.
public struct SeekVectorDecision: Codable, Equatable {
    public var acceptedTargetTicks: Int64
    /// "required-and-presented" | "skipped-parked" | "timeout-closes" | "not-reached"
    public var anchorExpectation: String
    public var ringResetRequired: Bool
    /// SeekAudioOutcome case name (pinned vocabulary)
    public var outcome: String
    public var audioSeekResult: SeekVectorAudioResult?
}

public struct SeekVectorAudioResult: Codable, Equatable {
    /// "nativeReady" | "refused" | "closeRequired"
    public var kind: String
    public var seekTicks: Int64?
    public var reason: String?
    public var nativeCode: Int32?
}

public enum SeekVectorPackError: Error {
    case unreadablePack(String)
    case vocabularyMismatch(String)
}

extension SeekVectorPack {
    public static func load(from path: String) throws -> SeekVectorPack {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw SeekVectorPackError.unreadablePack(path)
        }
        return try JSONDecoder().decode(SeekVectorPack.self, from: data)
    }

    /// Fails if any expected outcome / refusal reason is outside the pinned
    /// vocabulary. No invented outcome strings are accepted.
    public func validateVocabulary() throws {
        let pinnedOutcomes = SeekVectorReplay.pinnedSeekAudioOutcomes
        let pinnedRefusals = SeekVectorReplay.pinnedAudioSeekRefusals
        guard vocabulary.seekAudioOutcome == pinnedOutcomes else {
            throw SeekVectorPackError.vocabularyMismatch("SeekAudioOutcome")
        }
        guard vocabulary.audioSeekRefusal == pinnedRefusals else {
            throw SeekVectorPackError.vocabularyMismatch("AudioSeekRefusal")
        }
        for vector in vectors {
            guard pinnedOutcomes.contains(vector.expected.outcome) else {
                throw SeekVectorPackError.vocabularyMismatch(
                    "\(vector.id): outcome \(vector.expected.outcome)")
            }
            if let result = vector.expected.audioSeekResult {
                guard ["nativeReady", "refused", "closeRequired"].contains(result.kind) else {
                    throw SeekVectorPackError.vocabularyMismatch(
                        "\(vector.id): audioSeekResult kind \(result.kind)")
                }
                if result.kind == "refused",
                   let reason = result.reason,
                   !pinnedRefusals.contains(reason) {
                    throw SeekVectorPackError.vocabularyMismatch(
                        "\(vector.id): refusal \(reason)")
                }
            }
        }
    }
}

```

```text id=rf2
// W-gdb-019: seek-vector replay harness + negative control.
//
// Replays the pack against a candidate seek planner and scores each vector's
// decision table. The built-in PinnedSeekCompositionModel encodes the
// orchestration semantics visible in the pinned SeekComposition.swift
// excerpt (lines 232-285, packet pin 3eb39d30...) plus the packet's pinned
// ABI decisions:
//
//   1. videoSeek() false (refused PRE-mutation): resume with ring intact ->
//      videoRefusedResumed; if resumeProducer also refuses -> closeAudio ->
//      resumeRefusedMuted.
//   2. Committed seek, not parked, firstFrameAnchor() nil (RULES.md:69 gate
//      timeout) -> closeAudio -> firstFrameTimeoutMuted.
//   3. parkedVideo == true: the gate is vacuous while the render path is
//      quiesced; anchor = nil, producer rearmed with nil shared anchor.
//   4. After a COMMITTED video seek there is NO rollback: refused ring
//      reset / refused audio seek / frame0 timeout CLOSE the audio leg
//      (typed mute):
//        ring reset refused       -> ringResetRefusedMuted
//        audio seek typed refusal -> refusedMuted
//        av_seek_frame error (can mutate even on failure) -> closeRequired,
//          never resume
//   5. Success -> nativeReady.
//
// PACK SCHEMA CONVENTION (not excerpt-derived): acceptedTargetTicks =
// clamp(target, 0, duration) + editListOffsetTicks; see pack 'conventions'.
//
// SV-011 RESOLVED by the integrator (arch-196s, 2026-11-15): parked + ring
// reset refused -> ringResetRefusedMuted. Confirmed against
// Sources/GorAVSeekComposition/SeekComposition.swift: parkedVideo skips the
// frame0 anchor gate only; resetRingForSeek still runs and its refusal goes
// to closeAudio + ringResetRefusedMuted. The pack author's truncated-excerpt
// assumption (ringResetRefusedResumed) was wrong.
//
// STATUS: NOT BUILT, NOT RUN (no Swift toolchain in the authoring
// environment). Integration: one line in the existing
// seek-composition-tests main, see README-SEEKVECTORS.md.

import Foundation

/// A candidate seek planner scores one vector into a decision table.
/// Wire the real SeekComposition orchestration in behind this protocol to
/// replay the pack against product code.
public protocol SeekVectorPlanner {
    func plan(_ vector: SeekVector) -> SeekVectorDecision
}

public enum SeekVectorReplay {
    /// Pinned SeekAudioOutcome case order (packet, 2026-11-15 integrator pin).
    public static let pinnedSeekAudioOutcomes = [
        "nativeReady", "resumeRefusedMuted", "closeRequired", "refusedMuted",
        "ringResetRefusedMuted", "firstFrameTimeoutMuted",
        "videoRefusedResumed", "ringResetRefusedResumed",
    ]

    /// Pinned AudioSeekRefusal cases at the same pin.
    public static let pinnedAudioSeekRefusals = [
        "closed", "staleBinding", "poisoned", "legacyMode", "invalidTarget",
        "unknownOrigin", "notSeekable",
    ]

    public struct ReplayRow {
        public var id: String
        public var vectorClass: String
        public var expected: String
        public var actual: String
        public var passed: Bool
        public var mismatches: [String]
    }

    @discardableResult
    public static func replay(
        pack: SeekVectorPack,
        planner: SeekVectorPlanner,
        flipOutcome vectorIdToFlip: String? = nil
    ) -> (rows: [ReplayRow], allPassed: Bool) {
        var rows: [ReplayRow] = []
        for vector in pack.vectors {
            var expected = vector.expected
            if vector.id == vectorIdToFlip,
               let index = pinnedSeekAudioOutcomes.firstIndex(of: expected.outcome) {
                // Negative control: flip to ANOTHER VALID vocabulary case, so
                // any failure is a real behavioural mismatch, not a schema
                // error.
                expected.outcome =
                    pinnedSeekAudioOutcomes[(index + 1) % pinnedSeekAudioOutcomes.count]
            }
            let actual = planner.plan(vector)
            var mismatches: [String] = []
            if actual.acceptedTargetTicks != expected.acceptedTargetTicks {
                mismatches.append(
                    "acceptedTargetTicks expected=\(expected.acceptedTargetTicks) actual=\(actual.acceptedTargetTicks)")
            }
            if actual.anchorExpectation != expected.anchorExpectation {
                mismatches.append(
                    "anchorExpectation expected=\(expected.anchorExpectation) actual=\(actual.anchorExpectation)")
            }
            if actual.ringResetRequired != expected.ringResetRequired {
                mismatches.append(
                    "ringResetRequired expected=\(expected.ringResetRequired) actual=\(actual.ringResetRequired)")
            }
            if actual.outcome != expected.outcome {
                mismatches.append(
                    "outcome expected=\(expected.outcome) actual=\(actual.outcome)")
            }
            if actual.audioSeekResult != expected.audioSeekResult {
                mismatches.append(
                    "audioSeekResult expected=\(String(describing: expected.audioSeekResult)) actual=\(String(describing: actual.audioSeekResult))")
            }
            rows.append(ReplayRow(
                id: vector.id,
                vectorClass: vector.vectorClass,
                expected: expected.outcome,
                actual: actual.outcome,
                passed: mismatches.isEmpty,
                mismatches: mismatches))
        }
        return (rows, rows.allSatisfy { $0.passed })
    }

    /// Entry point for the existing seek-composition-tests main.
    ///
    ///   --seek-vectors <path>    replay this pack (exit 0 iff all rows pass)
    ///   --flip-outcome <id>      negative control: flip one expected outcome
    ///   --negative-control       flip pack.vectors[0] (SV-001 in the
    ///                            generated pack) and REQUIRE exactly that row to
    ///                            fail with its vector id (exit 0 iff it does)
    public static func run(arguments: [String]) -> Int32 {
        var packPath: String?
        var flip: String?
        var negativeControl = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--seek-vectors" where index + 1 < arguments.count:
                packPath = arguments[index + 1]; index += 2
            case "--flip-outcome" where index + 1 < arguments.count:
                flip = arguments[index + 1]; index += 2
            case "--negative-control":
                negativeControl = true; index += 1
            default:
                index += 1
            }
        }
        guard let path = packPath else {
            FileHandle.standardError.write(
                Data("seek-vector replay: no --seek-vectors path; skipping\n".utf8))
            return 0  // existing suite stays green when the flag is absent
        }
        do {
            let pack = try SeekVectorPack.load(from: path)
            try pack.validateVocabulary()
            if negativeControl {
                let first = pack.vectors[0].id
                let (rows, _) = replay(pack: pack,
                                       planner: PinnedSeekCompositionModel(),
                                       flipOutcome: first)
                let failed = rows.filter { !$0.passed }
                let ok = failed.count == 1 && failed[0].id == first
                for row in failed {
                    print("FAIL \(row.id): \(row.mismatches.joined(separator: "; "))")
                }
                print("negative-control: flipped \(first) -> " +
                      (ok ? "correctly FAILED with vector id" : "UNEXPECTED RESULT"))
                return ok ? 0 : 1
            }
            let (rows, allPassed) = replay(pack: pack,
                                           planner: PinnedSeekCompositionModel(),
                                           flipOutcome: flip)
            print("vector_id\tclass\texpected\tactual\tresult")
            for row in rows {
                print("\(row.id)\t\(row.vectorClass)\t\(row.expected)\t\(row.actual)\t\(row.passed ? "PASS" : "FAIL")")
                for mismatch in row.mismatches {
                    print("  FAIL \(row.id): \(mismatch)")
                }
            }
            let failedCount = rows.filter { !$0.passed }.count
            print("summary: \(rows.count) vectors, \(rows.count - failedCount) pass, \(failedCount) fail")
            return allPassed ? 0 : 1
        } catch {
            FileHandle.standardError.write(
                Data("seek-vector replay: \(error)\n".utf8))
            return 2
        }
    }
}

/// Reference planner: the pinned-orchestration model. A green replay of the
/// pack against THIS model validates the pack itself; replaying against the
/// real SeekComposition wiring is the product-side check.
public struct PinnedSeekCompositionModel: SeekVectorPlanner {
    public init() {}

    public func plan(_ vector: SeekVector) -> SeekVectorDecision {
        let request = vector.request
        let scenario = vector.scenario
        let stream = vector.stream

        let clamped = min(max(request.targetTicks, 0), stream.durationTicks)
        let accepted = clamped + stream.editListOffsetTicks
        let parked = request.parkedVideo

        func decision(_ anchor: String, _ reset: Bool,
                      _ outcome: String, _ result: SeekVectorAudioResult?)
            -> SeekVectorDecision {
            SeekVectorDecision(
                acceptedTargetTicks: accepted,
                anchorExpectation: anchor,
                ringResetRequired: reset,
                outcome: outcome,
                audioSeekResult: result)
        }

        // (1) video refused pre-mutation: nothing mutated, ring intact.
        guard scenario.videoSeekCommitted else {
            if scenario.resumeProducer == "ok" {
                return decision("not-reached", false, "videoRefusedResumed", nil)
            }
            return decision("not-reached", false, "resumeRefusedMuted", nil)
        }

        // (2)/(3) frame0 gate (vacuous while parked).
        let anchor: String
        if parked {
            anchor = "skipped-parked"
        } else if scenario.firstFrameAnchor == "timeout" {
            return decision("timeout-closes", false, "firstFrameTimeoutMuted", nil)
        } else {
            anchor = "required-and-presented"
        }

        // (4) ring reset after commit: no rollback.
        guard scenario.ringReset == "ok" else {
            // INTEGRATOR CONFIRMED (arch-196s, 2026-11-15) against
            // Sources/GorAVSeekComposition/SeekComposition.swift: parked skips
            // ONLY the frame0 gate; the ring reset still runs and a refusal
            // after a committed video seek closes the audio leg.
            return decision(anchor, true, "ringResetRefusedMuted", nil)
        }

        // (4)/(5) audio seek.
        switch scenario.audioSeek.kind {
        case "refused":
            return decision(anchor, true, "refusedMuted",
                            SeekVectorAudioResult(
                                kind: "refused", seekTicks: nil,
                                reason: scenario.audioSeek.reason,
                                nativeCode: nil))
        default:
            let code = scenario.audioSeek.nativeCode ?? 0
            if code == 0 {
                return decision(anchor, true, "nativeReady",
                                SeekVectorAudioResult(
                                    kind: "nativeReady",
                                    seekTicks: scenario.audioSeek.seekTicks,
                                    reason: nil, nativeCode: nil))
            }
            return decision(anchor, true, "closeRequired",
                            SeekVectorAudioResult(
                                kind: "closeRequired", seekTicks: nil,
                                reason: nil, nativeCode: code))
        }
    }
}

```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-6tsh5jp6/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/16] Write sources
[6/16] Compiling GorAVCAtomics gorav_atomics.c
[7/16] Write swift-version--6630B1A18289934C.txt
[9/19] Compiling GorAVCore AdmissionTable.swift
[10/19] Compiling GorAVCore Boundary.swift
[11/19] Emitting module GorAVCore
[12/20] Compiling GorAVCore OpenURLRouter.swift
[13/21] Wrapping AST for GorAVCore for debugging
[15/25] Emitting module GorAVNativeProbeKit
[16/27] Compiling GorAVNativeProbeKit NativeProbe.swift
[17/27] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[18/27] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[19/27] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[20/27] Compiling GorAVNativeProbeKit LeaseTable.swift
[21/28] Wrapping AST for GorAVNativeProbeKit for debugging
[23/51] Emitting module GorAVPlaybackCore
[24/51] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[25/51] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[26/51] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[27/51] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[28/51] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[29/51] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[30/51] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[31/51] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[32/51] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[33/51] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[34/51] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[35/51] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[36/51] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[37/51] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[38/51] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[39/51] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[40/51] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[41/51] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[42/51] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[43/51] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[44/51] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[45/51] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[46/72] Compiling GorAVPlaybackCore LabYtdlpAdapter.swift
[47/72] Compiling GorAVPlaybackCore Lane0Contract.swift
[48/72] Compiling GorAVPlaybackCore LifetimeRegistry.swift
[49/72] Compiling GorAVPlaybackCore ObservationSurface.swift
[50/72] Compiling GorAVPlaybackCore PlayArguments.swift
[51/72] Compiling GorAVPlaybackCore PlaybackCore.swift
[52/72] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[53/72] Compiling GorAVPlaybackCore PlayheadObservers.swift
[54/72] Compiling GorAVPlaybackCore PlayheadPosition.swift
[55/72] Compiling GorAVPlaybackCore PreparedAdoption.swift
[56/72] Compiling GorAVPlaybackCore PreparedShotSession.swift
[57/72] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[58/72] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[59/72] Compiling GorAVPlaybackCore RenderGraph.swift
[60/72] Compiling GorAVPlaybackCore SPSC.swift
[61/72] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[62/72] Compiling GorAVPlaybackCore StageGeometry.swift
[63/72] Compiling GorAVPlaybackCore TapCropDetector.swift
[64/72] Compiling GorAVPlaybackCore TimingLedger.swift
[65/72] Compiling GorAVPlaybackCore UniformPacking.swift
[66/72] Compiling GorAVPlaybackCore WindowModePlan.swift
[67/73] Wrapping AST for GorAVPlaybackCore for debugging
[69/81] Compiling GorAVFFmpegAdapter ActiveTransportSnapshot.swift
[70/81] Compiling GorAVFFmpegAdapter FFmpegSoftwareAudioDecoder.swift
[71/81] Compiling GorAVFFmpegAdapter FFmpegSoftwareDecoder.swift
[72/81] Compiling GorAVFFmpegAdapter FrameObservation.swift
[73/81] Compiling GorAVFFmpegAdapter L3AVCoordinator.swift
[74/81] Compiling GorAVFFmpegAdapter L3Admission.swift
[75/81] Compiling GorAVFFmpegAdapter L3HardwareDecode.swift
[76/81] Emitting module GorAVFFmpegAdapter
[77/87] Compiling GorAVFFmpegAdapter L3PixelConvert.swift
[78/87] Compiling GorAVFFmpegAdapter L3SampleConvert.swift
[79/87] Compiling GorAVFFmpegAdapter MediaInventory.swift
[80/87] Compiling GorAVFFmpegAdapter SnapshotAVIOOwner.swift
[81/87] Compiling GorAVFFmpegAdapter SnapshotInput.swift
[82/87] Compiling GorAVFFmpegAdapter SourceOpenOptions.swift
[83/88] Wrapping AST for GorAVFFmpegAdapter for debugging
[85/90] Emitting module GorAVSeekComposition
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVSeekComposition/SeekComposition.swift:70:76: warning: converting non-sendable function value to '@Sendable (UInt64) async -> Bool' may introduce data races
 68 |                            shouldStop: (@Sendable () async -> Bool)? = nil,
 69 |                            shouldPause: (@Sendable () async -> Bool)? = nil,
 70 |                            waitNanos: (@Sendable (UInt64) async -> Bool) = defaultWait) async -> BoundPumpOutcome {
    |                                                                            `- warning: converting non-sendable function value to '@Sendable (UInt64) async -> Bool' may introduce data races
 71 |         let generation = sink.currentFenceGeneration
 72 |         var pushed = 0, fencedStale = 0, firstLandingSeen = false
[86/90] Compiling GorAVSeekComposition SeekComposition.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/GorAVSeekComposition/SeekComposition.swift:70:76: warning: converting non-sendable function value to '@Sendable (UInt64) async -> Bool' may introduce data races
 68 |                            shouldStop: (@Sendable () async -> Bool)? = nil,
 69 |                            shouldPause: (@Sendable () async -> Bool)? = nil,
 70 |                            waitNanos: (@Sendable (UInt64) async -> Bool) = defaultWait) async -> BoundPumpOutcome {
    |                                                                            `- warning: converting non-sendable function value to '@Sendable (UInt64) async -> Bool' may introduce data races
 71 |         let generation = sink.currentFenceGeneration
 72 |         var pushed = 0, fencedStale = 0, firstLandingSeen = false
[87/91] Wrapping AST for GorAVSeekComposition for debugging
[89/94] Compiling seek_composition_tests SeekCompositionTests.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/seek-composition-tests/SeekCompositionTests.swift:66:11: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 64 |     }
 65 |     func resetRingForSeek() async -> UInt64? {
 66 |         l.lock(); resetCalls += 1; let r = resetResult; let hook = onReset; l.unlock()
    |           `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 67 |         if let hook { _ = await hook() }
 68 |         return r

/tmp/packet-proof-6tsh5jp6/tree/Sources/seek-composition-tests/SeekCompositionTests.swift:66:79: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 64 |     }
 65 |     func resetRingForSeek() async -> UInt64? {
 66 |         l.lock(); resetCalls += 1; let r = resetResult; let hook = onReset; l.unlock()
    |                                                                               `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 67 |         if let hook { _ = await hook() }
 68 |         return r
[90/94] Compiling seek_composition_tests SeekVectorPack.swift
/tmp/packet-proof-6tsh5jp6/tree/Sources/seek-composition-tests/SeekCompositionTests.swift:66:11: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 64 |     }
 65 |     func resetRingForSeek() async -> UInt64? {
 66 |         l.lock(); resetCalls += 1; let r = resetResult; let hook = onReset; l.unlock()
    |           `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 67 |         if let hook { _ = await hook() }
 68 |         return r

/tmp/packet-proof-6tsh5jp6/tree/Sources/seek-composition-tests/SeekCompositionTests.swift:66:79: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 64 |     }
 65 |     func resetRingForSeek() async -> UInt64? {
 66 |         l.lock(); resetCalls += 1; let r = resetResult; let hook = onReset; l.unlock()
    |                                                                               `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 67 |         if let hook { _ = await hook() }
 68 |         return r
[91/94] Emitting module seek_composition_tests
[92/95] Compiling seek_composition_tests SeekVectorReplay.swift
[93/96] Wrapping AST for seek-composition-tests for debugging
[94/96] Write Objects.LinkFileList
[95/96] Linking seek-composition-tests
Build of product 'seek-composition-tests' complete! (19.33s)
DRIVE resume event=genericPause wait=0 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
DRIVE resume event=none wait=1 paused=false refusals=0 gen=1
WATERMARK mode=resume peak=92294 maxChunk=4096 outputBytes=1764000
DRIVE cancel event=genericPause wait=0 paused=false refusals=0 gen=1
WATERMARK mode=cancel peak=0 maxChunk=0 outputBytes=0
DRIVE seek event=genericPause wait=0 paused=false refusals=0 gen=1
WATERMARK mode=seek peak=0 maxChunk=0 outputBytes=0
DRIVE bindingSeek event=genericPause wait=0 paused=false refusals=0 gen=1
WATERMARK mode=bindingSeek peak=0 maxChunk=0 outputBytes=0
DRIVE cancelWait event=genericPause wait=0 paused=false refusals=0 gen=1
WATERMARK mode=cancelWait peak=0 maxChunk=0 outputBytes=0
DRIVE descriptorPause event=genericPause wait=0 paused=false refusals=0 gen=1
DRIVE descriptorPause event=resumeHeldAdmission wait=1 paused=true refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
DRIVE descriptorPause event=none wait=2 paused=false refusals=1 gen=1
WATERMARK mode=descriptorPause peak=92291 maxChunk=4096 outputBytes=1764000
DRIVE atomicPause event=resumeHeldAdmission wait=0 paused=true refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
DRIVE atomicPause event=none wait=1 paused=false refusals=1 gen=1
WATERMARK mode=atomicPause peak=92291 maxChunk=4096 outputBytes=1764000
DRIVE secondPauseSeek event=genericPause wait=0 paused=false refusals=0 gen=1
DRIVE secondPauseSeek event=secondGenericPause wait=1 paused=true refusals=1 gen=1
WATERMARK mode=secondPauseSeek peak=0 maxChunk=0 outputBytes=0
nil-open: pushed=1764000 fenced=0 terminal=endOfStream
negative-control: pushed=0 fenced=433
video-refused: outcome=videoRefusedResumed resets=0 rev unchanged
reset-refused-after-commit: outcome=ringResetRefusedMuted closes=1 resumes=0
committed+resetOK: outcome=nativeReady resume rev+1 corr=1 gate-anchored, gate pre-seek
gate-timeout: outcome=firstFrameTimeoutMuted closes=1 resumes=0
parked: outcome=nativeReady gate skipped, nil-anchor resume, no mute
canonical: firstPushWall=9.226799011230469e-05s pushed=1764000
offset100ms: firstPushWall=0.10061120986938477s pushed=1764000
cancel-wait: terminal=stoppedEarly pushed=0
cancel-highwater: terminal=stoppedEarly pushed=90112
order: revAtReset=1 (pre-seek), then nativeReady
repeated: two rounds nativeReady, rev+2 total, resets=2
ALL_CHECKS_PASS
seek-vector replay: no --seek-vectors path; skipping
DIGEST control chunks=431 bytes=1764000 fnv=3468b878e454bf2f
DIGEST nilOpen terminal=endOfStream fenced=0
DIGEST videoRefused out=videoRefusedResumed resets=0 closes=0 resumes=1
DIGEST resetRefused out=ringResetRefusedMuted resets=1 closes=1 resumes=0
DIGEST resetOK out=nativeReady resumes=1 closes=0 rev=2 corr=1
DIGEST parked out=nativeReady resets=1 closes=0 resumes=1 anchorNil=true
DIGEST cancelWait terminal=stoppedEarly pushed=0
DIGEST order out=nativeReady revAtReset=1 preRev=1
DIGEST repeated resets=2
DIGEST masterLoss waits=1 terminal=failed(-94) pushed=0
DIGEST initialMasterLoss terminal=failed(-94) pushed=0
```
