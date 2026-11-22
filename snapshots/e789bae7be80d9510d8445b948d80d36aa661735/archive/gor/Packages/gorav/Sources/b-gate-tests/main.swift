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
//   audio landing 10 s    CITED (kits/bounds-table/bounds.json "post-seek audio landing", low confidence)
//   resume landing 5 s    CITED (kits/bounds-table/bounds.json "resume-after-pause landing", low confidence)
//   hold default 12 s     GROUNDED shape: STATUS.md arch-195b V2 "pause 12s /
//                         no EOS" (overridable: argv[2]).
//   time-pos freeze tol   PROPOSED 0.05 s across the hold.
//
// Exit codes: 0 pass, 1 fail (BAD line naming the witness), 2 NOT_RUN
// (missing fixture / no Metal), 77 UNRUN (non-macOS).
// Usage: b-gate-tests <clip-path> [holdSeconds]

import Foundation
import Dispatch
#if os(macOS)
import AppKit
import GorAVEmbeddedShell
import GorAVPlaybackCore
#endif

let UNRUN: Int32 = 77
let NOT_RUN: Int32 = 2
func fail(_ msg: String) -> Never { print("B-GATE BAD: \(msg)"); Foundation.exit(1) }

#if os(macOS)
// Same AppKit display-cycle requirement as e1-shapes (MetalCheck-proven):
// a CAMetalLayer-backed view in a window needs a real NSApplication event
// loop; dispatchMain() traps re-entrantly in NSViewSetCurrentlyBuildingLayerTree-
// ForDisplay once the embedded presenter attaches a layer after a successful open.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
let fixturePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures/e1-h264-aac-10s.mp4"
let holdSeconds = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 12.0) : 12.0
guard FileManager.default.fileExists(atPath: fixturePath) else {
    print("B-GATE NOT_RUN: missing fixture \(fixturePath)")
    Foundation.exit(NOT_RUN)
}

