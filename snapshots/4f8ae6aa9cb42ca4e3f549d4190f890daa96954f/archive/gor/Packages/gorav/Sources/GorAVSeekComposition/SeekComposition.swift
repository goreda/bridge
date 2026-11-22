// GorAVSeekComposition (M4 rev2): the PLATFORM-NEUTRAL seek composition
// control + bound audio pump, extracted from the AppKit-gated shell so the
// ACTUAL functions run under Linux integration tests with the real audio
// provider and real fixtures. The Mac shell injects its sink/clock/tasks;
// the module owns the ordering and refusal semantics.
import Foundation
import GorAVCore
import GorAVPlaybackCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter

/// The sink surface the composition drives. AudioUnitSink conforms in the
/// Mac shell (extension, no peer/core edits); tests use a recording fake.
public protocol AudioSinkControlling: Sendable {
    var available: Int { get }
    var currentFenceGeneration: UInt64 { get }
    func push(_ pcm: [UInt8])
    /// Sink-owned atomic admission. admitted = pushed; heldPaused = typed
    /// quiesced retry of THIS SAME PCM; stopped = terminal, do not push.
    func pushIfUnpaused(_ pcm: [UInt8], expectedGeneration: UInt64) -> AudioPushAdmission
    /// design C: stop-unit quiescence -> fence advance -> in-place ring
    /// reset -> restart. nil = TYPED refusal, nothing mutated.
    func resetRingForSeek() async -> UInt64?
}

public enum AudioPushAdmission: Equatable, Sendable { case admitted, heldPaused, stopped }
public extension AudioSinkControlling {
    func pushIfUnpaused(_ pcm: [UInt8], expectedGeneration: UInt64) -> AudioPushAdmission { push(pcm); return .admitted }
}

public final class AudioLandingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var landings: [AudioPCMTiming] = []
    private var admitted: [AudioPCMTiming] = []
    private var firstAdmissionWall: Double? = nil
    public init() {}
    public func record(_ t: AudioPCMTiming) { lock.lock(); landings.append(t); lock.unlock() }
    public func recordAdmission(_ t: AudioPCMTiming) { lock.lock(); defer { lock.unlock() }; guard admitted.isEmpty else { return }; admitted.append(t); firstAdmissionWall = ProcessInfo.processInfo.systemUptime }
    public var admittedAll: [AudioPCMTiming] { lock.lock(); defer { lock.unlock() }; return admitted }
    public var admissionWall: Double? { lock.lock(); defer { lock.unlock() }; return firstAdmissionWall }
    public var all: [AudioPCMTiming] { lock.lock(); defer { lock.unlock() }; return landings }
}

public enum BoundPumpTerminal: Equatable, Sendable {
    case endOfStream, sourceEnded, cancelled, stoppedEarly, failed(Int32)
}
public struct BoundPumpOutcome: Equatable, Sendable {
    public let pushed: Int
    public let fencedStale: Int
    public let terminal: BoundPumpTerminal
    public init(pushed: Int, fencedStale: Int, terminal: BoundPumpTerminal) {
        self.pushed = pushed; self.fencedStale = fencedStale; self.terminal = terminal
    }
}

