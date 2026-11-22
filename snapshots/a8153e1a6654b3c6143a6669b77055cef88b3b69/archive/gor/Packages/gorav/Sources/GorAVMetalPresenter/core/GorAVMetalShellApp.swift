// L2 presenter (block 78d), revision 3 (architect L2 r2 finding 6):
// muxed A/V entry on the Metal presenter path, mirroring
// GorAVMacShellApp.runMuxed with the SAME receipt field names.
// r3: BOTH decoders keep the v1.4 admission pin (the audio pin had been
// dropped - a regression); pin/open/audio-start all sit INSIDE the do so
// an early failure takes the structured cleanup path too; the catch AWAITS
// presenter close (quiescence) as well as decoder/audio teardown, on every
// error INCLUDING cancellation; open/start state is tracked by flags so
// partial starts clean up exactly what started; every receipt residual is
// CHECKED (a non-zero residual fails the F gate, never log-only).
// Decoders still open BEFORE audio.start (a failed open never leaves a
// running audio sink). AUTHORED NEW 2026-10-25, L2 lane.
// r8 port (block 168 L3 landing, against trunk d4c9d43): owner-issued
// session identity (PlaybackIdentityAuthority, S4 - no fixed-epoch
// fabrication; the audio leg SHARES the run's one session), a REAL shared
// CancelCommit authority wired through pump admissions AND the presenter
// upload fence (verdict S5 rev3/rev5), audio-master pacing attach
// (attachPacing + attachAudioMaster), failable AudioUnitSink init, and the
// cancellation-aware pacing wait (Bool onWait). KitAudioTelemetry is gone
// from the trunk; the receipt keeps the same field names.
#if canImport(AppKit) && canImport(CoreAudio) && canImport(Metal)
import AppKit
import GorAVCore
import GorAVPlaybackCore
import GorAVFFmpegAdapter
import GorAVMacShell

public struct MetalRunReceipt: Sendable {
    public var shown = 0, dropped = 0, waits = 0
    public var outOfOrderDrops = 0, nonFiniteDrops = 0
    public var digestsShown: [String] = []
    public var audioPushed = 0
    public var audioTerminal = ""
    public var audioResidualAtStop = 0
    public var audioOverrunDrops = 0
    public var audioUnderrunBytes = 0
    public var quiescenceResidual = -1
    public init() {}
}

/// Typed run error with the phase that failed (r2 finding 6: typed error
/// receipts, never an anonymous throw).
public enum MetalRunError: Error, Equatable {
    case videoPin(String)
    case videoOpen(String)
    case audioPin(String)
    case audioOpen(String)
    case audioStart(String)
    case playback(String)
    case cancelled
}

