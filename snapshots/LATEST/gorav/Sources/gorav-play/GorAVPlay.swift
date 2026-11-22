#if canImport(AppKit) && canImport(CoreAudio)
import AppKit
import Foundation
import GorAVMacShell
import GorAVPlaybackCore
#if canImport(Metal)
import GorAVMetalPresenter
#endif

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


// L12 parity binding (block 168, gdb gorav-play lane, 2026-11-01): the child
// process's FINAL decoded-frame counter, read back from the player's OWN
// heartbeat file ($GORAV_HB_FILE, per-run path, advanced by ShellFrameSource
// at the decoder's own emit points - every decoded frame writes
// synchronously, so the post-run value IS the final count). Loud in every
// case: hbBound=0 with the reason, never a silent inherit. Pure telemetry
// print - no playback behavior change, no new gate logic in the child.
func printChildDecodedBinding(leg: String, runID: String, launchedAt: Date) {
    guard let hbPath = ProcessInfo.processInfo.environment[DecodeHeartbeat.environmentVariable], !hbPath.isEmpty else {
        print("gorav play decoded: leg=\(leg) hbBound=0 hbNote=GORAV_HB_FILE-unset runID=\(runID)")
        return
    }
    // Freshness binding: the per-run contract (soak_runner substitutes
    // {run_id} into the path, proven at lanes/l13-soak/soak_runner.py) makes
    // cross-run collision impossible when the kit runner is the caller; this
    // mtime check closes the manual-invocation hole - a file last written
    // before THIS process launched can never be reported as this run's
    // counter. The file content stays a bare integer (the runner reads the
    // last numeric token); binding is by per-run path + freshness, never by
    // embedding run metadata in the counter file.
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: hbPath),
          let mtime = attrs[.modificationDate] as? Date, mtime >= launchedAt else {
        print("gorav play decoded: leg=\(leg) hbBound=0 hbNote=heartbeat-file-stale-or-missing-this-run runID=\(runID)")
        return
    }
    guard let raw = try? String(contentsOfFile: hbPath, encoding: .utf8),
          let v = UInt64(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        print("gorav play decoded: leg=\(leg) hbBound=0 hbNote=heartbeat-file-unparseable runID=\(runID)")
        return
    }
    print("gorav play decoded: leg=\(leg) childDecodedFrames=\(v) hbBound=1 runID=\(runID)")
}