/// THE actual bound audio pump (verbatim extraction of ShellAudioPump.runBound
/// incl. the r4/r4b fences and shared-anchor first-push wait).
public enum BoundAudioPump {
    public static func defaultWait(_ ns: UInt64) async -> Bool {
        do { try await Task.sleep(nanoseconds: ns); return true } catch { return false }
    }
    public static func run(decoder: FFmpegSoftwareAudioDecoder, session: SessionID,
                           binding: AudioSourceBinding, correlation: UInt64?,
                           sink: any AudioSinkControlling, highWaterBytes: Int = 88200,
                           clock: (any PlaybackClock)? = nil, sharedAnchor: MediaWallAnchor? = nil,
                           ledger: TimingLedger? = nil, ledgerSession: UInt64 = 0,
                           landing: AudioLandingBox? = nil,
                           shouldStop: (@Sendable () async -> Bool)? = nil,
                           shouldPause: (@Sendable () async -> Bool)? = nil,
                           waitNanos: (@Sendable (UInt64) async -> Bool) = defaultWait) async -> BoundPumpOutcome {
        let generation = sink.currentFenceGeneration
        var pushed = 0, fencedStale = 0, firstLandingSeen = false
        func term(_ kind: BoundPumpTerminal, code: Int32 = 0) -> BoundPumpOutcome {
            ledger?.append(session: ledgerSession, generation: generation, segment: .pump,
                           subsystem: .audio, kind: .terminal,
                           note: "\(kind) staleFenced=\(fencedStale)")
            return BoundPumpOutcome(pushed: pushed, fencedStale: fencedStale, terminal: kind)
        }
        if Task.isCancelled { return term(.cancelled) }
        if let stop = shouldStop, await stop() { return term(.stoppedEarly) }
        while let env = await decoder.nextBoundEvent(binding: binding) {
            // Returned-PCM fence: source/session/audioRevision (binding) AND
            // plan correlation - peer envelopes carry NIL correlation at
            // initial open, so the expectation is UInt64? end to end.
            guard env.binding == binding, env.correlation == correlation else { fencedStale += 1; continue }
            switch env.event {
            case .pcm(let f):
                if !firstLandingSeen, sharedAnchor != nil, env.timing == nil {
                    // Defensive (peer contract: timing present on every bound PCM):
                    // an anchored resume with UNtimed first PCM would push immediately
                    // and silently collapse the A/V offset - typed failure instead.
                    ledger?.append(session: ledgerSession, generation: generation, segment: .pump,
                                   subsystem: .audio, kind: .terminal, note: "anchorTimingMissing")
                    return term(.failed(-22))
                }
                if !firstLandingSeen, let tm = env.timing {
                    firstLandingSeen = true; landing?.record(tm)
                    // SHARED post-seek anchor: the first push waits until the
                    // anchor schedules this PCM's first sample, preserving the
                    // audio start offset vs the seek target as an ACTUAL A/V
                    // offset (canonical: 0; +100ms edit-list fixture: 100ms).
                    if let anchor = sharedAnchor, let clock {
                        let firstSec = Double(tm.firstSample.value) / Double(tm.firstSample.timescale)
                        let targetWall = anchor.scheduledWall(forMediaSeconds: firstSec)
                        var spins = 0
                        var landingNow = clock.nowSeconds()
                        guard landingNow.isFinite && targetWall.isFinite else {
                            ledger?.append(session: ledgerSession, generation: generation, segment: .pump,
                                           subsystem: .audio, kind: .terminal,
                                           note: "clockNonFiniteAtOffset")
                            return term(.failed(-94))
                        }
                        while landingNow < targetWall, spins < 400 {   // bounded: 4s max
                            if Task.isCancelled { return term(.cancelled) }
                            if let stop = shouldStop, await stop() { return term(.stoppedEarly) }
                            if await !waitNanos(10_000_000) { return term(.cancelled) }
                            spins += 1
                            landingNow = clock.nowSeconds()
                            guard landingNow.isFinite else {
                                ledger?.append(session: ledgerSession, generation: generation, segment: .pump,
                                               subsystem: .audio, kind: .terminal,
                                               note: "clockNonFiniteDuringOffset")
                                return term(.failed(-94))
                            }
                        }
                        if landingNow < targetWall {
                            // Deadline missed: TYPED failure, never push early
                            // (an early push silently collapses the A/V offset).
                            ledger?.append(session: ledgerSession, generation: generation, segment: .pump,
                                           subsystem: .audio, kind: .terminal,
                                           note: "anchorScheduleMiss target=\(targetWall) now=\(clock.nowSeconds())")
                            return term(.failed(-21))
                        }
                    }
                }
                while sink.available > highWaterBytes {
                    if Task.isCancelled { return term(.cancelled) }
                    if let stop = shouldStop, await stop() { return term(.stoppedEarly) }
                    if await !waitNanos(10_000_000) { return term(.cancelled) }
                }
                // A pull may return just as pause begins. Hold that PCM
                // without pushing or reclassifying it as a terminal event.
                while let pause = shouldPause, await pause() {
                    if Task.isCancelled { return term(.cancelled) }
                    if let stop = shouldStop, await stop() { return term(.stoppedEarly) }
                    if await !waitNanos(10_000_000) { return term(.cancelled) }
                }
                if Task.isCancelled { return term(.cancelled) }
                if let stop = shouldStop, await stop() { return term(.stoppedEarly) }
                // Pause is an await boundary: do not push an old ring
                // generation, or PCM whose provider binding changed.
                let expectedGeneration = sink.currentFenceGeneration
                guard expectedGeneration == generation else {
                    fencedStale += 1
                    return term(.stoppedEarly)
                }
                guard let current = await decoder.seekDescriptor(session: session), current.binding == binding,
                      sink.currentFenceGeneration == expectedGeneration else {
                    fencedStale += 1
                    return term(.stoppedEarly)
                }
                // Retry THIS SAME PCM; continue would discard it and pull
                // the next chunk, falsely passing a later-identity test.
                var admission: AudioPushAdmission
                repeat {
                    if let pause = shouldPause, await pause() {
                        if await !waitNanos(10_000_000) { return term(.cancelled) }
                        if let stop = shouldStop, await stop() { return term(.stoppedEarly) }
                        if Task.isCancelled { return term(.cancelled) }
                        guard sink.currentFenceGeneration == expectedGeneration,
                              let current = await decoder.seekDescriptor(session: session),
                              current.binding == binding,
                              sink.currentFenceGeneration == expectedGeneration else {
                            fencedStale += 1
                            return term(.stoppedEarly)
                        }
                        admission = .heldPaused
                        continue
                    }
                    if let stop = shouldStop, await stop() { return term(.stoppedEarly) }
                    if Task.isCancelled { return term(.cancelled) }
                    // Sink lock owns generation/lifecycle/pause and write as
                    // ONE admission decision; never admit under a stale fence.
                    admission = sink.pushIfUnpaused(f.bytes, expectedGeneration: expectedGeneration)
                    if admission == .heldPaused {
                        if await !waitNanos(10_000_000) { return term(.cancelled) }
                        if let stop = shouldStop, await stop() { return term(.stoppedEarly) }
                        if Task.isCancelled { return term(.cancelled) }
                        guard sink.currentFenceGeneration == expectedGeneration else {
                            fencedStale += 1
                            return term(.stoppedEarly)
                        }
                        guard let current = await decoder.seekDescriptor(session: session), current.binding == binding,
                              sink.currentFenceGeneration == expectedGeneration else {
                            fencedStale += 1
                            return term(.stoppedEarly)
                        }
                    }
                } while admission == .heldPaused
                if admission == .stopped { fencedStale += 1; return term(.stoppedEarly) }
                if let tm = env.timing { landing?.recordAdmission(tm) }
                pushed += f.bytes.count
            case .endOfStream: return term(.endOfStream)
            case .failed(let code, _): return term(.failed(Int32(code)), code: Int32(code))
            case .opened: continue
            }
            if let stop = shouldStop, await stop() { return term(.stoppedEarly) }
        }
        return term(.sourceEnded)
    }
}

