// AudioPacing.swift - GP-47 / M1 (164h) audio-master pacing policy and
// PlaybackClock adapter. Linux-testable: no AppKit/CoreAudio imports.
//
// Architect ruling 2026-10-30 19:51 (current main de9a3304): the clock
// authority behind nowSeconds() is audio-backed once audio runs
// (device-consumed frames / sampleRate), with a WALL fallback before the
// first anchor and for audio-absent sources. The composition (J3) injects
// this clock where the wall clock goes today - zero PlaybackCore edits.
//
// Epoch discipline (the ruling's unit/anchor-continuity condition):
// nowSeconds() ALWAYS reads on the owner's shared wall epoch. The audio
// correlation (GorAVAudioClock anchor) maps device-consumed samples onto
// that epoch: value(host) = mediaTime(host) + epochOffset. The offset is
// re-based at every anchor event so the value is CONTINUOUS across the
// wall->audio switch, across pause/resume, and across seek generation
// resets. nowSeconds() is monotonic as long as the device clock is.
//
// 2.2 no clock substitution: once a master has been anchored, losing it
// (fence on stop) surfaces as masterLost + a NaN reading - a fail-stop
// the session owner must terminate on, NEVER a silent wall fallback.
// NOTE on unguarded current-main AVSyncDecider: a NaN decision-now
// decides .show. The session MUST select the audio master only while
// hasMaster and tear down on masterLost; consuming that signal is J3's
// composition scope.
//
// Pause/quiesce (typed; 19:50 condition (a) counter hygiene): pause
// freezes the value (the sink holds its ring residual, so the
// device-consumed counter is frozen); intentional-pause silence is
// counted separately by the sink, never as underrun/overrun. Resume is a
// NEW clock generation (8.5 timeline change) whose anchor re-bases the
// epoch offset at the frozen value: no clock jump on resume, and no
// clock-drift decisions are made during the quiesced interval.
//
// Seek (M4 ring reset) is a new generation; the value stays continuous
// and monotonic across it (the pump re-anchors pts on arrival).
//
// G-A11: tolerances are caller-fixed inputs; no tuned constants here.
//
// Threading (architect 2026-10-30 20:09 cross-lane race verdict): the C
// core has no internal locking, and the pump thread READS this policy
// (nowSeconds -> value/hasMaster) while the session owner WRITES it
// (start/pause/resume/seek/stop/periodicAnchor). This type therefore
// SERIALIZES INTERNALLY: one NSLock guards every Swift field AND every
// C-core handle access made through the policy. nowSeconds() stays
// synchronous (brief lock, no allocation, no RT use - the AudioUnit
// render thread never calls it; it reads the sink's atomic pause flag).
// Direct use of `clock` outside the policy requires the caller's own
// serialization with policy calls (tests do this single-threaded).

import Foundation
import GorAVAudioClock
import GorAVPlaybackCore

/// Typed pacing receipts (architect 19:50 condition (d)): every transition
/// and refusal is counted; counters reconcile 1:1 with policy calls.
public struct AudioPacingCounters: Equatable, Sendable {
    public var generation: UInt64 = 0
    public var anchorsAccepted = 0
    public var anchorRefusals = 0
    public var lastAnchorStatus: AudioClockStatus? = nil
    public var pauseTransitions = 0
    public var resumeTransitions = 0
    public var seekGenerationResets = 0
    /// Intentional-pause silence rendered by the sink (folded in on
    /// resume), kept OUT of underrunBytes/overrunDrops.
    public var pausedSilenceFrames: UInt64 = 0
    /// R6 (arch-195l): accepted delay CHANGES (same-value sets not counted).
    public var delayChanges = 0
    public init() {}
}

public final class AudioPacingPolicy {
    /// The owned audio clock. Anchors are the sink's OWN device-consumed
    /// counter only (8.2); queries extrapolate at host rate between
    /// anchors. All composition access MUST go through this policy's
    /// methods (they hold stateLock); direct `clock` calls require the
    /// caller's own serialization with policy calls.
    public let clock: AudioClock
    public let sampleRate: UInt32
    public let consistencyTolerance: Double
    /// Guards every mutable field below AND every C-core handle access
    /// made through the policy (the core has no internal locking).
    private let stateLock = NSLock()
    private var countersStorage = AudioPacingCounters()
    private var pausedStorage = false
    private var hasEpochMappingStorage = false
    private var epochOffset: Double = 0
    private var freezeValue: Double? = nil
    /// R6 (arch-195l): user audio delay (mpv convention: positive = audio
    /// later). READ-SIDE offset only: anchors, consistency checks and the
    /// master mapping are untouched; the reported value shifts by exactly
    /// -(delay delta) at the next read. A value frozen by pause keeps the
    /// delay that was in force when it froze.
    private var delayStorage: Double = 0

