#if canImport(AppKit) && canImport(CoreAudio)
import Foundation
import QuartzCore
import GorAVCore
import GorAVPlaybackCore
import GorAVFFmpegAdapter
import GorAVNativeProbeKit
import GorAVSeekComposition

/// Wraps FFmpegSoftwareDecoder as the shell's FrameSource: pulls decoded
/// frames, converts yuv420p planes (via framePlaneCopy, the K6 shell seam)
/// to RGBA PixelPayload, and hands the pump pts/digest/pixels. Audio is
/// pushed into AudioUnitSink as PCM arrives from FFmpegSoftwareAudioDecoder.
/// Probe scope: yuv420p video + pcm_s16le stereo 44.1kHz audio.
public final class ShellFrameSource: QueuedFrameSource, @unchecked Sendable {
    /// Verdict S5 rev6: TYPED seek-barrier receipt - FAIL CLOSED.
    /// The ACTUAL provider flush lives in the DECODER lane
    /// (FFmpegSoftwareDecoder.seek does av_seek_frame +
    /// avcodec_flush_buffers + pending-packet drop), but that lane
    /// exposes no post-seek BARRIER/flush-verification API this source
    /// can attest a receipt from. Until the decoder lane exposes one
    /// (e.g. `seekBarrier(revision:) async -> SeekBarrierOutcome`
    /// attesting the flush+queue-drop completed), this source canNOT
    /// truthfully report `.flushed` - and the rev6 contract forbids a
    /// documented no-op. `.unsupported` makes FramePump.resetPresentation
    /// a typed seek refusal: NO completion ACK without a real barrier.
    /// M2 (S5 shell integration, opt-in): truthful `.flushed` ONLY when a ShellSeekBridge is
    /// attached AND its current fence binding anchors an ACTUAL committed seek receipt that was
    /// validated against the provider's current binding (source identity + session + revision).
    /// The binding is replaced by every subsequent commit and cleared on poison, so a stale
    /// receipt cannot be reused. SCOPE: this attests the VIDEO source path only (native cleanup
    /// + origin-tagged delivery + consumer fence below). The AUDIO ring (ShellAudioPump ->
    /// AudioUnitSink SPSC) has NO seek flush today: pre-seek PCM already in the ring is NOT
    /// covered by this receipt - that gap is declared, not hidden (M4 follow-up).
    /// Default stays fail-closed `.unsupported` (baseline unchanged when no bridge attached).
    public func coordinateSeek(revision: UInt64) async -> SeekBarrierOutcome {
        // Call-time binding check, not anchor presence: the fence must STILL match the
        // provider's actual current binding (source identity + session + revision).
        guard let bridge = seekBridge, bridge.fenceMatchesProvider(decoder) else { return .unsupported }
        return .flushed
    }
    /// M1/M3 attach point: when set, the video path switches to the ENVELOPED event channel
    /// (coordinated mode; legacy nextEvent(session:) would make tryBegin refuse legacyRejected)
    /// and every delivered frame is fenced by origin identity+session+revision. Rejected frames
    /// are released EXACTLY ONCE. When nil the legacy path runs byte-identically (baseline).
    public var seekBridge: ShellSeekBridge?
    /// M1: enveloped pull loop (bridge attached). Same mapping as the legacy path below,
    /// plus the origin fence: any event whose origin is not admitted by the bridge's current
    /// binding is DROPPED and its handle released exactly once - a pre-seek retained or
    /// delayed frame can never reach the pump after a committed seek.
    private func nextEventEnveloped(bridge: ShellSeekBridge) async -> SourceEvent {
        while true {
            let ev = await decoder.nextEvent()
            switch ev {
            case .opened: continue
            case .frameDecoded(let origin, let f):
                guard let fence = bridge.currentFence, fence.admits(origin) else {
                    await decoder.releaseFrame(handle: f.handle, session: session) // exactly once
                    continue
                }
                guard let pts = f.pts else {
                    await decoder.releaseFrame(handle: f.handle, session: session)
                    continue
                }
                let digest = await decoder.frameDigest(handle: f.handle, session: session) ?? "nil"
                var payload: PixelPayload?
                if let copy = await decoder.framePlaneCopy(handle: f.handle, session: session),
                   copy.format == "yuv420p", copy.planes.count == 3 {
                    let rgba = copy.planes[0].withUnsafeBufferPointer { yb -> [UInt8] in
                        copy.planes[1].withUnsafeBufferPointer { ub in
                            copy.planes[2].withUnsafeBufferPointer { vb in
                                YUV420Converter.rgbaFromYUV420p(
                                    y: yb.baseAddress!, yStride: copy.width,
                                    u: ub.baseAddress!, uStride: (copy.width + 1) >> 1,
                                    v: vb.baseAddress!, vStride: (copy.width + 1) >> 1,
                                    width: copy.width, height: copy.height)
                            }
                        }
                    }
                    payload = PixelPayload(width: copy.width, height: copy.height, bytes: rgba)
                }
                await decoder.releaseFrame(handle: f.handle, session: session)
                return .frame(SourceFrame(ptsSeconds: Double(pts) / timeBaseDen, durationSeconds: frameDuration,
                                   digest: digest, pixelPayload: payload))
            case .endOfStream: endState = .endOfStream; return .ended(.endOfStream)
            case .failed(let origin, let code, _):
                _ = origin; endState = .decodeFailed; return .failed(code)
            case .closed: endState = .interrupted; return .ended(.sourceEnded)
            case .interrupted: endState = .interrupted; return .ended(.sourceEnded)
            case .drained, .feedSaturated: continue
            }
        }
    }
    private let decoder: FFmpegSoftwareDecoder
    private let session: SessionID
    private let timeBaseDen: Double
    private let frameDuration: Double
    /// v1.1: external stop signal (e.g. user closed the window). Checked once
    /// per frame pull; returning true ends the source stream cleanly (nil).
    public var shouldStop: (@Sendable () async -> Bool)?
    /// Typed end state (finding 5): WHY the frame stream ended. runMuxed
    /// derives the video end reason from THIS, never a fabricated EOS.
    public enum EndState: String, Sendable, Equatable { case running, endOfStream, decodeFailed, stopped, interrupted }
    public private(set) var endState: EndState = .running
    /// S5 (architect full verdict): timeBaseDen / frameDuration HARDCODED
    /// defaults are CONTRACT-BLOCKED values - the real producer rational
    /// (stream time_base + per-frame duration) arrives via the L3 v4.4 /
    /// L4 r8 seam AFTER independent reproduction + integration, not from
    /// constants. Any timing claim computed from the defaults is marked
    /// provisional in the ledger; do not treat as producer truth.
    public init(decoder: FFmpegSoftwareDecoder, session: SessionID, timeBaseDen: Double = 12800, frameDuration: Double = 0.04) {
        self.decoder = decoder; self.session = session; self.timeBaseDen = timeBaseDen
        self.frameDuration = frameDuration
    }
    public func nextEvent() async -> SourceEvent {
        // S3 typed source states. Close intent maps to .ended and stays
        // distinguishable via endState (S4: close is preserved separately).
        if let stop = shouldStop, await stop() { endState = .stopped; return .ended(.sourceEnded) }
        if let bridge = seekBridge { return await nextEventEnveloped(bridge: bridge) }
        while let ev = await decoder.nextEvent(session: session) {
            switch ev {
            case .frameDecoded(let f):
                guard let pts = f.pts else {
                    // S5: release on EVERY path BEFORE a skip (handle leak).
                    await decoder.releaseFrame(handle: f.handle, session: session)
                    continue
                }
                let digest = await decoder.frameDigest(handle: f.handle, session: session) ?? "nil"
                var payload: PixelPayload?
                if let copy = await decoder.framePlaneCopy(handle: f.handle, session: session),
                   copy.format == "yuv420p", copy.planes.count == 3 {
                    let rgba = copy.planes[0].withUnsafeBufferPointer { yb -> [UInt8] in
                        copy.planes[1].withUnsafeBufferPointer { ub in
                            copy.planes[2].withUnsafeBufferPointer { vb in
                                YUV420Converter.rgbaFromYUV420p(
                                    y: yb.baseAddress!, yStride: copy.width,
                                    u: ub.baseAddress!, uStride: (copy.width + 1) >> 1,
                                    v: vb.baseAddress!, vStride: (copy.width + 1) >> 1,
                                    width: copy.width, height: copy.height)
                            }
                        }
                    }
                    payload = PixelPayload(width: copy.width, height: copy.height, bytes: rgba)
                }
                await decoder.releaseFrame(handle: f.handle, session: session)
                return .frame(SourceFrame(ptsSeconds: Double(pts) / timeBaseDen, durationSeconds: frameDuration,
                                   digest: digest, pixelPayload: payload))
            case .endOfStream: endState = .endOfStream; return .ended(.endOfStream)
            case .failed(let code, _): endState = .decodeFailed; return .failed(code)
            default: continue
            }
        }
        endState = .interrupted
        return .ended(.sourceEnded)
    }
}

