# W-gdb-001 b-gate B1/B2 bound grounding (research)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-001

target branch: ohal/gorav @ 2112af0d (lab does not push; gdb integrator integrates)
return: patch or full source + fixtures + test runner files; research001: table + cited source lines
publication check: pinned excerpts independently matched; product tests NOT_RUN by publisher; candidate open, unclaimed.

## problem (what fails for the user)
the native87 b-gate harness asserts pause-hold resume landing within 5s and post-seek audio landing within 10s. both bounds are marked PROPOSED in the harness header because no source-grounded value exists; a wrong bound either passes a real hang (too loose) or flakes a healthy player (too tight). the gate cannot go native with ungrounded bounds.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: Sources/b-gate-tests/main.swift (sha256 28ff620c, 11917B) - the harness with the PROPOSED bounds documented in its header; Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, 78639B) - resume/seek/close paths under test; Sources/GorAVSeekComposition/SeekComposition.swift (sha256 6c43336c, 17930B) - the 10s frame0 gate (the one GROUNDED bound) and the parkedVideo skip.
- current bounds and grounds are quoted in the b-gate main.swift header block "Bounds and their grounds".

## expected behaviour
a cited bound table replaces the two PROPOSED values: for each of resume-after-pause landing and post-seek audio landing, a value + unit + public source (player documentation, platform media framework docs, or open-source player code) + whether it is a hard deadline or a watchdog, plus a per-row confidence note. research only: cited table, no code.

## exact call site and interface
Sources/b-gate-tests/main.swift header (bounds block) and the B1 resume waitFor (5s) and B2 audio-landing waitFor (10s) call sites. output rides back as a replacement bounds table the integrator applies to the harness.

## behaviour that must not change
the GROUNDED bounds (frame0 anchor 10s, close_ms < 300) stay as they are; no harness behavior change in this packet beyond the two PROPOSED values.

## acceptance test (from the product repo)
the integrator swaps the returned bounds into b-gate-tests, the harness still compiles (swiftc -parse clean) and every table row carries a public citation; rows without a citation stay PROPOSED explicitly.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/b-gate-tests/main.swift (sha256 28ff620c, lines 1-33 of 211)
```swift
// B-GATE (native87 Stage B, arch spec 00-gate-spec-native87): T3 pause gate
// on the REAL embedded session - the same GorAVEmbeddedSession call surface
// gor's GorAVPlayerHost drives (open / setPaused / seek / close), asserted
// through the public live snapshot fields added for this gate.
//
// Legs:
//   B0 open + FIRST live frame + FIRST live audio callbacks ONLY. This is
//      NOT the native86-flagged E1 continuity witness - E1 continuity runs
//      as a separate ops leg; B0 asserts only that presentation and audio
//      callbacks have STARTED.
//   B1 pause hold (>= 12 s, V2 shape): eof MUST NOT signal; the sink's
//      intentional-pause-silence counter ADVANCES; non-silence delivery,
//      presentation and time-pos FREEZE; render callbacks CONTINUE (a
//      callback-count freeze is not this product's contract).
//      Resume: non-silence resumes, presented advances, no .failed events.
//      Counter and time-pos witnesses must be NON-NIL on both samples:
//      nil==nil equality is not a freeze witness (absence = FAIL).
//   B2 parked seek: seek while paused; exact .seekCommitted payload; on
//      resume the landing frame presents (frame0 anchor re-arms at the
//      target) and audio lands (audioLandingFirstSampleSeconds grows).
//   B3 close from paused: EmbeddedCloseReport - close_ms < 300, typed clean
//      shutdown, counters non-nil.
//
// Bounds and their grounds (spec: "source-grounded existing timeouts, else
// explicit PROPOSED bounds"):
//   close_ms < 300        GROUNDED: e1-headless-tests main.swift close assertion.
//   frame0/anchor 10 s    GROUNDED: GorAVEmbeddedSession.seek firstFrameAnchor
//                         deadline ("10s bounds keyframe-distance decode
//                         catch-up at serial software-decode rates").
//   audio landing 10 s    PROPOSED: same ground as frame0 anchor (no existing
//                         numeric bound in evidence).
//   counter-advance 5 s   PROPOSED: first counter movement after a transition.
//   hold default 12 s     GROUNDED shape: STATUS.md arch-195b V2 "pause 12s /
```

### Sources/GorAVSeekComposition/SeekComposition.swift (sha256 6c43336c, lines 232-285 of 312)
```swift
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
solver lab: unclaimed. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
