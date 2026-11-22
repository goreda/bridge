import AppKit
import GorAVEmbeddedShell

/// native104 D-stage app gate: the NORMAL AppDelegate lifecycle driven
/// end-to-end (the C stage's C0.scope gap: "isolated delegate, normal
/// AppDelegate lifecycle NOT_RUN"). Unlike --gorav-native-gate, main.swift
/// keeps AppDelegate() as the delegate; this driver only OBSERVES and
/// drives the normal path's own gorav host through the production host's
/// existing native87 gate surface. Media arrives through the normal argv
/// videoPath -> launchMPV -> PlayerBackendRoute path with GOR_ENGINE=gorav;
/// if the route does not take gorav, D1 FAILS with evidence (no silent mpv
/// fallback). Additive only: no AppDelegate/host behavior change, no owner
/// acceptance claim; venue/scanout is reported, never assumed.
// native107: the collector's stdout, captured at install BEFORE the normal
// path dup2s fd1/fd2 into gor-log-writer (AppDelegate.swift:463-464); every
// D line goes to this fd so the redirect cannot hide the driver (native105:
// zero post-dup2 lines reached the collector). nonisolated(unsafe): written
// once pre-run on the main thread, read by the MainActor driver + atexit.
nonisolated(unsafe) private var gDStageOutFD: Int32 = -1

@MainActor
final class GorAVAppGate: NSObject {
    private static var shared: GorAVAppGate?
    private weak var appDelegate: AppDelegate?
    private var failed = false
    private let started = ProcessInfo.processInfo.systemUptime

