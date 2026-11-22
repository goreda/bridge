// E1-SHAPES (arch-196v r2 item 2b/2c): the arch-196t r3 E1 gate on the
// generated real-media corpus (kits/e1-corpus), through the REAL product
// path - GorAVEmbeddedSession open -> demux -> decode -> present -> audio -
// not the lab MP4Demuxer/avcC harness (e1-headless-tests covers that shape).
// Scaffolding mirrors b-gate-tests (Task { @MainActor in } + venue-only
// NSWindow/NSView host + NSApplication.run per MetalCheck, see below); GorAVEmbeddedSession is @MainActor
// with init(hostView:runID:).
//
// Shapes (generated, no owner bytes):
//   e1-mkv-hevc10-dts.mkv   the owner's refusal shape
//   e1-mkv-h264-ac3.mkv
//   e1-mp4-h264-aac.mp4
//   e1-mkv-pgs.mkv          h264+aac+hdmv_pgs_subtitle
//
// Gate per shape (arch-196t r2 item 4c): frames presented > 240, real audio
// callbacks > 0, close < 300 ms. Requires the full-codec FFmpeg 7.1 provider
// (kits/ffmpeg-configure-diff/full-codec-provider-7.1{,-dav1d} recipes); with
// the codec-minimal provider the open refuses typed and the shape reports
// NOT_RUN (exit 2), never a guess.
//
// Usage:  swift run e1-shapes-tests <fixture> [timeoutSeconds]
// Driver: scripts/ci/e1-shapes.sh  (all 4 corpus shapes)
// Exit: 0 PASS, 1 FAIL, 2 NOT_RUN (typed, e.g. decoder missing / no Metal),
//       77 UNRUN (non-macOS).

import Foundation
import Dispatch
#if os(macOS)
import AppKit
import GorAVEmbeddedShell
import GorAVMetalPresenter   // diagnostics only: MetalPresenterTelemetry counters
import GorAVPlaybackCore     // diagnostics only: ObservationProperty reads
#endif

let UNRUN: Int32 = 77
let NOT_RUN: Int32 = 2

#if os(macOS)
// MetalCheck-proven CLI AppKit setup (Sources/GorAVMetalPresenter/cli/MetalCheck.swift):
// a CAMetalLayer-backed view in a window REQUIRES a real NSApplication event
// loop. dispatchMain() services the main dispatch queue only, so the display
// cycle's layer-tree build fires re-entrantly and traps with
// "NSViewIsCurrentlyBuildingLayerTreeForDisplay() != currentlyBuildingLayerTree"
// (NSView.m NSViewSetCurrentlyBuildingLayerTreeForDisplay) the moment the
// embedded presenter's layer attaches. app.run() services the runloop display
// cycle AND drains the main dispatch queue (MainActor jobs keep running).
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

let fixturePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let timeoutSeconds = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 45.0) : 45.0
guard !fixturePath.isEmpty else {
    print("E1-SHAPES NOT_RUN: usage e1-shapes-tests <fixture> [timeoutSeconds]")
    Foundation.exit(NOT_RUN)
}
guard FileManager.default.fileExists(atPath: fixturePath) else {
    print("E1-SHAPES NOT_RUN: missing fixture \(fixturePath)")
    Foundation.exit(NOT_RUN)
}
let shapeName = (fixturePath as NSString).lastPathComponent

