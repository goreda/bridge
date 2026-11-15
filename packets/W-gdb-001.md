# W-gdb-001 b-gate B1/B2 cited bounds table + harness swap
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-001

```packet-json
{
 "packet_id": "W-gdb-001",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/b-gate-tests/main.swift",
   "excerpt_block": "source1"
  },
  {
   "path": "Sources/GorAVSeekComposition/SeekComposition.swift",
   "excerpt_block": "source2"
  }
 ],
 "interface": {
  "signatures": "check.py bounds.json -> exit 0; row keys {name,value,unit,kind,citation,confidence}; harness B1/B2 waitFor bounds read named constants sourced from kits/bounds-table/bounds.json, never inline uncited literals",
  "types": "bounds row schema (fixture block); b-gate bounds entries PROPOSED vs GROUNDED; scope product",
  "ownership_lifetime": "bounds.json + check.py owned by kits/bounds-table; the harness consumes the table read-only",
  "caller": "b-gate harness (Sources/b-gate-tests/main.swift bounds block: B1 resume waitFor, B2 audio-landing waitFor)",
  "callee": "kits/bounds-table/bounds.json cited table + kits/bounds-table/check.py row verifier"
 },
 "scope": "product",
 "test": {
  "command": "python3 kits/bounds-table/check.py kits/bounds-table/bounds.json",
  "expected": "exit 0; stdout 'bounds-check: 2/2 rows cited, 0 uncited PASS'; a row missing value+unit+public citation prints its name and exits 1 (negative control in fixture); the swapped harness stays swiftc -parse clean",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/bounds-table/",
   "Sources/b-gate-tests/main.swift"
  ],
  "return_form": "full-files"
 }
}
```

## problem (what fails for the user)
the native87 b-gate harness asserts pause-hold resume landing within 5s and post-seek audio landing within 10s. both bounds are marked PROPOSED in the harness header because no source-grounded value exists; a wrong bound either passes a real hang (too loose) or flakes a healthy player (too tight). the gate cannot go native with ungrounded bounds.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: Sources/b-gate-tests/main.swift (sha256 28ff620c, 11917B) - the harness with the PROPOSED bounds documented in its header; Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift (sha256 558ab8a4, 78639B) - resume/seek/close paths under test; Sources/GorAVSeekComposition/SeekComposition.swift (sha256 6c43336c, 17930B) - the 10s frame0 gate (the one GROUNDED bound) and the parkedVideo skip.
- current bounds and grounds are quoted in the b-gate main.swift header block "Bounds and their grounds".

## expected behaviour
an implementation in two parts. (1) kits/bounds-table/: bounds.json carrying one row per PROPOSED bound (resume-after-pause landing, post-seek audio landing), each row = value + unit + kind (hard-deadline or watchdog) + public citation (player documentation, platform media framework docs, or open-source player code) + confidence, plus check.py (stdlib only) validating every row. (2) Sources/b-gate-tests/main.swift: the B1 resume waitFor and B2 audio-landing waitFor read their bounds from the table (via named constants generated or loaded from bounds.json); the two PROPOSED header lines become cited entries. The solver picks the cited values from public sources; uncited rows are rejected by check.py, not shipped.

## exact call site and interface
Sources/b-gate-tests/main.swift header (bounds block) and the B1 resume waitFor (5s) and B2 audio-landing waitFor (10s) call sites - those two call sites consume the table. Deliverables: kits/bounds-table/bounds.json, kits/bounds-table/check.py, and the patched main.swift.

## behaviour that must not change
the GROUNDED bounds (frame0 anchor 10s, close_ms < 300) stay as they are; no harness behavior change beyond the two PROPOSED values moving to cited table rows.

## acceptance test (from the product repo)
python3 kits/bounds-table/check.py kits/bounds-table/bounds.json exits 0 with both rows cited; the negative-control row exits 1; the patched harness stays swiftc -parse clean.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/b-gate-tests/main.swift (sha256 28ff620c, lines 1-33 of 211)
```swift id=source1
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
```swift id=source2
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

```json id=fixtures1
{"schema":{"name":"str","value":"number","unit":"s|ms","kind":"hard-deadline|watchdog","citation":"public url","confidence":"low|medium|high"},"deliverableRows":["resume-after-pause landing","post-seek audio landing"],"negativeControl":{"row":{"name":"uncited example","value":5,"unit":"s","kind":"watchdog","citation":"","confidence":"low"},"expect":"check.py prints 'uncited example' and exits 1"}}
```