// MARK: - M3: contract seek wiring (additive; baseline runMuxed unchanged)

extension FFmpegSoftwareDecoder: CoreSeekProvider {}

/// M3 (S5 shell integration): the shell seek entry point. Drives ONE contract seek through
/// the bridge and, ONLY on committedFlushed, publishes the SINGLE core-authority revision
/// bump via pump.resetPresentation() (the bridge's commitACK here is a ledger note only -
/// NO second bump anywhere). Revision spaces stay explicit: the pump admits under its own
/// CancelCommit counter; the frame fence uses the bridge's PROVIDER-space binding - the two
/// never mix numerals.
/// Recovery is TYPED, not a ledger note: committedButPumpRefused means the provider advanced
/// but the pump did not - playback MUST NOT resume (close, or an explicit caller re-sync with
/// a fresh resetPresentation attempt; the bridge fence remains valid at the new revision so a
/// retry is safe, but nothing resumes implicitly). The provider arrives as the existential:
/// the FFmpegSoftwareDecoder: CoreSeekProvider conformance is declared ONCE by the composing
/// executable (gorav-play), never inside a library module.
@discardableResult
public func shellPerformSeek(bridge: ShellSeekBridge, provider: any CoreSeekProvider,
                             pump: FramePump, position: RationalTime,
                             ledger: TimingLedger? = nil,
                             ledgerSession: UInt64 = 0, ledgerGeneration: UInt64 = 0,
                             seekAnchorSeconds: Double? = nil) async -> ShellSeekWiringOutcome {
    let result = await bridge.seek(on: provider, position: position) { _, _ in
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump, subsystem: .video,
                       kind: .presentationReset, note: "seekCommitAck:no-bump-here")
    }
    switch result {
    case .committedFlushed(let receipt, _):
        if await pump.resetPresentation(seekAnchorSeconds: seekAnchorSeconds) { return .committedAndReset(receipt: receipt) }
        // CONTROL-PATH fail-closed: admissions/uploads stop NOW, before any further pump
        // activity - a ledger note alone would let stale output escape until teardown.
        await pump.prohibitResumeAfterSeekFailure()
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump, subsystem: .video,
                       kind: .presentationReset, note: "seekBarrierRefusedAfterCommit:resume-prohibited")
        return .committedButPumpRefused(receipt: receipt)
    case .noMutationCoreGated, .admissionRefused:
        return .noChange
    case .requiresClose(let receipt):
        await pump.prohibitResumeAfterSeekFailure()
        return .requiresClose(receipt: receipt)
    }
}

extension AudioUnitSink: AudioSinkControlling {}