@main
struct GorAVPlayMain {
    // app.delegate is weak; keep the delegate alive for the process lifetime.
    static let appDelegate = GorAVPlayAppDelegate()
    static func main() {
        let launchedAt = Date() // L12 freshness epoch for the child-bound decoded counter
        // Card 465 v1.1: unbuffered stdout so a crash (e.g. SIGSEGV) never
        // swallows telemetry already printed (v1's piped block buffering lost
        // every line of the crashed run).
        setbuf(stdout, nil)
        // L2 presenter landing (block 168 L3): --metal is stripped BEFORE
        // the positional grammar parse so PlayArguments (GorAVPlaybackCore)
        // needs no change; the flag only selects the presenter leg below.
        let metalFlag = CommandLine.arguments.contains("--metal")
        let args = CommandLine.arguments.filter { $0 != "--metal" }
        let parsed: PlayArguments
        do { parsed = try PlayArguments(args) }
        catch {
            FileHandle.standardError.write(Data("usage: gorav-play <avPath> [holdSeconds] [seekAtSeconds seekTargetSeconds] [pauseAtSeconds resumeAtSeconds] [closeAtSeconds]; negative pairs absent\n".utf8))
            Foundation.exit(2)
        }
        let clip = parsed.path, hold = parsed.holdSeconds
        // L2 presenter landing (block 168 L3): optional Metal presenter leg.
        // The DEFAULT path below is byte-identical to the pre-L3 behavior;
        // --metal routes the same clip through GorAVMetalShellApp (Metal
        // presenter + shared CancelCommit admission) and prints the typed
        // MetalRunReceipt fields instead of the MuxedSummary fields.
        let useMetal = metalFlag
#if !canImport(Metal)
        // Independent review F5: a --metal request on a build without the
        // Metal presenter leg is a TYPED REFUSAL, never a silent fallback
        // to the default software path.
        if useMetal {
            FileHandle.standardError.write(Data("GORAV_PLAY_REFUSED: --metal typed refusal: the Metal presenter leg is unavailable in this build (canImport(Metal) false); no silent fallback to the default path\n".utf8))
            Foundation.exit(2)
        }
#endif
        let controls = PlayControlPlan(pauseAtSeconds: parsed.pauseAtSeconds,
                                       resumeAtSeconds: parsed.resumeAtSeconds,
                                       closeAtSeconds: parsed.closeAtSeconds)
        let seekPlan = parsed.seekAtSeconds.flatMap { at in
            parsed.seekTargetSeconds.map { SeekProbePlan(atSeconds: at, targetSeconds: $0) }
        }
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        Task { @MainActor in
            #if canImport(Metal)
            if useMetal {
                let receipt: MetalRunReceipt
                do {
                    receipt = try await GorAVMetalShellApp.runMuxed(path: clip)
                } catch {
                    FileHandle.standardError.write(Data("GORAV_PLAY_ERROR: \(error)\n".utf8))
                    Foundation.exit(1)
                }
                let onScreen = MetalPresenterTelemetry.visibleUploads > 0
                print("gorav play: windowOnScreen=\(onScreen ? 1 : 0)")
                print("gorav play telemetry (metal): displayUploaded=\(MetalPresenterTelemetry.uploads) displayNoPixel=\(MetalPresenterTelemetry.noPixels) resizeEvents=\(MetalPresenterTelemetry.resizeEvents) drawableNilPresents=\(MetalPresenterTelemetry.drawableNilPresents) ticketedCommits=\(MetalPresenterTelemetry.ticketedCommits) ticketRefusals=\(MetalPresenterTelemetry.ticketRefusals) audioCallbackRealBytes=\(receipt.audioPushed)")
                print("gorav play receipt (metal): shown=\(receipt.shown) dropped=\(receipt.dropped) waits=\(receipt.waits) audioTerminal=\(receipt.audioTerminal) audioResidualAtStop=\(receipt.audioResidualAtStop) quiescenceResidual=\(receipt.quiescenceResidual)")
                printChildDecodedBinding(leg: "metal", runID: "-", launchedAt: launchedAt) // MetalRunReceipt types no runID; leg label carries the binding
                // A residual GPU quiescence or an audio terminal that is not
                // endOfStream is a LOUD failure, never a silent pass.
                if receipt.quiescenceResidual != 0 || receipt.audioTerminal.hasPrefix("failed") {
                    Foundation.exit(1)
                }
                let effectiveHold = MetalPresenterTelemetry.closedByUser ? 0.0 : hold
                if effectiveHold > 0 {
                    print("gorav play: playback finished, holding window \(Int(effectiveHold))s")
                    do { try await Task.sleep(nanoseconds: UInt64(effectiveHold * 1_000_000_000)) } catch { }
                }
                Foundation.exit(0)
            }
            #endif
            let summary: MuxedSummary
            do {
                summary = try await GorAVMacShellApp.runMuxed(path: clip, controls: controls, seekPlan: seekPlan)
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
            print("gorav play seek: attempted=\(summary.seekAttempted ? 1 : 0) outcome=\(summary.seekOutcome) audioOutcome=\(summary.seekAudioOutcome) audioNote=\(summary.seekAudioNote)")
            print("gorav play controls: pauses=\(summary.pauses) resumes=\(summary.resumes) pausedWallSeconds=\(summary.pausedWallSeconds) pauseOutcome=\(summary.pauseOutcome) resumeOutcome=\(summary.resumeOutcome) pausedSilenceFrames=\(summary.pausedSilenceFrames) clockSource=\(summary.clockSource) closedByUser=\(summary.closedByUser ? 1 : 0) endReason=\(summary.endReason)")
            let combinedSeekAccepted = PlaySeekAcceptance.accepts(attempted: summary.seekAttempted,
                video: summary.seekOutcome, audio: summary.seekAudioOutcome)
            print("gorav play seek acceptance: combinedSeekAccepted=\(combinedSeekAccepted ? 1 : 0)")
            printChildDecodedBinding(leg: "default", runID: summary.runID, launchedAt: launchedAt)
            if !combinedSeekAccepted || summary.pauseOutcome == "refused" || summary.resumeOutcome == "refused" || summary.clockSource == "masterLost" || summary.endReason == "decodeFailed" {
                Foundation.exit(1)
            }
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