public enum GorAVMetalShellApp {
    /// Minimal JSON string escaping for the typed error receipt (r3 finding
    /// 8: interpolated raw errors could break the receipt format).
    private static func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }

    @MainActor public static func runMuxed(path: String) async throws -> MetalRunReceipt {
        var receipt = MetalRunReceipt()
        // S4 (current trunk): ONE owner-issued opaque identity per run,
        // issued BEFORE audio.start; the audio leg SHARES the run's session
        // (no second mint, no unchecked fixed-epoch fabrication).
        guard let session = PlaybackIdentityAuthority.shared.issue() else {
            throw MetalRunError.playback("identity authority exhausted (typed)")
        }
        // r3 S5 wiring (current trunk): one shared cancel/commit authority
        // governs pump show admissions AND the presenter upload fence; the
        // sink binds it at INIT - no mutable adoption surface (rev5).
        let commit = CancelCommit(sessionEpoch: session.epoch)
        let sink = try MetalPresenter(screenCheck: (), commit: commit)
        let root = (path as NSString).deletingLastPathComponent
        let decoder = FFmpegSoftwareDecoder()
        let adec = FFmpegSoftwareAudioDecoder()
        let ases = session
        guard let audio = AudioUnitSink() else {
            throw MetalRunError.audioStart("AudioUnitSink init refused (typed)")
        }
        var audioStarted = false
        var videoOpened = false
        var audioOpened = false
        do {
            // Admission: BOTH decoders pinned (v1.4 contract kept).
            do { try decoder.pinLocalRoots([root]) }
            catch { throw MetalRunError.videoPin("\(error)") }
            do { try adec.pinLocalRoots([root]) }
            catch { throw MetalRunError.audioPin("\(error)") }
            // Decoders open BEFORE the audio unit starts.
            do {
                try await decoder.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: session)
                videoOpened = true
            } catch { throw MetalRunError.videoOpen("\(error)") }
            _ = await decoder.nextEvent(session: session) // .opened
            print("gorav play-metal: video open ok (muxed admission passed)")
            do {
                try await adec.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: ases)
                audioOpened = true
            } catch { throw MetalRunError.audioOpen("\(error)") }
            print("gorav play-metal: audio open ok")
            // Audio-master pacing (current trunk shape): attach BEFORE
            // start so the render callback paces the host clock from the
            // first push; decoders still open first (r3 finding 6 kept).
            let clock = ShellClock()
            guard audio.attachPacing(hostClock: { clock.rawWallSeconds() }) else {
                throw MetalRunError.audioStart("audio pacing attach refused (typed)")
            }
            clock.attachAudioMaster(audio.pacingClock)
            defer { clock.attachAudioMaster(nil) }
            do {
                try audio.start()
                audioStarted = true
            } catch { throw MetalRunError.audioStart("\(error)") }

            let source = ShellFrameSource(decoder: decoder, session: session)
            // Cancellation is a real stop condition (r3 finding 8): a
            // cancelled run stops the pumps at the next frame, runs the
            // FULL cleanup + quiescence, then throws typed .cancelled.
            source.shouldStop = { @MainActor in
                sink.closedByUser || commit.isCancelled || Task.isCancelled
            }
            let pump = FramePump(source: source, sink: sink, clock: clock,
                                 commit: commit,
                                 closeRequested: { @MainActor in sink.closedByUser }) { seconds in
                // Cancellation-aware pacing wait (current trunk shape): the
                // sleep's CancellationError is REPORTED (false), never
                // swallowed.
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); return true }
                catch { return false }
            }
            let hbT0 = Date()
            let heartbeat = Task { @MainActor [weak audio] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let audio else { return }
                    print("gorav play-metal hb t=\(Int(Date().timeIntervalSince(hbT0)))s displayUploaded=\(MetalPresenterTelemetry.uploads) displayVisibleUploads=\(MetalPresenterTelemetry.visibleUploads) displayNoPixel=\(MetalPresenterTelemetry.noPixels) windowClosedByUser=\(MetalPresenterTelemetry.closedByUser ? 1 : 0) audioConsumed=\(audio.kitConsumedBytes) overrunDrops=\(audio.overrunDrops) underrunBytes=\(audio.underrunBytes) resizeEvents=\(MetalPresenterTelemetry.resizeEvents) drawableNilPresents=\(MetalPresenterTelemetry.drawableNilPresents)")
                }
            }
            defer { heartbeat.cancel() }
            async let audioOutcome = ShellAudioPump.runPaced(decoder: adec, session: ases, sink: audio, shouldStop: { @MainActor in sink.closedByUser || commit.isCancelled || Task.isCancelled })
            let stats = await pump.run()
            let outcome = await audioOutcome
            // Presenter close = bounded GPU quiescence BEFORE decoders/audio
            // teardown; the residual is CHECKED by the F gate, not log-only.
            receipt.quiescenceResidual = await sink.close()
            if audioOpened { await adec.close(session: ases) }
            if videoOpened { _ = await decoder.closeAndReport(session: session) }
            print("gorav play-metal: decoders closed")
            let drained = await audio.drainBounded(maxSeconds: 5.0).remaining
            audio.stop()
            audioStarted = false
            heartbeat.cancel()
            await heartbeat.value
            receipt.shown = stats.shown; receipt.dropped = stats.dropped; receipt.waits = stats.waits
            receipt.outOfOrderDrops = stats.outOfOrderDrops; receipt.nonFiniteDrops = stats.nonFiniteDrops
            receipt.digestsShown = stats.digestsShown
            receipt.audioPushed = outcome.pushed
            receipt.audioTerminal = "\(outcome.terminal)"
            receipt.audioResidualAtStop = drained
            receipt.audioOverrunDrops = audio.overrunDrops
            receipt.audioUnderrunBytes = audio.underrunBytes
            print("gorav play-metal: shown=\(stats.shown) dropped=\(stats.dropped) waits=\(stats.waits) outOfOrder=\(stats.outOfOrderDrops) audioPushed=\(outcome.pushed) terminal=\(outcome.terminal) audioResidualAtStop=\(drained) audioOverrunDrops=\(audio.overrunDrops) audioUnderrunBytes=\(audio.underrunBytes) windowClosedByUser=\(MetalPresenterTelemetry.closedByUser ? 1 : 0) resizeEvents=\(MetalPresenterTelemetry.resizeEvents) fullscreenEntries=\(MetalPresenterTelemetry.fullscreenEntries) fullscreenExits=\(MetalPresenterTelemetry.fullscreenExits) drawableNilPresents=\(MetalPresenterTelemetry.drawableNilPresents) quiescenceResidual=\(receipt.quiescenceResidual)")
            // Cancellation takes the TYPED error path only AFTER the full
            // cleanup + quiescence above has completed (witness: matrix T).
            if Task.isCancelled { throw MetalRunError.cancelled }
            return receipt
        } catch {
            // Structured cleanup on EVERY error including cancellation:
            // stop only what started, close what opened, and ALWAYS await
            // the presenter quiescence (r2 finding 6: the r2 catch never
            // awaited sink.close). Typed error receipt printed.
            let typed = (error as? MetalRunError) ?? (error is CancellationError ? .cancelled : .playback("\(error)"))
            print("{\"section\":\"runMuxed\",\"error\":\"\(jsonEscape("\(typed)"))\",\"audioStarted\":\(audioStarted),\"audioOpened\":\(audioOpened),\"videoOpened\":\(videoOpened)}")
            if audioStarted { audio.stop() }
            if audioOpened { await adec.close(session: ases) }
            if videoOpened { _ = await decoder.closeAndReport(session: session) }
            _ = await sink.close()
            throw typed
        }
    }
}
#endif