    static func install(appDelegate: AppDelegate) {
        gDStageOutFD = dup(STDOUT_FILENO)
        let g = GorAVAppGate(appDelegate: appDelegate)
        shared = g
        // D0 FIRST, at install (before app.run()), unconditionally: the first
        // venue run proved the didFinishLaunching-notification -> Task chain
        // is NOT guaranteed - the normal path's own quit machinery can
        // pre-empt it (quit watchdog _exit(70), AppDelegate.swift:3341) and
        // leave zero D lines. D0 emitted here survives every later outcome.
        let os = ProcessInfo.processInfo.operatingSystemVersion
        g.note("D0.scope", "normal AppDelegate lifecycle + production gorav engine route (argv videoPath -> launchMPV); GOR_ENGINE=gorav; no owner acceptance")
        g.note("D0.venue", "\(ProcessInfo.processInfo.environment["GOR_NATIVE_GATE_VENUE"] ?? "UNVERIFIED venue; scanout NOT_VERIFIED"); macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        // native107 earlier/more traces (observation only, no behavior):
        g.note("D0.argv", "args=\(CommandLine.arguments); videoCandidate=\(CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map { "\($0):\(FileManager.default.fileExists(atPath: $0))" })")
        let bid = Bundle.main.bundleIdentifier
        let others = bid.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
            .map { String($0.processIdentifier) } } ?? []
        g.note("D0.instances", "same-bundleID others at install=\(others); duplicate-arbitration exit(0) path AppDelegate.swift:405-428")
        atexit {
            guard gDStageOutFD >= 0 else { return }
            let msg = "{\"stage\":\"D\",\"check\":\"D0.atexit\",\"status\":\"PARTIAL\",\"evidence\":\"exit() path ran atexit; rules out _exit/signal kill\"}"
            msg.withCString { _ = Darwin.write(gDStageOutFD, $0, strlen($0)) }
            var nl: UInt8 = 10
            _ = Darwin.write(gDStageOutFD, &nl, 1)
        }
        NotificationCenter.default.addObserver(g, selector: #selector(launched),
                                               name: NSApplication.didFinishLaunchingNotification, object: nil)
        // Discriminates an AppKit terminate from a bare exit(): willTerminate
        // only fires on the former.
        NotificationCenter.default.addObserver(g, selector: #selector(terminating),
                                               name: NSApplication.willTerminateNotification, object: nil)
    }
    @objc private func terminating() {
        note("D0.will-terminate", "NSApplication.willTerminateNotification fired; AppKit terminate path taken")
    }
    private init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }

    private func line(_ check: String, _ ok: Bool, _ evidence: String) {
        if !ok { failed = true }
        emit(check, ok ? "PASS" : "FAIL", evidence)
    }
    private func note(_ check: String, _ evidence: String) { emit(check, "PARTIAL", evidence) }
    private func emit(_ check: String, _ status: String, _ evidence: String) {
        let row: [String: Any] = ["stage": "D", "check": check, "status": status,
            "evidence": evidence, "elapsed_s": ProcessInfo.processInfo.systemUptime - started]
        if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
            let out = gDStageOutFD >= 0 ? FileHandle(fileDescriptor: gDStageOutFD, closeOnDealloc: false) : FileHandle.standardOutput
            out.write(data); out.write(Data([10]))
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

    @objc private func launched() { Task { await run() } }

    private func run() async {
        // D0.scope/D0.venue were already emitted at install; this note proves
        // the notification -> driver chain itself was reached (its absence in
        // a future run means the normal lifecycle never handed over).
        note("D0.driver-enter", "didFinishLaunchingNotification observed on the normal AppDelegate lifecycle")
        // D1: the normal route must take the gorav engine on THIS fixture.
        note("D1.wait-begin", "initial goravSourceURL=\(String(describing: appDelegate?.goravSourceURL)) activePlayerEngine=\(appDelegate.map { String(describing: $0.activePlayerEngine) } ?? "nil")")
        var polls = 0
        let routed = await wait(30) {
            polls += 1
            if polls % 100 == 0 {
                self.note("D1.poll", "goravSourceURL=\(String(describing: self.appDelegate?.goravSourceURL)) activePlayerEngine=\(self.appDelegate.map { String(describing: $0.activePlayerEngine) } ?? "nil")")
            }
            return self.appDelegate?.goravSourceURL != nil
        }
        let engine = appDelegate.map { String(describing: $0.activePlayerEngine) } ?? "nil"
        line("D1.engine-route", routed && engine == "gorav", "goravSourceURL=\(String(describing: appDelegate?.goravSourceURL)) activePlayerEngine=\(engine); 30s route timeout")
        guard routed, let host = appDelegate?.goravHostForAppGate else { await finish(); return }
        line("D2.window-open", host.gateWindowVisible, "normal path's host NSWindow.isVisible")
        let opened = await wait(20) { (await host.gateSnapshot())?.anchorMediaSeconds != nil }
        line("D3.first-frame-anchor", opened, "actual EmbeddedSnapshot anchor via the normal path; 20s gate timeout")
        guard opened else { await finish(host: host); return }
        // D4: pause + resume through the normal path's own host controls.
        // native108: anchor+admission witness BEFORE the cycle. D3's
        // condition is the PUMP pace anchor; the session PlayheadTracker
        // binds on the 50ms first-frame watch (GorAVEmbeddedSession.swift
        // :1238-1252), and the audio pacing clock's first epoch value lands
        // on its own schedule. native111 correction: the nil-freeze
        // mechanism for native107 is NOT pinned from source. The typed
        // refusal route is textually verified end to end (AudioPacing.pause
        // guards the freeze value; AudioPacing.resume refuses while frozen;
        // the host prints every thrown refusal), and native111 F1 removes
        // the nil-freeze path entirely. But native107 captured NO refusal,
        // and absence of a captured refusal is not exclusion of the route.
        // The 0.7812 FAIL line is the tracker snapshot, not freezeValue
        // itself; an early-bind nil->finite race stays a candidate, not an
        // identified cause. The zero-trace anomaly stays OPEN. The witness
        // waits for the same surfaces D4 reads; original check
        // bounds/verdicts are unchanged and the added witnesses are bounded
        // (worst case ~7s more stage time).
        let anchored = await wait(5) {
            guard let s = await host.gateSnapshot() else { return false }
            // EmbeddedSnapshot.audioFirstAdmissionWallSeconds is a NON-optional
            // [Double] (GorAVEmbeddedSession.swift:129); native108 A1 compile
            // FAIL came from optional-chaining it. Intent unchanged: tracker
            // anchor bound AND first audio admission landed.
            return s.timePositionSeconds != nil && !s.audioFirstAdmissionWallSeconds.isEmpty
        }
        note("D4.anchor-witness", "timePos+audio-admission bound before the pause/resume cycle: \(anchored); 5s witness")
        await host.gatePauseAction()
        let paused = await wait(2) { (await host.gateSnapshot())?.isPaused == true }
        line("D4.pause-witness", paused, "isPaused==true after the host's pause control; 2s witness")
        await host.gatePauseAction()
        let resumed = await wait(2) { (await host.gateSnapshot())?.isPaused == false }
        let t0 = await host.gateSnapshot()?.timePositionSeconds
        await sleep(1.0)
        let t1 = await host.gateSnapshot()?.timePositionSeconds
        line("D4.resume-advance", resumed && t0 != nil && t1 != nil && t1! > t0!, "resumed=\(resumed) timePos \(String(describing: t0)) -> \(String(describing: t1)) after resume; 2s resume-applied witness")
        // native111: on failure, dump the session control trace (toggle
        // decisions + idempotent/refusal exits), mirroring C3's seekTrace
        // dump - native107's zero-trace signature must stay readable. The
        // condition is kept in De Morgan form so the gate test's pinned
        // conjunct text stays single-occurrence (mutant detectability).
        if !resumed || t0 == nil || t1 == nil || t1! <= t0! {
            for t in (await host.gateSnapshot())?.controlTrace ?? [] { note("D4.controlTrace", t) }
        }
        // D5: parked seek landing, same honest condition as C3 (10s bound).
        await host.gatePauseAction()
        _ = await wait(2) { (await host.gateSnapshot())?.isPaused == true }
        await host.gateSeekAction(seconds: 8)
        await host.gatePauseAction()
        var landed = false
        let landedOk = await wait(10) {
            guard let s = await host.gateSnapshot(), s.isPaused == false,
                  let time = s.timePositionSeconds, let anchor = s.anchorMediaSeconds else { return false }
            if time >= 8 && anchor >= 7.5 { landed = true }
            return landed
        }
        _ = landedOk
        line("D5.seek-landing", landed, "time>=8 && anchor>=7.5 after parked seek; 10s gate timeout (C3 parity)")
        // D6: scanout facts are OBSERVED, never claimed as verified.
        if let screen = host.window?.screen {
            note("D6.scanout", "screen=\(screen.localizedName) frame=\(NSStringFromRect(screen.frame)) colorSpace=\(String(describing: screen.colorSpace)) scale=\(screen.backingScaleFactor); placement OBSERVED, scanout verification NOT_RUN")
        } else {
            note("D6.scanout", "no NSScreen on host window; scanout NOT_VERIFIED")
        }
        await finish(host: host)
    }

    private func finish(host: GorAVPlayerHost? = nil) async {
        if let host {
            await host.gateCloseAction()
            let clean = host.gateCloseReport?.cleanShutdown == true
            line("D7.typed-close", clean, "closeMs=\(String(describing: host.gateCloseReport?.closeMs)) drainRemaining=\(String(describing: host.gateCloseReport?.audioDrainRemainingBytes)) cleanShutdown=\(clean)")
        }
        // Direct exit, no NSApp.terminate: the normal quit path arms a 6s
        // watchdog that Darwin._exit(70)s when its graceful sequence stalls
        // (AppDelegate.swift:3277/:3341), which would mask this gate's own
        // verdict and stdio state. Exercising the normal quit machinery is
        // explicitly NOT_RUN scope for this stage. Writes above are direct
        // fd writes, so nothing is lost by skipping the stdio-flushing exit.
        let out = gDStageOutFD >= 0 ? FileHandle(fileDescriptor: gDStageOutFD, closeOnDealloc: false) : FileHandle.standardOutput
        out.write(Data("[gorav-app-gate] \(failed ? "FAIL" : "PASS")\n".utf8))
        Foundation.exit(failed ? 1 : 0)
    }
}
