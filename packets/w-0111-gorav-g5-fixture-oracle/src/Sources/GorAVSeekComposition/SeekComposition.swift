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
    /// design C: stop-unit quiescence -> fence advance -> in-place ring
    /// reset -> restart. nil = TYPED refusal, nothing mutated.
    func resetRingForSeek() async -> UInt64?
}

public final class AudioLandingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var landings: [AudioPCMTiming] = []
    public init() {}
    public func record(_ t: AudioPCMTiming) { lock.lock(); landings.append(t); lock.unlock() }
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
                        while clock.nowSeconds() < targetWall, spins < 400 {   // bounded: 4s max
                            if Task.isCancelled { return term(.cancelled) }
                            if let stop = shouldStop, await stop() { return term(.stoppedEarly) }
                            if await !waitNanos(10_000_000) { return term(.cancelled) }
                            spins += 1
                        }
                        if clock.nowSeconds() < targetWall {
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
                sink.push(f.bytes); pushed += f.bytes.count
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
    case closeRequired
    case refusedMuted              // video committed, audio seek refused -> audio CLOSED (typed mute)
    case ringResetRefusedMuted     // video committed, sink reset refused -> audio CLOSED (typed mute)
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
        videoSeek: () async -> Bool,                     // true = committed (and pump anchor set)
        commitAnchor: () -> MediaWallAnchor?,            // actual commit anchor from the pump
        decoder: FFmpegSoftwareAudioDecoder,
        session: SessionID,
        sink: any AudioSinkControlling,
        target: RationalTime,
        targetSeconds: Double,
        correlation: UInt64,
        stopAndJoinProducer: () async -> Void,
        resumeProducer: (AudioSourceBinding, UInt64?, MediaWallAnchor?) -> Void,
        closeAudio: () async -> Void
    ) async -> SeekAudioOutcome {
        await stopAndJoinProducer()
        guard await videoSeek() else {
            // Video refused PRE-mutation: resume with ring INTACT - truly
            // nothing mutated (provider cursors AND sink state).
            resumeProducer(audioBinding, audioCorrelation, nil)
            return .videoRefusedResumed
        }
        // Video COMMITTED: reset the ring in the quiesced window.
        guard await sink.resetRingForSeek() != nil else {
            // Typed refusal, ring NOT mutated - but the old audio position no
            // longer matches the new video position: CLOSE the audio leg
            // (typed mute). Resuming old audio here would split A/V.
            await closeAudio()
            return .ringResetRefusedMuted
        }
        let anchor = commitAnchor() ?? MediaWallAnchor(mediaSeconds: targetSeconds, wallSeconds: 0)
        let ar = await decoder.seek(binding: audioBinding, videoRelativeTarget: target, correlation: correlation)
        switch ar {
        case .nativeReady(let nb, let corr, _, _):
            resumeProducer(nb, corr, anchor)
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