    /// Typed pacing receipts - a CONSISTENT snapshot (struct copy under
    /// the lock), safe to read while the session mutates.
    public var counters: AudioPacingCounters {
        stateLock.lock(); defer { stateLock.unlock() }
        return countersStorage
    }
    /// True while quiesced (typed pause in force).
    public var paused: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return pausedStorage
    }
    /// True once at least one anchor landed: the wall fallback is over.
    public var hasEpochMapping: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return hasEpochMappingStorage
    }
    /// True only while a proven anchor is in force (one lock acquisition:
    /// mapping + C-core master read are observed together).
    public var hasMasterProven: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return hasEpochMappingStorage && clock.hasMaster
    }

    public init?(hostClock: @escaping @Sendable () -> Double, sampleRate: UInt32,
                 consistencyTolerance: Double) {
        guard sampleRate > 0, consistencyTolerance.isFinite, consistencyTolerance >= 0 else { return nil }
        guard let c = AudioClock(hostClock: hostClock) else { return nil }
        self.clock = c
        self.sampleRate = sampleRate
        self.consistencyTolerance = consistencyTolerance
    }

    /// Current value on the shared wall epoch. nil before the first
    /// anchor (caller falls back to wall); the frozen value while paused;
    /// nil after the master is fenced (the adapter then fails STOP).
    public func wallEpochValue(atHost host: Double) -> Double? {
        stateLock.lock(); defer { stateLock.unlock() }
        return wallEpochValueLocked(atHost: host)
    }

    private func wallEpochValueLocked(atHost host: Double) -> Double? {
        if pausedStorage { return freezeValue }
        guard hasEpochMappingStorage else { return nil }
        let r = clock.mediaTime(atHost: host)
        guard r.status == .ok, let m = r.mediaTime else { return nil }
        return m + epochOffset - delayStorage
    }

    /// R6 (arch-195l): set the user audio delay. false = refused
    /// (non-finite or beyond AudioDelay.limitSeconds); state unchanged.
    /// Same-value set is accepted without a counter bump.
    @discardableResult
    public func setDelay(seconds newDelay: Double) -> Bool {
        guard newDelay.isFinite, abs(newDelay) <= AudioDelay.limitSeconds else { return false }
        stateLock.lock(); defer { stateLock.unlock() }
        if newDelay != delayStorage {
            delayStorage = newDelay
            countersStorage.delayChanges &+= 1
        }
        return true
    }
    /// The delay currently in force (seconds; positive = audio later).
    public var delaySeconds: Double {
        stateLock.lock(); defer { stateLock.unlock() }
        return delayStorage
    }

    /// Session start (first successful render-path start): first
    /// generation; the offset is continuous with the wall clock NOW.
    @discardableResult
    public func sessionStart(consumedFrames: UInt64, atHost host: Double) -> AudioClockStatus {
        stateLock.lock(); defer { stateLock.unlock() }
        let g = countersStorage.generation &+ 1
        let off = host - Double(consumedFrames) / Double(sampleRate)
        let st = applyAnchorLocked(generation: g, consumedFrames: consumedFrames,
                                   host: host, newOffset: off, fencePrior: false)
        if st == .ok {
            countersStorage.generation = g
            // A new session NEVER inherits a prior session's quiesce
            // (20:40 lifecycle race): a pause orphaned by teardown would
            // otherwise freeze the fresh session's clock at the stale
            // value forever.
            pausedStorage = false
            freezeValue = nil
        }
        return st
    }

    /// Typed pause. Refused (false) when already paused, before the
    /// first anchor, or when the freeze value cannot be read finite
    /// (nothing to freeze; the wall fallback is already
    /// stationary-correct for the session).
    @discardableResult
    public func pause(atHost host: Double) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        // Require a LIVE current-generation master (20:22 architect
        // review): hasEpochMapping persists across sessions, so without
        // the hasMaster check a pause landing between a new session's
        // lifecycle publication and its first anchor would succeed
        // against the PREVIOUS session's stale mapping and then be
        // silently cleared by sessionStart - a pause that returned true
        // but never happened. After sessionStop (fence) hasMaster is
        // false, so such a pause now gets the honest typed refusal.
        guard !pausedStorage, hasEpochMappingStorage, clock.hasMaster else { return false }
        // native111 (local overlay vs upstream 2112af0d): a pause that
        // cannot freeze a FINITE value must refuse typed, not latch
        // pausedStorage with a nil/non-finite freezeValue - resume's
        // `guard let frozen` (and the anchor's isfinite checks) would
        // refuse forever, so the pause becomes a one-way door only a
        // seekReset re-base reopens (paused, unresumable until seek).
        // Refusal leaves the session fully in
        // the prior leg (typed atomic; nothing to freeze = nothing to
        // pause). Reachability note: gvac_media_time fails only on a
        // non-finite host or no-master (guarded above), and a finite
        // host can still extrapolate to a non-finite value.
        guard let freeze = wallEpochValueLocked(atHost: host), freeze.isFinite else { return false }
        freezeValue = freeze
        pausedStorage = true
        countersStorage.pauseTransitions += 1
        return true
    }

    /// Typed resume: NEW generation (8.5). The anchor uses the sink's
    /// device-consumed counter (frozen over the pause) and re-bases the
    /// epoch offset at the frozen value - exact and continuous.
    @discardableResult
    public func resume(consumedFrames: UInt64, atHost host: Double) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard pausedStorage, let frozen = freezeValue else { return false }
        let g = countersStorage.generation &+ 1
        let off = frozen - Double(consumedFrames) / Double(sampleRate)
        let st = applyAnchorLocked(generation: g, consumedFrames: consumedFrames,
                                   host: host, newOffset: off, fencePrior: true)
        guard st == .ok else { return false }
        countersStorage.generation = g
        freezeValue = nil
        pausedStorage = false
        countersStorage.resumeTransitions += 1
        return true
    }

    /// M4 seek ring reset: the ring restarts at 0, so media restarts at
    /// 0; the value is kept continuous/monotonic (the pump re-anchors pts
    /// on arrival). A seek while paused re-bases the frozen value too.
    @discardableResult
    public func seekReset(atHost host: Double) -> AudioClockStatus {
        stateLock.lock(); defer { stateLock.unlock() }
        let v = wallEpochValueLocked(atHost: host) ?? host
        let g = countersStorage.generation &+ 1
        let st = applyAnchorLocked(generation: g, consumedFrames: 0,
                                   host: host, newOffset: v, fencePrior: countersStorage.generation > 0)
        guard st == .ok else { return st }
        countersStorage.generation = g
        if pausedStorage { freezeValue = v }
        countersStorage.seekGenerationResets += 1
        return st
    }

    /// Teardown: fence the master. Later readings fail (masterLost),
    /// never substitute (2.2).
    public func sessionStop() {
        stateLock.lock(); defer { stateLock.unlock() }
        if hasEpochMappingStorage { clock.fence(generation: countersStorage.generation) }
    }

    /// Periodic same-generation re-anchor (drift tracking). The offset is
    /// re-based so the value is continuous at the re-anchor instant. A
    /// beyond-tolerance sample is a typed refusal, counted, previous
    /// anchor in force.
    @discardableResult
    public func periodicAnchor(consumedFrames: UInt64, atHost host: Double) -> AudioClockStatus {
        stateLock.lock(); defer { stateLock.unlock() }
        guard hasEpochMappingStorage, !pausedStorage else { return .noMaster }
        let v = wallEpochValueLocked(atHost: host) ?? host
        let off = v - Double(consumedFrames) / Double(sampleRate)
        return applyAnchorLocked(generation: countersStorage.generation, consumedFrames: consumedFrames,
                                 host: host, newOffset: off, fencePrior: false)
    }

    /// Drift between the two most recent same-generation anchors
    /// (.insufficientAnchors until two; thresholds stay the caller's).
    public func driftPPM() -> (status: AudioClockStatus, ppm: Double?) {
        stateLock.lock(); defer { stateLock.unlock() }
        return clock.driftPPM()
    }

    /// Fold the sink's RT-thread pause-silence count into the receipts.
    public func notePausedSilence(_ frames: UInt64) {
        stateLock.lock(); defer { stateLock.unlock() }
        countersStorage.pausedSilenceFrames += frames
    }

    @discardableResult
    private func applyAnchorLocked(generation: UInt64, consumedFrames: UInt64, host: Double,
                                   newOffset: Double, fencePrior: Bool) -> AudioClockStatus {
        let st = clock.anchor(generation: generation, consumedSamples: Int64(consumedFrames),
                              sampleRate: sampleRate, hostTime: host,
                              consistencyTolerance: consistencyTolerance)
        countersStorage.lastAnchorStatus = st
        guard st == .ok else { countersStorage.anchorRefusals += 1; return st }
        if fencePrior, generation > 0 { clock.fence(generation: generation &- 1) }
        countersStorage.anchorsAccepted += 1
        epochOffset = newOffset
        hasEpochMappingStorage = true
        return st
    }
}