Task { @MainActor in
    guard GorAVEmbeddedSession.probeAvailable() else {
        print("E1-SHAPES NOT_RUN \(shapeName): no Metal device (probeAvailable=false)")
        Foundation.exit(NOT_RUN)
    }

    // Venue-only drawable hosting, never product geometry (b-gate shape).
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 64, height: 64),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
    window.contentView = host

    final class Flags { var firstFrame = false; var ended: String?; var failed: String? }
    let flags = Flags()
    let gateStart = ProcessInfo.processInfo.systemUptime
    func wall() -> Double { ProcessInfo.processInfo.systemUptime - gateStart }
    let session = GorAVEmbeddedSession(hostView: host, runID: "e1-shapes")
    session.onEvent = { ev in
        print(String(format: "E1-SHAPES EVENT t=+%.2fs \(ev)", wall()))
        switch ev {
        case .firstFrame: flags.firstFrame = true
        case .ended(let r): flags.ended = r
        case .failed(let t): flags.failed = t
        default: break
        }
    }

    do {
        try await session.open(path: fixturePath)
    } catch {
        // A typed decoder/admission refusal on this host is NOT_RUN, not FAIL
        // (codec-minimal provider or missing decoder for the shape).
        print("E1-SHAPES NOT_RUN \(shapeName): open refused typed: \(GorAVEmbeddedSession.fallbackReason(for: error))")
        Foundation.exit(NOT_RUN)
    }

    let t0 = ContinuousClock.now
    var lastFrames = -1
    var stallPolls = 0
    // The audio legs are torn down by pumpDidFinish's cleanupLegs at EOF,
    // so audioCounters in the close report read nil->0 after a natural
    // ended(eof). The honest audio witness is the LIVE maximum seen while
    // the session was playing, captured here during polling.
    var maxAudioCallbacks: UInt64 = 0
    var maxNonSilence: UInt64 = 0
    // Same post-EOF caveat as audio: at natural EOF pumpDidFinish tears down
    // and close() returns early ("alreadyClosed") with NO snapshot, so
    // report.presentedFrames reads nil->0 even after a fully presented run
    // (Ops 10d875b PGS shape: shown=300 live, report frames=0). The honest
    // frames witness is the live maximum captured while polling.
    var maxFramesPresented = 0
    while flags.ended == nil && flags.failed == nil {
        if t0.duration(to: .now) > .seconds(timeoutSeconds) { break }
        try? await Task.sleep(nanoseconds: 250_000_000)
        let snap = await session.snapshot()
        let frames = snap.presentedFrames ?? 0
        if frames > maxFramesPresented { maxFramesPresented = frames }
        if let cb = snap.audioCallbacks, cb > maxAudioCallbacks { maxAudioCallbacks = cb }
        if let ns = snap.audioNonSilenceFrames, ns > maxNonSilence { maxNonSilence = ns }
        if frames == lastFrames { stallPolls += 1 } else { stallPolls = 0; lastFrames = frames }
        // EOF at the tail: presentation stalls while the ended event lands.
        if snap.eofReached && stallPolls > 8 { break }
    }
    // Race fix (Ops 4fb181d hevc10 cleanShutdown=false): on a zero-presentation
    // shape stallPolls is > 8 from the start, so the branch above can break
    // the moment terminalEndReason is set - BEFORE pumpDidFinish finishes
    // cleanupLegs and applies plane .closed. close() then early-returns
    // "alreadyClosed" with plane still .closing -> cleanShutdown=false even
    // though the session completes cleanly milliseconds later. The ended event
    // is emitted by pumpDidFinish AFTER plane .closed, so wait for it bounded.
    if flags.ended == nil && flags.failed == nil {
        let tWait = ContinuousClock.now
        while flags.ended == nil && flags.failed == nil && tWait.duration(to: .now) < .seconds(10) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    // Diagnostics (print-only): pre-close live snapshot + presenter refusal
    // counters, so a zero-progress native run names its own failure class.
    let pre = await session.snapshot()
    print(String(format: "E1-SHAPES DIAG t=+%.2fs snap: presented=%@ shown=%@ dropped=%@ waits=%@ endReason=%@ eof=%@ audioCB=%@ nonSilence=%@ pausedSilence=%@ maxAudioCB=%llu maxNonSilence=%llu maxFrames=%d hwdec=%@",
                 wall(),
                 pre.presentedFrames.map(String.init) ?? "nil",
                 pre.shown.map(String.init) ?? "nil",
                 pre.dropped.map(String.init) ?? "nil",
                 pre.waits.map(String.init) ?? "nil",
                 pre.pumpEndReason ?? "nil",
                 String(pre.eofReached),
                 pre.audioCallbacks.map(String.init) ?? "nil",
                 pre.audioNonSilenceFrames.map(String.init) ?? "nil",
                 pre.audioIntentionalSilenceFrames.map(String.init) ?? "nil", maxAudioCallbacks, maxNonSilence, maxFramesPresented,
                 String(describing: session.observations.read(.hwdecCurrent))))
    let report = await session.close()
    print("E1-SHAPES DIAG telemetry: uploads=\(MetalPresenterTelemetry.uploads) uploadRejections=\(MetalPresenterTelemetry.uploadRejections) ticketRefusals=\(MetalPresenterTelemetry.ticketRefusals) noPixels=\(MetalPresenterTelemetry.noPixels) drawableNilPresents=\(MetalPresenterTelemetry.drawableNilPresents) sequenceExhausted=\(MetalPresenterTelemetry.sequenceExhausted) visibleUploads=\(MetalPresenterTelemetry.visibleUploads) ticketedCommits=\(MetalPresenterTelemetry.ticketedCommits)")

    if let tok = flags.failed {
        print("E1-SHAPES FAIL \(shapeName): session failed token=\(tok)")
        Foundation.exit(1)
    }
    let frames = max(report.presentedFrames ?? 0, maxFramesPresented)
    let callbacks = max(report.audioCallbacks ?? 0, maxAudioCallbacks)
    var bad: [String] = []
    if !flags.firstFrame { bad.append("no firstFrame event") }
    if frames <= 240 { bad.append("frames=\(frames) <= 240") }
    if callbacks == 0 { bad.append("audioCallbacks=0") }
    if report.closeMs >= 300 { bad.append(String(format: "closeMs=%.1f >= 300", report.closeMs)) }
    if !report.cleanShutdown { bad.append("cleanShutdown=false") }
    if bad.isEmpty {
        print(String(format: "E1-SHAPES PASS %@ frames=%d audioCallbacks=%llu closeMs=%.1f eof=%@",
                     shapeName, frames, callbacks, report.closeMs, (report.eofReached || pre.eofReached) ? "true" : "false"))
        Foundation.exit(0)
    }
    print("E1-SHAPES FAIL \(shapeName): \(bad.joined(separator: "; "))")
    Foundation.exit(1)
}
app.run()
#else
print("E1-SHAPES UNRUN: macOS-only legs (real AudioUnit + Metal presenter session)")
Foundation.exit(UNRUN)
#endif
