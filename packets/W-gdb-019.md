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
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
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
  "branch": "ohal/gorav",
  "paths": [
   "kits/seek-vectors/",
   "Sources/seek-composition-tests/"
  ],
  "return_form": "patch"
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