/// The audio master presented as a PlaybackClock (the pump's injected
/// clock). Values are ALWAYS on the shared wall epoch (see the policy
/// header); before the first anchor this is the plain wall clock, and a
/// lost master after selection reads NaN + masterLost (fail-stop, never
/// substitution).
///
/// @unchecked Sendable: internally synchronized - the pump thread reads
/// nowSeconds()/hasMaster while the session owner mutates the policy
/// (architect 20:09 race verdict). masterLost has its own lock; all
/// policy state is read through the policy's serialized methods.
public final class AudioMasterPacingClock: PlaybackClock, @unchecked Sendable {
    public let policy: AudioPacingPolicy
    private let hostNow: @Sendable () -> Double
    private let lostLock = NSLock()
    private var masterLostStorage = false
    /// Set once a reading fails after an epoch mapping existed. Sticky:
    /// the session owner must tear down (2.2), not recover silently.
    public private(set) var masterLost: Bool {
        get { lostLock.lock(); defer { lostLock.unlock() }; return masterLostStorage }
        set { lostLock.lock(); masterLostStorage = newValue; lostLock.unlock() }
    }
    public init(policy: AudioPacingPolicy, hostClock: @escaping @Sendable () -> Double) {
        self.policy = policy
        self.hostNow = hostClock
    }
    /// True only while a proven anchor is in force. The composition MUST
    /// select the audio master only while this holds.
    public var hasMaster: Bool { policy.hasMasterProven }
    public func nowSeconds() -> Double {
        let h = hostNow()
        if let v = policy.wallEpochValue(atHost: h) { return v }
        if policy.hasEpochMapping { masterLost = true; return .nan }
        return h
    }
}