/// Audio pump: pulls decoded PCM from the audio adapter and feeds the
/// sink's ring. Runs as a sibling Task beside the video pump; the SPSC ring
/// is the only shared state.
public enum ShellAudioPump {
    /// (team2 OBS-3 / K4 r2 terminal-semantics rule) a failed audio decode
    /// is NOT a clean EOS: the terminal state is surfaced, not collapsed.
    /// L1 v2 (finding 6): cancelled is its OWN terminal - a swallowed
    /// CancellationError must never reappear as EOS.
    public enum Terminal: Equatable, Sendable { case endOfStream, failed(Int), sourceEnded, stoppedEarly, cancelled }
    public static func coreKind(of t: Terminal) -> AudioTerminalKind {
        switch t {
        case .endOfStream: return .endOfStream
        case .failed: return .failed
        case .sourceEnded: return .sourceEnded
        case .stoppedEarly: return .stoppedEarly
        case .cancelled: return .cancelled
        }
    }
    public struct Outcome: Equatable, Sendable { public let pushed: Int; public let terminal: Terminal }
    public static func run(decoder: FFmpegSoftwareAudioDecoder, session: SessionID,
                           sink: any AudioSink) async -> Outcome {
        var pushed = 0
        while let ev = await decoder.nextEvent(session: session) {
            switch ev {
            case .pcm(let f): sink.push(f.bytes); pushed += f.bytes.count
            case .endOfStream: return Outcome(pushed: pushed, terminal: .endOfStream)
            case .failed(let code, _): return Outcome(pushed: pushed, terminal: .failed(code))
            default: continue
            }
        }
        return Outcome(pushed: pushed, terminal: .sourceEnded)
    }

    /// Cancellation-aware wait (finding 6): NOT try?-swallowed. Returns
    /// false when the task was cancelled mid-wait.
    private static func waitNanos(_ ns: UInt64) async -> Bool {
        do { try await Task.sleep(nanoseconds: ns); return true }
        catch is CancellationError { return false }
        catch { return true } // clock errors are not cancellation; keep pacing
    }

    /// Card 465 (2026-10-25): paced variant for real-length clips. Gates
    /// pushes on a ring watermark so the live AudioUnit render callback
    /// drains in real time and the producer waits. The watermark bounds the
    /// AUDIO QUEUE DEPTH ONLY. It is NOT an A/V skew bound: there is no
    /// shared playhead, no overshoot record, no audio-master clock feedback;
    /// audio-master sync remains NOT_IMPLEMENTED in the core
    /// (SyncMaster.audioNotImplemented). Any skew claim is FALSE here.
    /// Landing telemetry of the first post-seek bound PCM envelope (M4):
    /// the MEASURED late-start gap is preserved - no fake exact landing.
    public static func runPaced(decoder: FFmpegSoftwareAudioDecoder, session: SessionID,
                                sink: AudioUnitSink, highWaterBytes: Int = 88200,
                                ledger: TimingLedger? = nil, ledgerSession: UInt64 = 0,
                                shouldStop: (@Sendable () async -> Bool)? = nil) async -> Outcome {
        let generation = sink.currentGeneration
        func term(_ kind: Terminal, code: Int = 0) -> Outcome {
            if case .failed = kind {
                ledger?.append(session: ledgerSession, generation: generation, segment: .pump,
                               subsystem: .audio, kind: .decodeError, bytes: code)
            }
            ledger?.append(session: ledgerSession, generation: generation, segment: .pump,
                           subsystem: .audio, kind: .terminal,
                           note: Self.coreKind(of: kind).rawValue)
            return Outcome(pushed: 0, terminal: kind) // pushed replaced below
        }
        var pushed = 0
        func termP(_ kind: Terminal, code: Int = 0) -> Outcome {
            var o = term(kind, code: code); o = Outcome(pushed: pushed, terminal: o.terminal); return o
        }
        if Task.isCancelled { return termP(.cancelled) }
        if let stop = shouldStop, await stop() { return termP(.stoppedEarly) }
        while let ev = await decoder.nextEvent(session: session) {
            switch ev {
            case .pcm(let f):
                while sink.available > highWaterBytes {
                    if Task.isCancelled { return termP(.cancelled) }
                    if let stop = shouldStop, await stop() { return termP(.stoppedEarly) }
                    // Finding 6: cancellation-aware sleep; the old try?
                    // form swallowed the cancel and could busy-spin.
                    let paced = await waitNanos(10_000_000)
                    if !paced { return termP(.cancelled) }
                }
                sink.push(f.bytes); pushed += f.bytes.count
            case .endOfStream: return termP(.endOfStream)
            case .failed(let code, _): return termP(.failed(code), code: code)
            default: continue
            }
            if let stop = shouldStop, await stop() { return termP(.stoppedEarly) }
        }
        return termP(.sourceEnded)
    }
}

/// Typed run summary (finding 7/8): the run's verdict-relevant facts travel
/// as a VALUE from runMuxed to the entry point - never re-parsed from
/// global mutable telemetry, and never inherited across runs.
public struct MuxedSummary: Sendable, Equatable {
    public var shown = 0, dropped = 0, waits = 0, fencedShows = 0
    public var audioPushed = 0
    public var terminal = "none"
    public var audioResidualAtStop = -1
    public var audioOverrunDrops = 0
    public var audioUnderrunBytes = 0
    public var audioConsumedBytes = 0
    public var closedByUser = false
    public var endReason = "none"
    public var ledgerEvents = 0
    public var ledgerAllowsSuccess = false
    public var ledgerWriteOK = false
    public var admissionBoundHolds = false
    public var uploads = 0, visibleUploads = 0, noPixels = 0, fenceSkips = 0
    public var audioStopCalls = 0, audioDisposeCount = 0, audioFailedStops = 0, audioStaleFenced = 0
    public var runID = ""
    // Seek-probe telemetry (all "none"/false on the baseline path).
    public var seekAttempted = false
    public var seekOutcome = "none"        // committedAndReset|committedButPumpRefusedClosed|noChange|requiresCloseClosed|attachFailed
    public var seekAudioNote = "none"      // audio-reposition-gap declared when a seek ran
    public var seekAudioOutcome = "none"   // M4: nativeReady/closeRequired/refused/ringResetRefused - NOT firstPCM/coreACK
}

