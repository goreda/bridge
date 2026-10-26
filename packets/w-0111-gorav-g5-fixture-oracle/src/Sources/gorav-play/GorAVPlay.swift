#if canImport(AppKit) && canImport(CoreAudio)
import AppKit
import Foundation
import GorAVMacShell

// gorav-play: real-clip playback entry point (card 465, 2026-10-25).
// Plays ONE bundled muxed A/V clip (mov: mpeg4 video + pcm_s16le audio)
// through the real GorAVMacShellApp path: FFmpeg software decode ->
// NSWindow display sink + AudioUnit default-output sink, never NullSink.
// Explicit NSApp.run() runloop on the main thread; async playback on a Task
// (same shape as gorav-sink-check; no top-level statements in either branch).
// Native compilation and runtime were not performed before authoring:
// any compile error here is reported by the kit into the result file.
/// v1.1: minimal standard app lifecycle. v1 ran a bare NSApplication with
/// no delegate; the v1 crash (.ips) was a message to a deallocated object
/// from CoreFoundation inside NSApplication.run. A delegate puts AppKit on
/// its standard paths; closing the window must not quit mid-playback.
final class GorAVPlayAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct GorAVPlayMain {
    // app.delegate is weak; keep the delegate alive for the process lifetime.
    static let appDelegate = GorAVPlayAppDelegate()
    static func main() {
        // Card 465 v1.1: unbuffered stdout so a crash (e.g. SIGSEGV) never
        // swallows telemetry already printed (v1's piped block buffering lost
        // every line of the crashed run).
        setbuf(stdout, nil)
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: gorav-play <avPath> [holdSeconds] [seekAtSeconds seekTargetSeconds]\n".utf8))
            Foundation.exit(2)
        }
        let clip = args[1]
        let hold: Double = (args.count >= 3 ? Double(args[2]) : nil) ?? 4.0
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        Task { @MainActor in
            let summary: MuxedSummary
            do {
                if args.count >= 5, let seekAt = Double(args[3]), let seekTarget = Double(args[4]) {
                    summary = try await GorAVMacShellApp.runMuxedSeekProbe(path: clip,
                        plan: SeekProbePlan(atSeconds: seekAt, targetSeconds: seekTarget))
                } else {
                    summary = try await GorAVMacShellApp.runMuxed(path: clip)
                }
            } catch {
                FileHandle.standardError.write(Data("GORAV_PLAY_ERROR: \(error)\n".utf8))
                Foundation.exit(1)
            }
            // L1 v2 (finding 7/8): every verdict input comes from the TYPED
            // summary value - no global telemetry, no cross-run inheritance.
            let onScreen = summary.visibleUploads > 0
            print("gorav play: windowOnScreen=\(onScreen ? 1 : 0)")
            print("gorav play telemetry: displayUploaded=\(summary.uploads) displayNoPixel=\(summary.noPixels) audioCallbackRealBytes=\(summary.audioConsumedBytes)")
            // Finding 7: an incomplete/unwritable ledger or a failed
            // admission bound can never back a PASS; said LOUDLY so the kit
            // predicate sees it even if every other metric looks green.
            print("gorav play integrity: ledgerAllowsSuccess=\(summary.ledgerAllowsSuccess ? 1 : 0) ledgerWriteOK=\(summary.ledgerWriteOK ? 1 : 0) admissionBound=\(summary.admissionBoundHolds ? 1 : 0) audioFailedStops=\(summary.audioFailedStops) runID=\(summary.runID)")
            print("gorav play seek: attempted=\(summary.seekAttempted ? 1 : 0) outcome=\(summary.seekOutcome) audioNote=\(summary.seekAudioNote)")
            let effectiveHold = summary.closedByUser ? 0.0 : hold
            if effectiveHold > 0 {
                print("gorav play: playback finished, holding window \(Int(effectiveHold))s")
                do { try await Task.sleep(nanoseconds: UInt64(effectiveHold * 1_000_000_000)) } catch { }
            }
            Foundation.exit(0)
        }
        app.run()
    }
}
#else
import Foundation
@main
struct GorAVPlayUnsupportedMain {
    static func main() {
        setbuf(stdout, nil)
        print("gorav-play: real display/audio sinks require macOS (AppKit/CoreAudio); unsupported on this host")
        Foundation.exit(3)
    }
}
#endif