// MARK: - Sink admission core (Linux-testable; shared with the Mac sink)

/// The refusal decision the Mac AudioUnitSink's REAL stateLock critical
/// section makes (20:17 architect blocker): extracted here so the Linux
/// suite drives the SAME decision code under contention, not a toy
/// independent model. Production exclusion: the sink's stateLock (pause
/// writes + this decision + the ring write in one section); tests use
/// `admissionLock` to apply the identical discipline.
public enum AudioAdmissionRefusal: Equatable, Sendable {
    /// Fence advanced past the caller's expectation (a seek/reset
    /// landed): old-generation PCM, never written. Sink maps to .stopped.
    case staleGeneration
    /// Genuinely quiesced: nothing written or counted; the caller
    /// retains the PCM and retries after resume. Sink maps to .heldPaused.
    case paused
}

public final class AudioAdmissionState: @unchecked Sendable {
    /// RT-visible pause cell (lock-free read on the render thread).
    /// Written ONLY under the owner's admission lock (production: the
    /// sink's stateLock inside pauseAudio/resumeAudio).
    public let pausedCell: AtomicU64?
    /// The test/driver lock playing the sink stateLock's exclusion role.
    public let admissionLock = NSLock()
    public init() { pausedCell = AtomicU64(0) }
    /// Lock-free pause read (render thread + producer pre-checks).
    public var isPaused: Bool { (pausedCell?.load() ?? 0) != 0 }
    /// The shared admission decision; call with the owner's admission
    /// lock HELD. nil = proceed to the ring write.
    public func refusal(fenceActive: UInt64, expectedGeneration: UInt64) -> AudioAdmissionRefusal? {
        guard fenceActive == expectedGeneration else { return .staleGeneration }
        if isPaused { return .paused }
        return nil
    }
}
