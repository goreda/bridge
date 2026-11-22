import AppKit
import GorAVEmbeddedShell
import GorAVPlaybackCore

/// Explicit diagnostic venue in the real gor binary, not normal app startup.
/// Host controls and renderer are production code. No installed preferences,
/// event taps, mpv, camera helpers or default-engine changes are started here.
@MainActor
final class GorAVNativeGate: NSObject, NSApplicationDelegate {
    private var host: GorAVPlayerHost?
    private var failed = false
    private var events = 0
    private let started = ProcessInfo.processInfo.systemUptime
    private func line(_ check: String, _ ok: Bool, _ evidence: String) {
        if !ok { failed = true }
        let row: [String: Any] = ["stage": "C", "check": check,
            "status": ok ? "PASS" : "FAIL", "evidence": evidence,
            "elapsed_s": ProcessInfo.processInfo.systemUptime - started]
        if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        }
        events += 1
    }
    private func note(_ check: String, _ evidence: String) {
        let row = ["stage": "C", "check": check, "status": "PARTIAL", "evidence": evidence]
        if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        }
    }
    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    private func wait(_ seconds: Double, _ condition: () async -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        repeat { if await condition() { return true }; await sleep(0.05) }
        while ProcessInfo.processInfo.systemUptime < deadline
        return false
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await run() }
    }
    private func run() async {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--gorav-native-gate"), i + 1 < args.count,
              FileManager.default.fileExists(atPath: args[i + 1]) else {
            line("C0.local-fixture", false, "explicit existing local media required"); exit(2)
        }
        note("C0.scope", "real gor executable/NSApplication/host/session/UI-control path; isolated delegate, normal AppDelegate lifecycle NOT_RUN; no owner acceptance")
        note("C2.venue", ProcessInfo.processInfo.environment["GOR_NATIVE_GATE_VENUE"] ?? "UNVERIFIED venue; scanout NOT_VERIFIED")
        let h = GorAVPlayerHost(); host = h
        h.open(file: args[i + 1])
        line("C3.window-open", h.gateWindowVisible, "actual host NSWindow.isVisible")
        let opened = await wait(20) { (await h.gateSnapshot())?.anchorMediaSeconds != nil }
        line("C3.first-frame-anchor", opened, "actual EmbeddedSnapshot anchor; 20s gate timeout")
        guard opened else { await h.gateCloseAction(); exit(1) }
        await sleep(0.5)
        let beforePause = await h.gateSnapshot()
        line("C4.duration", (beforePause?.durationSeconds ?? 0) > 20, "fixture must exceed 20 seconds and contain audio/video")
        await h.gatePauseAction()
        let paused = await wait(2) { (await h.gateSnapshot())?.isPaused == true }
        line("C3.pause-control", paused, "same togglePause UI action -> session; 2s state timeout")
        await sleep(0.25)
        let freeze = await h.gateSnapshot()
        let holdStart = ProcessInfo.processInfo.systemUptime
        var frozen = freeze?.timePositionSeconds != nil
        var noEOS = true
        // Live counter witnesses (engine 2112af0d): every sampled field must be
        // present; a nil counter is a nil witness and FAILs, never passes.
        var sawLive = freeze?.presentedFrames != nil && freeze?.audioCallbacks != nil
            && freeze?.audioIntentionalSilenceFrames != nil && freeze?.audioNonSilenceFrames != nil
        var presentedFrozen = freeze?.presentedFrames != nil
        var nonSilenceFrozen = freeze?.audioNonSilenceFrames != nil
        var lastHold = freeze
        while ProcessInfo.processInfo.systemUptime - holdStart < 12 {
            let s = await h.gateSnapshot()
            if let a = freeze?.timePositionSeconds, let b = s?.timePositionSeconds {
                frozen = frozen && abs(a - b) <= 0.000001
            } else { frozen = false }
            noEOS = noEOS && h.gateObservation(.eofReached) == .bool(false) && h.gateTerminalCount == 0
                && s?.eofReached == false && s?.pumpEndReason == nil
            if let f = freeze, let s, let pf = f.presentedFrames, let ps = s.presentedFrames,
               let nf = f.audioNonSilenceFrames, let ns = s.audioNonSilenceFrames,
               s.audioCallbacks != nil, s.audioIntentionalSilenceFrames != nil {
                presentedFrozen = presentedFrozen && pf == ps
                nonSilenceFrozen = nonSilenceFrozen && nf == ns
            } else { sawLive = false; presentedFrozen = false; nonSilenceFrozen = false }
            if s != nil { lastHold = s }
            await sleep(0.1)
        }
        line("C3.pause12-time-frozen", frozen, "actual sampled time-pos; hold_s=\(ProcessInfo.processInfo.systemUptime - holdStart)")
        line("C3.pause12-no-eos", noEOS, "eof/pumpEnd sampled every100ms throughout12s")
        // Live AudioUnit/presentation diagnostics are mandatory. Pause contract:
        // presented + non-silence freeze while intentional silence advances and
        // render callbacks continue. A missing counter FAILs; it is never a
        // fabricated zero or a narrower PASS.
        let livePause: Bool = {
            guard sawLive, presentedFrozen, nonSilenceFrozen, let f = freeze, let l = lastHold,
                  let cb0 = f.audioCallbacks, let cb1 = l.audioCallbacks,
                  let si0 = f.audioIntentionalSilenceFrames, let si1 = l.audioIntentionalSilenceFrames
            else { return false }
            return cb1 > cb0 && si1 > si0
        }()
        line("C3.real-audio-and-presentation-pause", livePause,
             "actual pause-hold counters: presented=\(String(describing: freeze?.presentedFrames))->\(String(describing: lastHold?.presentedFrames)) frozen=\(presentedFrozen); nonSilence=\(String(describing: freeze?.audioNonSilenceFrames))->\(String(describing: lastHold?.audioNonSilenceFrames)) frozen=\(nonSilenceFrozen); intentionalSilence=\(String(describing: freeze?.audioIntentionalSilenceFrames))->\(String(describing: lastHold?.audioIntentionalSilenceFrames)) growing; callbacks=\(String(describing: freeze?.audioCallbacks))->\(String(describing: lastHold?.audioCallbacks)) growing; sawLive=\(sawLive)")
        let seekStart = ProcessInfo.processInfo.systemUptime
        await h.gateSeekAction(seconds: 8)
        let afterSeek = await h.gateSnapshot()
        let committed = (afterSeek?.seekTrace.count ?? 0) > (freeze?.seekTrace.count ?? 0) && afterSeek?.seekTrace.contains(where: { $0.contains("seekCommitted") }) == true
            && (afterSeek?.seekCommittedCount ?? 0) > (freeze?.seekCommittedCount ?? 0)
        line("C3.parked-seek-committed", committed, "actual UI seek action->session->engine; target8; seekTrace+seekCommittedCount \(String(describing: freeze?.seekCommittedCount))->\(String(describing: afterSeek?.seekCommittedCount)); elapsed_s=\(ProcessInfo.processInfo.systemUptime-seekStart)")
        await h.gatePauseAction()
        // native96 instrumentation (no behavior change; the 10s bound and
        // the pass condition are UNCHANGED): sample the landing wait every
        // ~2s so the log distinguishes decode catch-up progressing
        // (seekLandingDrops growing) from a presentation stall (flat).
        var resumed = false
        let resumeDeadline = ProcessInfo.processInfo.systemUptime + 10
        var nextSample = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime < resumeDeadline {
            if let s = await h.gateSnapshot(), s.isPaused == false,
               let time = s.timePositionSeconds, let anchor = s.anchorMediaSeconds,
               time >= 8 && anchor >= 7.5 { resumed = true; break }
            if ProcessInfo.processInfo.systemUptime >= nextSample {
                nextSample = ProcessInfo.processInfo.systemUptime + 2
                let s = await h.gateSnapshot()
                note("C3.resume-landing-sample", "presented=\(String(describing: s?.presentedFrames)) seekLandingDrops=\(String(describing: s?.seekLandingDrops)) lastDropPTS=\(String(describing: s?.seekLandingLastDropPTS)) fenced=\(String(describing: s?.seekLandingFencedShows)) admitNil=\(String(describing: s?.seekLandingFencedAdmitNil)) sinkFalse=\(String(describing: s?.seekLandingFencedSinkFalse)) lastDecPTS=\(String(describing: s?.seekLandingLastDecodedPTS)) maxDecPTS=\(String(describing: s?.seekLandingMaxDecodedPTS)) prerollSkipped=\(String(describing: s?.seekPrerollSkipped)) anchor=\(String(describing: s?.anchorMediaSeconds)) timePos=\(String(describing: s?.timePositionSeconds))")
            }
            await sleep(0.05)
        }
        line("C3.resume-landing-anchor", resumed, "actual live time-pos/pace anchor after parked seek;10s gate timeout")
        if !resumed {
            // native99 instrumentation (no bound/gate change): the B gate
            // dumps seekTrace on failure; mirror it here so the C failure
            // path shows the clock-stamped seek token order too. native100:
            // dump the landing counters too (goreda T2 blind spot) - refused
            // landing shows and the unbounded decoded-pts reach.
            if let s = await h.gateSnapshot() {
                note("C3.resume-landing-failobs", "presented=\(String(describing: s.presentedFrames)) seekLandingDrops=\(String(describing: s.seekLandingDrops)) lastDropPTS=\(String(describing: s.seekLandingLastDropPTS)) fenced=\(String(describing: s.seekLandingFencedShows)) admitNil=\(String(describing: s.seekLandingFencedAdmitNil)) sinkFalse=\(String(describing: s.seekLandingFencedSinkFalse)) lastDecPTS=\(String(describing: s.seekLandingLastDecodedPTS)) maxDecPTS=\(String(describing: s.seekLandingMaxDecodedPTS)) prerollSkipped=\(String(describing: s.seekPrerollSkipped)) pumpEnd=\(String(describing: s.pumpEndReason)) anchor=\(String(describing: s.anchorMediaSeconds)) timePos=\(String(describing: s.timePositionSeconds))")
                for t in s.seekTrace {
                    note("C3.resume-landing-seekTrace", t)
                }
            }
        }
        let snap = await h.gateSnapshot()
        let resumeCounters: Bool = {
            guard let s = snap, let f = freeze,
                  let sp = s.presentedFrames, let fp = f.presentedFrames,
                  let sn = s.audioNonSilenceFrames, let fn = f.audioNonSilenceFrames
            else { return false }
            return sp > fp && sn > fn
        }()
        line("C3.resume-live-counters", resumeCounters, "actual post-resume growth: presented=\(String(describing: freeze?.presentedFrames))->\(String(describing: snap?.presentedFrames)); nonSilence=\(String(describing: freeze?.audioNonSilenceFrames))->\(String(describing: snap?.audioNonSilenceFrames)); nil witness=FAIL")
        line("C3.audio-landing", (snap?.audioLandingFirstSampleSeconds.count ?? 0) > (freeze?.audioLandingFirstSampleSeconds.count ?? 0), "actual session audio admission samples")
        line("C3.no-control-refusal", h.gateFailureCount == 0, "host typed failure count=\(h.gateFailureCount)")
        for p: ObservationProperty in [.timePos, .duration, .pause, .eofReached, .idleActive, .metadata, .mediaTitle, .hwdecCurrent] {
            let value = h.gateObservation(p)
            line("C4." + p.rawValue, value != nil && value != ObservationValue.none, "actual observation=\(String(describing: value))")
        }
        note("C4.known-open", "width/height/video-params/dwidth/dheight/fps/frame-drop surface not accepted by this gate")
        await h.gatePauseAction()
        let closeStart = ProcessInfo.processInfo.systemUptime
        await h.gateCloseAction()
        let closeMS = (ProcessInfo.processInfo.systemUptime - closeStart) * 1000
        // Typed engine close report (2112af0d): measured closeMs + cleanShutdown
        // + pre-close counters. A missing report is a nil witness: FAIL.
        let report = h.gateCloseReport
        let typedClose: Bool = {
            guard let r = report else { return false }
            return r.reason == "close" && r.cleanShutdown && r.closeMs < 300
                && r.presentedFrames != nil && r.audioCallbacks != nil
        }()
        line("C3.close-from-paused", typedClose, "typed EmbeddedCloseReport reason=\(report?.reason ?? "missing") closeMs=\(String(describing: report?.closeMs)) cleanShutdown=\(report?.cleanShutdown == true) presented=\(String(describing: report?.presentedFrames)) callbacks=\(String(describing: report?.audioCallbacks)) intentionalSilence=\(String(describing: report?.audioIntentionalSilenceFrames)) nonSilence=\(String(describing: report?.audioNonSilenceFrames)) eof=\(report?.eofReached == true); hostAwaitedMs=\(closeMS); bound<300")
        line("C.summary", !failed, "checks=\(events); PARTIAL venue/app-lifecycle scope remains even when checks pass")
        exit(failed ? 1 : 0)
    }
}