/// Seek-probe plan for runMuxedSeekProbe (Mac evidence gathering for the contract seek
/// path; NOT a product seek UI). Audio truth: the audio leg has NO reposition API, so
/// post-seek audio continues from its own stale position and is REPORTED as such -
/// never fed to an A/V claim.
public struct SeekProbePlan: Sendable, Equatable {
    public var atSeconds: Double
    public var targetSeconds: Double
    /// M4: audio seek correlation (peer refuses 0); distinct from any video queue turn.
    public var correlation: UInt64
    public init(atSeconds: Double, targetSeconds: Double, correlation: UInt64 = 1) {
        self.atSeconds = atSeconds; self.targetSeconds = targetSeconds; self.correlation = correlation
    }
}

/// App glue: window + display sink + audio sink + pump, real clock.
public enum GorAVMacShellApp {
    /// Card 465 (2026-10-25): muxed A/V entry - ONE container with sibling
    /// video and audio streams (bounded profile: mov family + one admitted
    /// video codec + one pcm_s16le audio stream; see DemuxerPolicy).
    /// L1 v2: returns a typed MuxedSummary; PLAYBACK_PASS gating lives in
    /// the entry point and REQUIRES ledgerAllowsSuccess && ledgerWriteOK &&
    /// admissionBoundHolds (finding 7: overflow or a lost ledger can never
    /// back a PASS).
    @MainActor @discardableResult
    public static func runMuxed(path: String) async throws -> MuxedSummary {
        var summary = MuxedSummary()
        // Explicit run identity (finding 7/8): the kit exports GORAV_RUN_ID
        // and GORAV_WORK; the ledger header carries both and the ledger file
        // lands at an EXPLICIT path, never a CWD-relative guess.
        let env = ProcessInfo.processInfo.environment
        let runID = env["GORAV_RUN_ID"] ?? "norunid"
        summary.runID = runID
        let cwd = FileManager.default.currentDirectoryPath
        let ledger = TimingLedger(capacity: 8192, clock: { CACurrentMediaTime() }, runID: runID, cwd: cwd,
                              nonce: env["GORAV_NONCE"] ?? "")
        ledger.append(session: 0, generation: 1, segment: .open, subsystem: .core,
                      kind: .ledgerOrigin, note: "gorav-play-v1.4+l1v2")
        guard let audio = AudioUnitSink() else { throw NSError(domain: "gorav.shell", code: 90, userInfo: [NSLocalizedDescriptionKey: "AudioUnitSink bring-up refused (C cells)"]) }
        audio.ledger = ledger
        // Structured cleanup (finding 5): EVERY throw after a successful
        // audio.start() still drains + stops the sink - a decoder-open
        // failure must never leak a retained, running unit.
        var audioStarted = false
        var audioProducerStarted = false
        do {
            try await runMuxedBody(path: path, audio: audio, ledger: ledger, summary: &summary,
                                   audioStarted: &audioStarted, audioProducerStarted: &audioProducerStarted)
        } catch {
            if audioStarted {
                // S2 caller fix: a throw BEFORE the producer task existed
                // must declare .absent - stop() on a .pending witness is a
                // bounded retained fault, and an open failure is NOT one.
                if !audioProducerStarted {
                    audio.producerNotExpected(generation: audio.currentGeneration)
                }
                audio.drainRTTransitions(segment: .teardown)
                audio.stop()
                audio.drainRTTransitions(segment: .teardown)
            }
            throw error
        }
        return summary
    }

    /// Seek-probe entry: identical structure to runMuxed with the contract seek path wired
    /// (enveloped open, bridge attach, one mid-playback seek). Baseline runMuxed is unchanged.
    @MainActor @discardableResult
    public static func runMuxedSeekProbe(path: String, plan: SeekProbePlan) async throws -> MuxedSummary {
        var summary = MuxedSummary()
        let env = ProcessInfo.processInfo.environment
        let runID = env["GORAV_RUN_ID"] ?? "norunid"
        summary.runID = runID
        let cwd = FileManager.default.currentDirectoryPath
        let ledger = TimingLedger(capacity: 8192, clock: { CACurrentMediaTime() }, runID: runID, cwd: cwd,
                              nonce: env["GORAV_NONCE"] ?? "")
        ledger.append(session: 0, generation: 1, segment: .open, subsystem: .core,
                      kind: .ledgerOrigin, note: "gorav-play-seekprobe-v1")
        guard let audio = AudioUnitSink() else { throw NSError(domain: "gorav.shell", code: 90, userInfo: [NSLocalizedDescriptionKey: "AudioUnitSink bring-up refused (C cells)"]) }
        audio.ledger = ledger
        var audioStarted = false
        var audioProducerStarted = false
        do {
            try await runMuxedBody(path: path, audio: audio, ledger: ledger, summary: &summary,
                                   audioStarted: &audioStarted, audioProducerStarted: &audioProducerStarted,
                                   seekProbe: plan)
        } catch {
            if audioStarted {
                if !audioProducerStarted { audio.producerNotExpected(generation: audio.currentGeneration) }
                audio.drainRTTransitions(segment: .teardown)
                audio.stop()
                audio.drainRTTransitions(segment: .teardown)
            }
            throw error
        }
        return summary
    }

