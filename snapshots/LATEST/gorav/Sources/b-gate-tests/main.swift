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
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { fail("\(name) \(detail)") }
        print(String(format: "B-GATE check %@ t=+%.2fs %@", name, wall(), detail))
    }

    let log = EventLog()
    let s = GorAVEmbeddedSession(hostView: host, runID: "b-gate")
    s.onEvent = { ev in
        log.events.append(ev)
        print(String(format: "B-GATE event t=+%.2fs \(ev)", wall()))
        if case .failed(let token) = ev { fail("typed failure event: \(token)") }
    }

    func waitFor(_ desc: String, _ timeout: Double, _ cond: () async -> Bool) async -> Bool {
        let t0 = ContinuousClock.now
        while t0.duration(to: .now) < .seconds(timeout) {
            if await cond() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        print("B-GATE TIMEOUT waiting \(desc) after \(timeout)s")
        return false
    }

    // Open + frame0 anchor (10s, grounded).
    do { try await s.open(path: fixturePath) } catch { fail("open threw: \(error)") }
    guard await waitFor("first presented frame", 10, { (await s.snapshot().presentedFrames ?? 0) > 0 }) else {
        fail("B0 no presented frame within 10s of open")
    }
    let f0 = await s.snapshot()
    check("B0.first-frame-anchor", f0.anchorMediaSeconds != nil, "anchor=\(String(describing: f0.anchorMediaSeconds)) (FIRST live frame only; E1 continuity is a separate ops leg)")
    check("B0.first-audio-callbacks", (f0.audioCallbacks ?? 0) > 0, "callbacks=\(String(describing: f0.audioCallbacks)) (START only, not continuity)")

    // B1: pause at a logged wall time, hold, counter witnesses.
    print(String(format: "B-GATE B1 pause at t=+%.2fs hold=%.0fs", wall(), holdSeconds))
    do { try await s.setPaused(true) } catch { fail("B1 setPaused(true) threw: \(error)") }
    if !log.seen("paused") { fail("B1 no .paused event") }
    let p0 = await s.snapshot()
    try? await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
    let p1 = await s.snapshot()
    check("B1.no-eos", !log.seen("ended"), "(no .ended during hold)")
    check("B1.counters-present",
          p0.audioIntentionalSilenceFrames != nil && p1.audioIntentionalSilenceFrames != nil &&
          p0.audioNonSilenceFrames != nil && p1.audioNonSilenceFrames != nil &&
          p0.audioCallbacks != nil && p1.audioCallbacks != nil &&
          p0.presentedFrames != nil && p1.presentedFrames != nil,
          "counter witnesses must be NON-NIL on both pause samples (nil==nil equality is not a freeze witness)")
    check("B1.silence-advances",
          (p1.audioIntentionalSilenceFrames ?? 0) > (p0.audioIntentionalSilenceFrames ?? 0),
          "silence \(String(describing: p0.audioIntentionalSilenceFrames)) -> \(String(describing: p1.audioIntentionalSilenceFrames))")
    check("B1.callbacks-continue",
          (p1.audioCallbacks ?? 0) > (p0.audioCallbacks ?? 0),
          "callbacks \(String(describing: p0.audioCallbacks)) -> \(String(describing: p1.audioCallbacks))")
    check("B1.non-silence-frozen",
          p1.audioNonSilenceFrames == p0.audioNonSilenceFrames,
          "nonSilence=\(String(describing: p1.audioNonSilenceFrames))")
    check("B1.presentation-frozen", p1.presentedFrames == p0.presentedFrames,
          "presented=\(String(describing: p1.presentedFrames))")
    guard let t0p = p0.timePositionSeconds, let t1p = p1.timePositionSeconds else {
        fail("B1 time-pos witness missing: timePositionSeconds nil at a pause sample (nil==nil is not a freeze witness; absence FAILs per gate review)")
    }
    check("B1.time-pos-frozen", abs(t1p - t0p) <= 0.05, "timePos \(t0p) -> \(t1p) (PROPOSED tol 0.05s)")

    // Resume: non-silence resumes, presentation advances (5s, PROPOSED).
    do { try await s.setPaused(false) } catch { fail("B1 setPaused(false) threw: \(error)") }
    if !log.seen("resumed") { fail("B1 no .resumed event") }
    guard await waitFor("post-resume non-silence", BoundsTable.shared.seconds("resume-after-pause landing"), {
        (await s.snapshot().audioNonSilenceFrames ?? 0) > (p1.audioNonSilenceFrames ?? 0)
    }) else { fail("B1 non-silence did not resume within 5s (PROPOSED)") }
    guard await waitFor("post-resume presented advance", BoundsTable.shared.seconds("resume-after-pause landing"), {
        (await s.snapshot().presentedFrames ?? 0) > (p1.presentedFrames ?? 0)
    }) else { fail("B1 presented did not advance within 5s of resume (PROPOSED)") }
    check("B1.resume-landing", true, "non-silence + presented advancing after resume")

    // B2: parked seek - seek while paused, land on resume.
    do { try await s.setPaused(true) } catch { fail("B2 setPaused(true) threw: \(error)") }
    if !log.seen("paused") { fail("B2 no .paused event") }
    let preSeek = await s.snapshot()
    let landingCountBefore = preSeek.audioLandingFirstSampleSeconds.count
    let seeksBefore = preSeek.seekCommittedCount
    let eventsBefore = log.events.count
    do { try await s.seek(toSeconds: 2.0) } catch { fail("B2 parked seek(2.0) threw: \(error)") }
    guard let committed = log.seekCommittedPayload(), abs(committed - 2.0) < 1e-6 else {
        fail("B2 missing exact .seekCommitted(2.0)")
    }
    check("B2.seekCommitted", (await s.snapshot().seekCommittedCount) == seeksBefore + 1,
          "seeks \(seeksBefore) -> \(seeksBefore + 1)")
    do { try await s.setPaused(false) } catch { fail("B2 resume threw: \(error)") }
    // The immediate case is subsumed by waitFor's first poll; no `||` with an
    // async RHS (autoclosure cannot be async) and no stray closure parameter.
    guard await waitFor("post-seek frame0", 10, { log.events.dropFirst(eventsBefore).contains(.firstFrame) }) else {
        fail("B2 no post-seek frame0 within 10s (grounded bound)")
    }
    let anchorNow = await s.snapshot().anchorMediaSeconds
    guard let anchor = anchorNow, abs(anchor - 2.0) < 1.5 else {
        fail("B2 anchor did not re-arm at seek target (anchor=\(String(describing: anchorNow)))")
    }
    check("B2.frame0-anchor", true, "anchor=\(anchor)")
    guard await waitFor("post-seek audio landing", BoundsTable.shared.seconds("post-seek audio landing"), {
        (await s.snapshot().audioLandingFirstSampleSeconds).count > landingCountBefore
    }) else { fail("B2 no audio landing within 10s (PROPOSED, frame0 ground)") }
    let landings = await s.snapshot().audioLandingFirstSampleSeconds
    check("B2.audio-landing", true, "landings=\(landings)")

    // B3: close from paused state.
    do { try await s.setPaused(true) } catch { fail("B3 setPaused(true) threw: \(error)") }
    let report = await s.close()
    check("B3.close-under-300ms", report.closeMs < 300, String(format: "close_ms=%.1f (grounded < 300)", report.closeMs))
    check("B3.clean-shutdown", report.cleanShutdown, "typed shutdown via plane .closed")
    check("B3.counters-present",
          report.audioCallbacks != nil && report.audioIntentionalSilenceFrames != nil && report.audioNonSilenceFrames != nil,
          "callbacks=\(String(describing: report.audioCallbacks)) silence=\(String(describing: report.audioIntentionalSilenceFrames)) nonSilence=\(String(describing: report.audioNonSilenceFrames)) presented=\(String(describing: report.presentedFrames))")
    let second = await s.close()
    check("B3.second-close-typed-noop", second.reason == "alreadyClosed", "reason=\(second.reason)")

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