public enum SeekAudioOutcome: String, Equatable, Sendable {
    case nativeReady
    case resumeRefusedMuted         // joined producer could not safely re-arm
    case closeRequired
    case refusedMuted              // video committed, audio seek refused -> audio CLOSED (typed mute)
    case ringResetRefusedMuted     // video committed, sink reset refused -> audio CLOSED (typed mute)
    case firstFrameTimeoutMuted    // video committed, no first presentable frame inside the gate window -> audio CLOSED (typed mute)
    case videoRefusedResumed       // video refused pre-mutation: producer resumed, ring INTACT
    case ringResetRefusedResumed   // video NOT yet sought (legacy path): resume same, untouched
}

/// THE actual seek audio-leg orchestration (M4 rev2 order): producer
/// stopped+joined (provider cursor untouched) -> VIDEO commit (injected) ->
/// ONLY on commit: sink ring reset -> audio provider seek (REAL). Refusal
/// semantics: a refused VIDEO seek mutates nothing anywhere (producer resumed
/// with ring/fence intact). After a COMMITTED video seek there is no resume
/// of the old audio position - a refused ring reset or refused audio seek
/// CLOSES the audio leg (typed mute, consistent A/V). No rollback is claimed.
public enum SeekOrchestration {
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
        guard let resetFence = await sink.resetRingForSeek() else {
            // Typed refusal, ring NOT mutated - but the old audio position no
            // longer matches the new video position: CLOSE the audio leg
            // (typed mute). Resuming old audio here would split A/V.
            await closeAudio()
            return .ringResetRefusedMuted
        }
        onAudioRingReset?()
        let ar = await decoder.seek(binding: audioBinding, videoRelativeTarget: target, correlation: correlation)
        onAudioSeekDone?(ar)
        switch ar {
        case .nativeReady(let nb, let corr, _, _):
            guard resumeProducer(nb, corr, anchor, resetFence) else {
                await closeAudio()
                return .resumeRefusedMuted
            }
            return .nativeReady
        case .closeRequired:
            await closeAudio()
            return .closeRequired
        case .refused:
            await closeAudio()
            return .refusedMuted
        }
    }
}