    @MainActor
    private static func runMuxedBody(path: String, audio: AudioUnitSink, ledger: TimingLedger,
                                     summary: inout MuxedSummary, audioStarted: inout Bool,
                                     audioProducerStarted: inout Bool,
                                     seekProbe: SeekProbePlan? = nil) async throws {
        let env = ProcessInfo.processInfo.environment
        let runID = env["GORAV_RUN_ID"] ?? "norunid"
        // S4: owner-issued opaque identity (fixed epoch had NO authority).
        // Verdict S5 rev5 IDENTITY ORDER: the session is issued BEFORE
        // audio.start - no start/ledger record can carry a default-0
        // session; display / pump / audio all carry the run's one epoch,
        // and the shared commit authority is bound to the same run.
        guard let session = PlaybackIdentityAuthority.shared.issue() else { throw NSError(domain: "gorav.shell", code: 91, userInfo: [NSLocalizedDescriptionKey: "identity authority exhausted (typed)"]) }
        audio.ledgerSession = session.epoch
        try audio.start()
        audioStarted = true
        let audioGeneration = audio.currentGeneration
        let root = (path as NSString).deletingLastPathComponent
        // v4 (full-review): STRUCTURED decoder cleanup. Every throw after a
        // decoder open closes BOTH decoders (each close attempted, statuses
        // recorded) before propagating; audio.stop() is handled by the
        // caller's do/catch. No unit/decoder is ever left open by a throw.
        var decoderOpened = false
        var adecOpened = false
        let decoder = FFmpegSoftwareDecoder()
        let adec = FFmpegSoftwareAudioDecoder()
        let ases = session   // S4: the audio leg SHARES the run's one owner-issued identity - no second mint
        do {
        try decoder.pinLocalRoots([root])
        try await decoder.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: session)
        decoderOpened = true
        if seekProbe != nil {
            _ = await decoder.nextEvent()   // enveloped: legacy pull would claim legacy and refuse tryBegin
        } else {
            _ = await decoder.nextEvent(session: session) // .opened (baseline path, unchanged)
        }
        print("gorav play: video open ok (muxed admission passed)")
        try adec.pinLocalRoots([root])
        try await adec.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: ases)
        adecOpened = true
        print("gorav play: audio open ok")
        // r3 S5 WIRING (peer rev1): the shared cancel/commit authority is
        // REAL here - one cell governs pump show admissions AND the
        // display upload fence (no more nil-commit fallback in the shell).
        // Verdict S5 rev5: the sink binds its authority at INIT - no
        // mutable adoption surface exists.
        let commit = CancelCommit(sessionEpoch: session.epoch)
        let sink = DisplaySink(screenCheck: (), commit: commit)
        sink.ledger = ledger; sink.ledgerGeneration = 1; sink.ledgerSession = session.epoch
        let source = ShellFrameSource(decoder: decoder, session: session)
        source.shouldStop = { @MainActor in sink.closedByUser }
        let clock = ShellClock()
        let pump = FramePump(source: source, sink: sink, clock: clock,
                             ledger: ledger, ledgerSession: session.epoch, ledgerGeneration: 1,
                             commit: commit) { seconds in
            // Cancellation-aware pacing wait (v4): the sleep's
            // CancellationError is REPORTED (false), never swallowed.
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); return true }
            catch { return false }
        }
        var seekTask: Task<ShellSeekWiringOutcome, Never>?
        if let plan = seekProbe {
            let bridge = ShellSeekBridge()
            if bridge.attach(to: decoder) {
                source.seekBridge = bridge
                summary.seekAttempted = true
                seekTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(plan.atSeconds * 1_000_000_000))
                    guard let pos = try? RationalTime(value: Int64(plan.targetSeconds * 1000), timescale: 1000)
                    else { return .noChange }
                    // M4 AUDIO LEG (before the video seek narrows the stale window):
                    // stop producer -> JOIN (quiescence witness) -> ring generation reset ->
                    // provider seek -> resume bound pulls on the NEW binding. Returned PCM
                    // already in flight is fenced by the binding check in runBound; the RT
                    // drain window is measured, never claimed revoked.
                    var videoOutcome: ShellSeekWiringOutcome = .noChange
                    if let cur = audioBinding {
                        // THE actual orchestration (GorAVSeekComposition, Linux-tested):
                        // producer stop+join -> VIDEO commit -> ring reset -> audio seek.
                        let audioOutcome = await SeekOrchestration.coordinateSeekAudio(
                            audioBinding: cur, audioCorrelation: audioCorrelation,
                            videoSeek: {
                                let o = await shellPerformSeek(bridge: bridge, provider: decoder, pump: pump,
                                                               position: pos, ledger: ledger,
                                                               ledgerSession: session.epoch, ledgerGeneration: 1,
                                                               seekAnchorSeconds: plan.targetSeconds)
                                videoOutcome = o
                                if case .committedAndReset = o { return true }
                                return false
                            },
                            commitAnchor: { pump.currentPaceAnchor },
                            decoder: adec, session: ases, sink: audio,
                            target: pos, targetSeconds: plan.targetSeconds, correlation: plan.correlation,
                            stopAndJoinProducer: {
                                audioStopFlag.store(1)
                                _ = await audioTask.value               // producer quiescence: JOINED
                                audio.markProducerJoined(generation: audio.currentGeneration)
                            },
                            resumeProducer: { b, c, anchor in
                                audioBinding = b; audioCorrelation = c
                                audioStopFlag.store(0)
                                audioTask = Task { let o = await BoundAudioPump.run(decoder: adec, session: ases, binding: b, correlation: c,
                                    sink: audio, clock: clock, sharedAnchor: anchor,
                                    ledger: ledger, ledgerSession: session.epoch, landing: landingBox,
                                    shouldStop: { audioStopFlag.load() != 0 }); return ShellAudioPump.Outcome(pushed: o.pushed, terminal: mapTerm(o.terminal)) }
                            },
                            closeAudio: { await adec.close(session: ases); adecOpened = false })
                        summary.seekAudioOutcome = audioOutcome.rawValue
                        switch videoOutcome {
                        case .committedButPumpRefused:
                            await decoder.close(session: session); decoderOpened = false
                        case .requiresClose:
                            _ = await decoder.closeAndReport(session: session); decoderOpened = false
                        default: break
                        }
                        return videoOutcome
                    }
                    let outcome = await shellPerformSeek(bridge: bridge, provider: decoder, pump: pump,
                                                         position: pos, ledger: ledger,
                                                         ledgerSession: session.epoch, ledgerGeneration: 1,
                                                         seekAnchorSeconds: plan.targetSeconds)
                    // Failure actions land HERE, in the seek completion control path - never
                    // deferred past further pump activity. shellPerformSeek has already
                    // prohibited admissions; this closes the provider immediately.
                    switch outcome {
                    case .committedButPumpRefused:
                        await decoder.close(session: session); decoderOpened = false
                    case .requiresClose:
                        _ = await decoder.closeAndReport(session: session); decoderOpened = false
                    default: break
                    }
                    return outcome
                }
            } else {
                summary.seekOutcome = "attachFailed"
            }
        }
        let hbT0 = Date()
        let heartbeat = Task { @MainActor [weak audio] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
                guard let audio else { return }
                print("gorav play hb t=\(Int(Date().timeIntervalSince(hbT0)))s displayUploaded=\(sink.uploads) displayVisibleUploads=\(sink.visibleUploads) displayNoPixel=\(sink.noPixels) windowClosedByUser=\(sink.closedByUser ? 1 : 0) audioConsumed=\(audio.kitConsumedBytes) overrunDrops=\(audio.overrunDrops) underrunBytes=\(audio.underrunBytes)")
            }
        }
        defer { heartbeat.cancel() }
        audioProducerStarted = true   // S2: producer task exists from here
        // M4: bound pulls FROM THE BEGINNING in probe mode - a legacy pull
        // would claim legacy mode and refuse every later seek (peer 73d2ea6c).
        guard let audioStopFlag = AtomicU64(0) else { throw NSError(domain: "gorav.shell", code: 92, userInfo: [NSLocalizedDescriptionKey: "audio stop flag cell refused"]) }
        let landingBox = AudioLandingBox()
        var audioBinding: AudioSourceBinding? = nil
        var audioCorrelation: UInt64? = nil   // peer envelopes: nil at initial open, plan correlation post-seek
        if seekProbe != nil {
            if let d = await adec.seekDescriptor(session: ases), d.seekable, d.referenceOrigin != nil {
                audioBinding = d.binding
                summary.seekAudioNote = "descriptor:originIsVideo=\(d.referenceIsVideo)"
            } else {
                summary.seekAudioNote = "descriptor-unavailable:audio-legacy-stale"
            }
        }
        func mapTerm(_ bt: BoundPumpTerminal) -> ShellAudioPump.Terminal {
            switch bt {
            case .endOfStream: return .endOfStream
            case .sourceEnded: return .sourceEnded
            case .cancelled: return .cancelled
            case .stoppedEarly: return .stoppedEarly
            case .failed(let c): return .failed(Int(c))
            }
        }
        var audioTask: Task<ShellAudioPump.Outcome, Never>
        if let b0 = audioBinding {
            audioTask = Task { let o = await BoundAudioPump.run(decoder: adec, session: ases, binding: b0, correlation: nil,
                sink: audio, ledger: ledger, ledgerSession: session.epoch, landing: landingBox,
                shouldStop: { audioStopFlag.load() != 0 }); return ShellAudioPump.Outcome(pushed: o.pushed, terminal: mapTerm(o.terminal)) }
        } else {
            audioTask = Task { await ShellAudioPump.runPaced(decoder: adec, session: ases, sink: audio,
                ledger: ledger, ledgerSession: session.epoch,
                shouldStop: { @MainActor in sink.closedByUser }) }
        }
        let stats = await pump.run()
        // S5: run ended - the shared authority refuses any further
        // admission/upload through teardown.
        commit.requestCancel()
        if let seekTask {
            switch await seekTask.value {
            case .committedAndReset:
                summary.seekOutcome = "committedAndReset"
                summary.seekAudioNote = "audio-unaffected-no-reposition-api"
            case .committedButPumpRefused:
                // close already landed inside the seek task (control path); telemetry only.
                summary.seekOutcome = "committedButPumpRefusedClosed"
                summary.seekAudioNote = "audio-unaffected-no-reposition-api"
            case .noChange:
                summary.seekOutcome = "noChange"
            case .requiresClose:
                summary.seekOutcome = "requiresCloseClosed"
                summary.seekAudioNote = "audio-unaffected-no-reposition-api"
            }
        }
        let outcome = await audioTask.value
        if let landing = landingBox.all.last {
            summary.seekAudioNote = "first=\(landing.firstSample.value)/\(landing.firstSample.timescale) gap=\(landing.gapFromTarget?.value ?? -1)/\(landing.gapFromTarget?.timescale ?? 1) trim=\(landing.trimmedSamples)"
        }
        // v4: the producer is JOINED before any stop/snapshot/reset - the
        // sink ENFORCES this witness (fails closed without it).
        audio.markProducerJoined(generation: audioGeneration)
        await adec.close(session: ases)
        // S4/r3: the decoder close result is EVIDENCE, never discarded.
        let closeReport = await decoder.closeAndReport(session: session)
        print("gorav play: decoders closed")
        // (team2 K9-07) EOS is a drain-point, not a cut-point: let the ring
        // play out before stop, bounded; residual is REPORTED.
        ledger.append(session: session.epoch, generation: audioGeneration, segment: .drain, subsystem: .audio, kind: .drainStart,
                      bytes: audio.available)
        let drained = await audio.drainBounded(maxSeconds: 5.0)
        if drained.cancelled {
            ledger.append(session: session.epoch, generation: audioGeneration, segment: .drain, subsystem: .audio,
                          kind: .terminal, note: "drainCancelled")
        }
        audio.drainRTTransitions(segment: .drain)
        ledger.append(session: session.epoch, generation: audioGeneration, segment: .drain, subsystem: .audio, kind: .drainEnd,
                      bytes: drained.remaining)
        ledger.append(session: 0, generation: 1, segment: .teardown, subsystem: .core, kind: .teardownStart)
        let audioStopOutcome = audio.stop()
        audio.drainRTTransitions(segment: .teardown)
        heartbeat.cancel()
        await heartbeat.value // deterministic: no heartbeat print or task outlives runMuxed
        // Finding 6: combined A/V terminal with EXPLICIT priority - never
        // whichever await returned last.
        let audioReason = EndReason.from(audioTerminal: ShellAudioPump.coreKind(of: outcome.terminal),
                                         closeIntent: sink.closedByUser)
        // Finding 5: the video end reason is DERIVED from the source's
        // typed end state + pump cancellation - never fabricated EOS.
        let videoReason: EndReason
        if stats.cancelled { videoReason = .cancelled }
        else {
            switch source.endState {
            case .endOfStream: videoReason = .endOfStream
            case .decodeFailed: videoReason = .decodeFailed
            case .stopped: videoReason = sink.closedByUser ? .userClose : .stoppedEarly
            case .interrupted: videoReason = .stoppedEarly
            case .running: videoReason = .stoppedEarly
            }
        }
        // S4: the summary NEVER travels alone - leg terminals, close
        /// intent, drain residual and the typed stop result are preserved
        /// separately in the typed RunTerminal. EOS success requires
        /// explicit EOS on both legs + clean drain + clean teardown;
        /// sourceEnded is not EOS.
        // r3 S4: teardownClean requires the typed .complete outcome -
        // "not failed" wrongly accepted .pending/.noop (verdict S4).
        let stopKind: StopOutcomeKind
        switch audioStopOutcome {
        case .complete: stopKind = .complete
        case .failed: stopKind = .failed
        case .pending: stopKind = .pending
        case .noop: stopKind = .noop
        }
        let closeSummary: DecoderCloseSummary? = closeReport.map {
            DecoderCloseSummary(leakedHandles: $0.leakedHandles.count,
                                droppedPendingPackets: $0.droppedPendingPackets,
                                leaseTableLeaks: $0.leaseTableLeaks.count,
                                ledgerLeaks: $0.ledgerLeaks.count,
                                logicalTeardown: $0.customIOLogicalTeardown.rawValue)
        }
        var failureCode: Int? = nil
        if case .failed(let c) = outcome.terminal { failureCode = c }
        let runTerminal = RunTerminal(audio: audioReason, video: videoReason,
                                      closeIntent: sink.closedByUser,
                                      audioDrainResidual: drained.remaining,
                                      teardownClean: audioStopOutcome.isComplete,
                                      audioStop: stopKind,
                                      decoderClose: closeSummary,
                                      failureCode: failureCode)
        let endReason = runTerminal.summary
        // Cond. 1 + finding 5: the queue bound is derived from RECORDED
        // maxima only, through the production predicate.
        let bound = QueueBoundEvidence(capacity: 1 << 20, watermark: 88200,
                                       maxChunkBytes: audio.maxChunkBytes,
                                       maxAvailAfterPush: audio.maxQueueBytes,
                                       overrunDrops: audio.overrunDrops,
                                       pushCount: audio.pushRecords)
        ledger.append(session: session.epoch, generation: audioGeneration, segment: .teardown, subsystem: .audio, kind: .terminal,
                      note: endReason.rawValue)
        ledger.append(session: 0, generation: 1, segment: .teardown, subsystem: .core,
                      kind: .teardownComplete, note: bound.summary + " eosSuccess=\(runTerminal.isEOSSuccess ? 1 : 0)")
        // v4 (full-review): ORDERED, PER-SESSION/GENERATION completeness,
        // diagnosed BEFORE the export so the diagnosis lands IN the
        // artifact. A kind fulfilled by a foreign session/generation or
        // out of order does NOT count.
        var missing: [String] = []
        for (ses, gen, req) in [
            (UInt64(0), UInt64(1), [LedgerKind.ledgerOrigin, .teardownStart, .teardownComplete]),
            (session.epoch, UInt64(1), [LedgerKind.videoPumpStart, .videoPumpEnd]),
            (session.epoch, audioGeneration, [LedgerKind.audioStartAccepted, .drainStart, .drainEnd,
                                          .audioStopAttempt, .audioStopAccepted, .disposeCompleted,
                                          .terminal]),
        ] {
            let m = ledger.missingSequence(session: ses, generation: gen, required: req)
            if !m.isEmpty { missing.append("s\(ses)g\(gen):" + m.map { $0.rawValue }.joined(separator: ",")) }
        }
        if !missing.isEmpty {
            ledger.append(session: 0, generation: 1, segment: .teardown, subsystem: .core,
                          kind: .rtOverflow,
                          note: "MISSING_LIFECYCLE:" + missing.joined(separator: ";"))
        }
        // Finding 7: the ledger write is CHECKED (no try? swallow). A lost
        // ledger means the run cannot back a PASS.
        let ledgerPath = env["GORAV_WORK"].map { $0 + "/gorav-timing-ledger.jsonl" } ?? "gorav-timing-ledger.jsonl"
        do {
            try ledger.jsonLines().write(toFile: ledgerPath, atomically: true, encoding: .utf8)
            summary.ledgerWriteOK = true
        } catch {
            summary.ledgerWriteOK = false
            print("gorav play: LEDGER WRITE FAILED: \(error)")
        }
        summary.shown = stats.shown; summary.dropped = stats.dropped; summary.waits = stats.waits
        summary.fencedShows = stats.fencedShows
        summary.audioPushed = outcome.pushed
        summary.terminal = "\(outcome.terminal)"
        summary.audioResidualAtStop = drained
        summary.audioOverrunDrops = audio.overrunDrops
        summary.audioUnderrunBytes = audio.underrunBytes
        summary.audioConsumedBytes = audio.kitConsumedBytes
        summary.closedByUser = sink.closedByUser
        summary.endReason = endReason.rawValue
        summary.ledgerEvents = ledger.count
        summary.ledgerAllowsSuccess = ledger.allowsSuccess && missing.isEmpty && !ledger.lastExportTruncated && !ledger.lastExportHeaderFailed
        summary.admissionBoundHolds = bound.admissionBoundHolds
        summary.uploads = sink.uploads; summary.visibleUploads = sink.visibleUploads
        summary.noPixels = sink.noPixels; summary.fenceSkips = sink.fenceSkips
        summary.audioStopCalls = audio.stopCallCount; summary.audioDisposeCount = audio.disposeCount
        summary.audioFailedStops = audio.failedStopCount
        summary.audioStaleFenced = audio.staleFencedCount
        print("gorav play: shown=\(stats.shown) dropped=\(stats.dropped) waits=\(stats.waits) fencedShows=\(stats.fencedShows) audioPushed=\(outcome.pushed) terminal=\(outcome.terminal) audioResidualAtStop=\(drained) audioOverrunDrops=\(audio.overrunDrops) audioUnderrunBytes=\(audio.underrunBytes) windowClosedByUser=\(sink.closedByUser ? 1 : 0) endReason=\(endReason.rawValue) ledgerEvents=\(ledger.count) ledgerAllowsSuccess=\(summary.ledgerAllowsSuccess ? 1 : 0) ledgerWriteOK=\(summary.ledgerWriteOK ? 1 : 0) admissionBound=\(bound.admissionBoundHolds ? 1 : 0) audioMaxQueueBytes=\(audio.maxQueueBytes) audioMaxChunkBytes=\(audio.maxChunkBytes) audioStopCalls=\(audio.stopCallCount) audioDisposeCount=\(audio.disposeCount) audioFailedStops=\(audio.failedStopCount) audioStaleFenced=\(audio.staleFencedCount) displayFenceSkips=\(sink.fenceSkips) displayUploaded=\(sink.uploads) displayNoPixel=\(sink.noPixels) audioCallbackRealBytes=\(audio.kitConsumedBytes) runID=\(runID)")
        } catch {
            // Typed cleanup on the throw path: close what was opened,
            // record statuses, propagate the ORIGINAL error.
            if adecOpened { await adec.close(session: ases) }
            if decoderOpened { _ = await decoder.closeAndReport(session: session) }
            ledger.append(session: 0, generation: 1, segment: .teardown, subsystem: .core,
                          kind: .decodeError,
                          note: "runMuxedThrow decodersClosed=\(adecOpened ? 1 : 0)\(decoderOpened ? 1 : 0)")
            throw error
        }
    }

    /// Minimal typed summary for the split-file sink check entry point.
    public struct ShellSummary: Sendable, Equatable {
        public var uploads = 0, visibleUploads = 0, noPixels = 0, audioConsumedBytes = 0
    }
    @MainActor @discardableResult
    public static func run(videoPath: String, audioPath: String?) async throws -> ShellSummary {
        guard let audio = AudioUnitSink() else { throw NSError(domain: "gorav.shell", code: 90, userInfo: [NSLocalizedDescriptionKey: "AudioUnitSink bring-up refused (C cells)"]) }
        // S4: owner-issued opaque identity (fixed epoch had NO authority).
        // Verdict S5 rev5 IDENTITY ORDER: issue BEFORE audio.start - no
        // start/ledger record carries a default-0 session.
        guard let session = PlaybackIdentityAuthority.shared.issue() else { throw NSError(domain: "gorav.shell", code: 91, userInfo: [NSLocalizedDescriptionKey: "identity authority exhausted (typed)"]) }
        audio.ledgerSession = session.epoch
        if audioPath != nil { try audio.start() }
        let decoder = FFmpegSoftwareDecoder()
        try decoder.pinLocalRoots([(videoPath as NSString).deletingLastPathComponent])
        try await decoder.open(source: SourceDescriptor(id: videoPath, kind: .local, seekable: true), session: session)
        if seekProbe != nil {
            _ = await decoder.nextEvent()   // enveloped: legacy pull would claim legacy and refuse tryBegin
        } else {
            _ = await decoder.nextEvent(session: session) // .opened (baseline path, unchanged)
        }
        let source = ShellFrameSource(decoder: decoder, session: session)
        let clock = ShellClock()
        // r3 S5 WIRING (peer rev1): shared cancel/commit cell through
        // pump + display fence (same authority as the muxed path).
        // Verdict S5 rev5: the sink binds its authority at INIT.
        let commit = CancelCommit(sessionEpoch: session.epoch)
        let sink = DisplaySink(screenCheck: (), commit: commit)
        let pump = FramePump(source: source, sink: sink, clock: clock,
                             commit: commit) { seconds in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); return true }
            catch { return false }
        }
        if let audioPath = audioPath {
            let adec = FFmpegSoftwareAudioDecoder()
            try adec.pinLocalRoots([(audioPath as NSString).deletingLastPathComponent])
            // S4: the audio leg shares the RUN identity authority.
            let ases = session   // S4: the audio leg SHARES the run's one owner-issued identity - no second mint
            try await adec.open(source: SourceDescriptor(id: audioPath, kind: .local, seekable: true), session: ases)
            async let audioOutcome = ShellAudioPump.run(decoder: adec, session: ases, sink: audio)
            let stats = await pump.run()
            commit.requestCancel()   // S5: fence teardown admissions
            let outcome = await audioOutcome
            // S2 caller fix: the audio pump task was AWAITED - witness the
            // join or stop() is a bounded retained fault, never a clean stop.
            audio.markProducerJoined(generation: audio.currentGeneration)
            await adec.close(session: ases)
            _ = await decoder.closeAndReport(session: session)
            let drained = await audio.drainBounded(maxSeconds: 5.0)
            audio.stop()
            print("gorav shell: shown=\(stats.shown) dropped=\(stats.dropped) waits=\(stats.waits) audioPushed=\(outcome.pushed) terminal=\(outcome.terminal) audioResidualAtStop=\(drained.remaining) drainCancelled=\(drained.cancelled ? 1 : 0)")
            return ShellSummary(uploads: sink.uploads, visibleUploads: sink.visibleUploads,
                                noPixels: sink.noPixels, audioConsumedBytes: audio.kitConsumedBytes)
        }
        let stats = await pump.run()
        commit.requestCancel()   // S5: fence teardown admissions
        _ = await decoder.closeAndReport(session: session)
        // S2 caller fix: video-only run - declare NO audio producer before
        // stop(), or stop() sees a pending witness and fails retained.
        audio.producerNotExpected(generation: audio.currentGeneration)
        audio.stop()
        print("gorav shell: shown=\(stats.shown) dropped=\(stats.dropped) waits=\(stats.waits)")
        return ShellSummary(uploads: sink.uploads, visibleUploads: sink.visibleUploads,
                            noPixels: sink.noPixels, audioConsumedBytes: audio.kitConsumedBytes)
    }
}
#endif