Task { @MainActor in
    guard GorAVEmbeddedSession.probeAvailable() else {
        print("B-GATE NOT_RUN: no Metal device on this host (probeAvailable=false)")
        Foundation.exit(NOT_RUN)
    }

    final class EventLog {
        var events: [EmbeddedEvent] = []
        func seen(_ needle: String) -> Bool { events.contains { "\($0)".hasPrefix(needle) } }
        func seekCommittedPayload() -> Double? {
            for ev in events { if case .seekCommitted(let secs) = ev { return secs } }
            return nil
        }
    }

    // Venue-only drawable hosting, never product geometry (session-venue shape).
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 64, height: 64),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
    window.contentView = host

    let gateStart = ProcessInfo.processInfo.systemUptime
    func wall() -> Double { ProcessInfo.processInfo.systemUptime - gateStart }
    func check(_ name: String, _ ok: Bool, _ detail: String = "") async {
        if !ok { await failObserved("\(name) \(detail)") }
        print(String(format: "B-GATE check %@ t=+%.2fs %@", name, wall(), detail))
    }

    let log = EventLog()
    // native96r2: declared BEFORE the onEvent closure - a closure captures
    // only what is already declared (A1 compile error b7393eb5).
    var lastSnapshot: EmbeddedSnapshot?
    var waitSamples: [String] = []
    // native102: the last close report, so FAIL-OBS can dump the drain
    // result + leg timings even when a close CHECK fails.
    var lastCloseReportForObs: EmbeddedCloseReport?
    let s = GorAVEmbeddedSession(hostView: host, runID: "b-gate")
    s.onEvent = { ev in
        log.events.append(ev)
        print(String(format: "B-GATE event t=+%.2fs \(ev)", wall()))
        if case .failed(let token) = ev { Task { await failObserved("typed failure event: \(token)") } }
    }

    // native96r2 (local overlay vs upstream 2112af0d; instrumentation only,
    // no bound or gate change): failure-path observation. waitFor samples the
    // session snapshot (~1s cadence + a final timeout sample) into
    // waitSamples; failObserved dumps the samples, the landing-drop counter
    // and seekTrace before exiting so a B-stage failure distinguishes decode
    // catch-up (drops growing) from a presentation stall (flat). Pass paths
    // and all bounds are unchanged.
    func refreshSnapshot(_ branch: String) async {
        let snap = await s.snapshot()
        lastSnapshot = snap
        // native100: fenced/admitNil/sinkFalse + unbounded last/max decoded
        // pts (goreda T2 blind spot: refused landing shows are invisible to
        // presented/drops alone).
        waitSamples.append(String(format: "branch=%@ t=+%.2fs generation=%u anchor=%@ presented=%@ seekLandingDrops=%@ lastDropPTS=%@ fenced=%@ admitNil=%@ sinkFalse=%@ lastDecPTS=%@ maxDecPTS=%@ prerollSkipped=%@ timePos=%@",
            branch, wall(), snap.generation, String(describing: snap.anchorMediaSeconds),
            String(describing: snap.presentedFrames), String(describing: snap.seekLandingDrops),
            String(describing: snap.seekLandingLastDropPTS), String(describing: snap.seekLandingFencedShows),
            String(describing: snap.seekLandingFencedAdmitNil), String(describing: snap.seekLandingFencedSinkFalse),
            String(describing: snap.seekLandingLastDecodedPTS), String(describing: snap.seekLandingMaxDecodedPTS),
            String(describing: snap.seekPrerollSkipped), String(describing: snap.timePositionSeconds)))
    }
    // native101r3 (goreda T2): take a FRESH snapshot at failure time - the
    // terminal counters (pumpEnd, prerollSkipped) live on the pump end
    // which postdates the last periodic sample; the cached lastSnapshot
    // printed them as their pre-failure values (native100 showed
    // prerollSkipped=0 at a pump:-9 that happened mid-skip).
    func failObserved(_ msg: String) async -> Never {
        print("B-GATE FAIL-OBS samples=\(waitSamples.count)")
        for line in waitSamples { print("B-GATE FAIL-OBS sample \(line)") }
        if let snap = await s.snapshot() ?? lastSnapshot {
            print("B-GATE FAIL-OBS generation=\(snap.generation) anchor=\(String(describing: snap.anchorMediaSeconds)) presented=\(String(describing: snap.presentedFrames)) seekLandingDrops=\(String(describing: snap.seekLandingDrops)) lastDropPTS=\(String(describing: snap.seekLandingLastDropPTS)) fenced=\(String(describing: snap.seekLandingFencedShows)) admitNil=\(String(describing: snap.seekLandingFencedAdmitNil)) sinkFalse=\(String(describing: snap.seekLandingFencedSinkFalse)) lastDecPTS=\(String(describing: snap.seekLandingLastDecodedPTS)) maxDecPTS=\(String(describing: snap.seekLandingMaxDecodedPTS)) prerollSkipped=\(String(describing: snap.seekPrerollSkipped)) pumpEnd=\(String(describing: snap.pumpEndReason))")
            if let cr = lastCloseReportForObs {
                print("B-GATE FAIL-OBS close reason=\(cr.reason) ringAtRequest=\(String(describing: cr.audioRingBytesAtRequest)) drainStart=\(String(describing: cr.audioDrainStartBytes)) drainRemaining=\(String(describing: cr.audioDrainRemainingBytes)) drainCancelled=\(String(describing: cr.audioDrainCancelled)) taskAwaitMs=\(String(describing: cr.taskAwaitMs)) presenterDecoderCloseMs=\(String(describing: cr.presenterDecoderCloseMs)) drainMs=\(String(describing: cr.audioDrainMs)) stopMs=\(String(describing: cr.audioStopMs))")
            }
            for t in snap.seekTrace { print("B-GATE FAIL-OBS seekTrace \(t)") }
        } else {
            print("B-GATE FAIL-OBS no snapshot captured")
        }
        fail(msg)
    }

    func waitFor(_ desc: String, _ timeout: Double, _ cond: () async -> Bool) async -> Bool {
        let t0 = ContinuousClock.now
        var nextSample = 0.0
        while t0.duration(to: .now) < .seconds(timeout) {
            if await cond() { return true }
            if wall() >= nextSample {
                nextSample = wall() + 1.0
                await refreshSnapshot(desc)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        await refreshSnapshot(desc + ":timeout")
        print("B-GATE TIMEOUT waiting \(desc) after \(timeout)s")
        return false
    }

    // Open + frame0 anchor (10s, grounded).
    do { try await s.open(path: fixturePath) } catch { fail("open threw: \(error)") }
    guard await waitFor("first presented frame", 10, { (await s.snapshot().presentedFrames ?? 0) > 0 }) else {
        await failObserved("B0 no presented frame within 10s of open")
    }
    let f0 = await s.snapshot()
    await check("B0.first-frame-anchor", f0.anchorMediaSeconds != nil, "anchor=\(String(describing: f0.anchorMediaSeconds)) (FIRST live frame only; E1 continuity is a separate ops leg)")
    await check("B0.first-audio-callbacks", (f0.audioCallbacks ?? 0) > 0, "callbacks=\(String(describing: f0.audioCallbacks)) (START only, not continuity)")

    // Sequencing variant (native93): the B1 time-pos witness needs the
    // tracker's committed firstFrame anchor, so the wait is on
    // snapshot().timePositionSeconds (tracker.read) - NOT on the pump's
    // anchorMediaSeconds. B0's presented-frame wait can complete one watch
    // poll (50 ms) before acceptFirstFrame commits it, leaving
    // timePositionSeconds legitimately nil at p0 (native92 B1 time-pos
    // FAIL). Bounded wait on the same grounded 10s frame0/anchor bound;
    // absence stays a FAIL with its own reason - never an invented 0,
    // never an accepted nil.
    guard await waitFor("committed firstFrame time-pos witness", 10, { (await s.snapshot().timePositionSeconds) != nil }) else {
        await failObserved("B1.pre-pause time-pos witness not committed within 10s (grounded frame0/anchor bound)")
    }

    // B1: pause at a logged wall time, hold, counter witnesses.
    print(String(format: "B-GATE B1 pause at t=+%.2fs hold=%.0fs", wall(), holdSeconds))
    do { try await s.setPaused(true) } catch { await failObserved("B1 setPaused(true) threw: \(error)") }
    if !log.seen("paused") { await failObserved("B1 no .paused event") }
    let p0 = await s.snapshot()
    try? await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
    let p1 = await s.snapshot()
    // native91 T1 observability: the full B1 pause samples logged BEFORE any
    // fail-fast check, so a BAD line never hides the counter values. No
    // check, bound or exit code changes.
    print("B-GATE B1 p0 callbacks=\(String(describing: p0.audioCallbacks)) silence=\(String(describing: p0.audioIntentionalSilenceFrames)) nonSilence=\(String(describing: p0.audioNonSilenceFrames)) presented=\(String(describing: p0.presentedFrames)) timePos=\(String(describing: p0.timePositionSeconds))")
    print("B-GATE B1 p1 callbacks=\(String(describing: p1.audioCallbacks)) silence=\(String(describing: p1.audioIntentionalSilenceFrames)) nonSilence=\(String(describing: p1.audioNonSilenceFrames)) presented=\(String(describing: p1.presentedFrames)) timePos=\(String(describing: p1.timePositionSeconds))")
    await check("B1.no-eos", !log.seen("ended"), "(no .ended during hold)")
    await check("B1.counters-present",
          p0.audioIntentionalSilenceFrames != nil && p1.audioIntentionalSilenceFrames != nil &&
          p0.audioNonSilenceFrames != nil && p1.audioNonSilenceFrames != nil &&
          p0.audioCallbacks != nil && p1.audioCallbacks != nil &&
          p0.presentedFrames != nil && p1.presentedFrames != nil,
          "counter witnesses must be NON-NIL on both pause samples (nil==nil equality is not a freeze witness)")
    await check("B1.silence-advances",
          (p1.audioIntentionalSilenceFrames ?? 0) > (p0.audioIntentionalSilenceFrames ?? 0),
          "silence \(String(describing: p0.audioIntentionalSilenceFrames)) -> \(String(describing: p1.audioIntentionalSilenceFrames))")
    await check("B1.callbacks-continue",
          (p1.audioCallbacks ?? 0) > (p0.audioCallbacks ?? 0),
          "callbacks \(String(describing: p0.audioCallbacks)) -> \(String(describing: p1.audioCallbacks))")
    await check("B1.non-silence-frozen",
          p1.audioNonSilenceFrames == p0.audioNonSilenceFrames,
          "nonSilence=\(String(describing: p1.audioNonSilenceFrames))")
    await check("B1.presentation-frozen", p1.presentedFrames == p0.presentedFrames,
          "presented=\(String(describing: p1.presentedFrames))")
    guard let t0p = p0.timePositionSeconds, let t1p = p1.timePositionSeconds else {
        await failObserved("B1 time-pos witness missing: timePositionSeconds nil at a pause sample (nil==nil is not a freeze witness; absence FAILs per gate review)")
    }
    await check("B1.time-pos-frozen", abs(t1p - t0p) <= 0.05, "timePos \(t0p) -> \(t1p) (PROPOSED tol 0.05s)")

    // Resume: non-silence resumes, presentation advances (5s, PROPOSED).
    do { try await s.setPaused(false) } catch { await failObserved("B1 setPaused(false) threw: \(error)") }
    if !log.seen("resumed") { await failObserved("B1 no .resumed event") }
    guard await waitFor("post-resume non-silence", BoundsTable.shared.seconds("resume-after-pause landing"), {
        (await s.snapshot().audioNonSilenceFrames ?? 0) > (p1.audioNonSilenceFrames ?? 0)
    }) else { await failObserved("B1 non-silence did not resume within 5s (PROPOSED)") }
    guard await waitFor("post-resume presented advance", BoundsTable.shared.seconds("resume-after-pause landing"), {
        (await s.snapshot().presentedFrames ?? 0) > (p1.presentedFrames ?? 0)
    }) else { await failObserved("B1 presented did not advance within 5s of resume (PROPOSED)") }
    await check("B1.resume-landing", true, "non-silence + presented advancing after resume")

    // B2: parked seek - seek while paused, land on resume.
    do { try await s.setPaused(true) } catch { await failObserved("B2 setPaused(true) threw: \(error)") }
    if !log.seen("paused") { await failObserved("B2 no .paused event") }
    let preSeek = await s.snapshot()
    let landingCountBefore = preSeek.audioLandingFirstSampleSeconds.count
    let seeksBefore = preSeek.seekCommittedCount
    let eventsBefore = log.events.count
    do { try await s.seek(toSeconds: 2.0) } catch { await failObserved("B2 parked seek(2.0) threw: \(error)") }
    guard let committed = log.seekCommittedPayload(), abs(committed - 2.0) < 1e-6 else {
        await failObserved("B2 missing exact .seekCommitted(2.0)")
    }
    await check("B2.seekCommitted", (await s.snapshot().seekCommittedCount) == seeksBefore + 1,
          "seeks \(seeksBefore) -> \(seeksBefore + 1)")
    do { try await s.setPaused(false) } catch { await failObserved("B2 resume threw: \(error)") }
    // The immediate case is subsumed by waitFor's first poll; no `||` with an
    // async RHS (autoclosure cannot be async) and no stray closure parameter.
    guard await waitFor("post-seek frame0", 10, { log.events.dropFirst(eventsBefore).contains(.firstFrame) }) else {
        await failObserved("B2 no post-seek frame0 within 10s (grounded bound)")
    }
    let anchorNow = await s.snapshot().anchorMediaSeconds
    guard let anchor = anchorNow, abs(anchor - 2.0) < 1.5 else {
        await failObserved("B2 anchor did not re-arm at seek target (anchor=\(String(describing: anchorNow)))")
    }
    await check("B2.frame0-anchor", true, "anchor=\(anchor)")
    guard await waitFor("post-seek audio landing", BoundsTable.shared.seconds("post-seek audio landing"), {
        (await s.snapshot().audioLandingFirstSampleSeconds).count > landingCountBefore
    }) else { await failObserved("B2 no audio landing within 10s (PROPOSED, frame0 ground)") }
    let landings = await s.snapshot().audioLandingFirstSampleSeconds
    await check("B2.audio-landing", true, "landings=\(landings)")

    // B3: close from paused state.
    do { try await s.setPaused(true) } catch { await failObserved("B3 setPaused(true) threw: \(error)") }
    let report = await s.close()
    lastCloseReportForObs = report   // native102: FAIL-OBS visibility
    // native102 (observation only, goreda T2): the drain result + per-leg
    // close timings. A close from PAUSED holds the ring quiesced (silence
    // without consumption), so drainRemaining > 0 for the full 5s bound is
    // the typed expectation, not a hang - the fields make it measurable.
    print(String(format: "B-GATE B3 close-obs ringAtRequest=%@ drainStart=%@ drainRemaining=%@ drainCancelled=%@ taskAwaitMs=%@ presenterDecoderCloseMs=%@ drainMs=%@ stopMs=%@",
        String(describing: report.audioRingBytesAtRequest), String(describing: report.audioDrainStartBytes),
        String(describing: report.audioDrainRemainingBytes), String(describing: report.audioDrainCancelled),
        String(describing: report.taskAwaitMs), String(describing: report.presenterDecoderCloseMs),
        String(describing: report.audioDrainMs), String(describing: report.audioStopMs)))
    await check("B3.close-under-300ms", report.closeMs < 300, String(format: "close_ms=%.1f (grounded < 300)", report.closeMs))
    await check("B3.clean-shutdown", report.cleanShutdown, "typed shutdown via plane .closed")
    await check("B3.counters-present",
          report.audioCallbacks != nil && report.audioIntentionalSilenceFrames != nil && report.audioNonSilenceFrames != nil,
          "callbacks=\(String(describing: report.audioCallbacks)) silence=\(String(describing: report.audioIntentionalSilenceFrames)) nonSilence=\(String(describing: report.audioNonSilenceFrames)) presented=\(String(describing: report.presentedFrames))")
    let second = await s.close()
    await check("B3.second-close-typed-noop", second.reason == "alreadyClosed", "reason=\(second.reason)")

    print(String(format: "B-GATE PASS hold=%.0fs close_ms=%.1f callbacks=%llu silence=%llu nonSilence=%llu presented=%ld t=+%.2fs",
                 holdSeconds, report.closeMs, report.audioCallbacks ?? 0,
                 report.audioIntentionalSilenceFrames ?? 0, report.audioNonSilenceFrames ?? 0,
                 report.presentedFrames ?? 0, wall()))
    Foundation.exit(0)
}
app.run()
#else
print("B-GATE UNRUN: macOS-only legs (real AudioUnit + Metal presenter session)")
Foundation.exit(UNRUN)
#endif
