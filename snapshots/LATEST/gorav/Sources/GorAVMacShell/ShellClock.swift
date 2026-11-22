// AUTHORED NEW (2026-10-17, K6 shell): macOS clock + window/display/audio
// sinks for GorAVPlaybackCore. Derived from mpv 0.41.0 macOS implementation
// (study-only, GPLv2+): video/out/mac/window.swift + view.swift (NSWindow/
// NSView ownership), common.swift (CVDisplayLink/CADisplayLink pacing),
// audio/out/ao_audiounit.m (AudioUnit render-callback pull model).
// Linux-safe: the whole module is AppKit-gated; core stays Linux-testable.
//
// M1 DELTA (2026-10-30, GP-47 / 164h, architect ruling 19:51 on main
// de9a3304): ShellClock becomes the audio-master injection point. Once an
// AudioMasterPacingClock is attached AND holds a proven anchor,
// nowSeconds() is AUDIO-BACKED (the AudioUnit device-consumed position
// mapped onto THIS wall epoch); before the anchor, for audio-absent
// sources, or with no attachment it stays the plain wall clock. A master
// lost after selection fails STOP (NaN), never a silent substitution.
// This closes the LANE_INTERFACES L1 gap ("Audio-master sync:
// NOT_IMPLEMENTED today") at the clock object the composition already
// injects - zero PlaybackCore edits (decide() stays J3's).
#if canImport(AppKit) && canImport(CoreAudio)
import AppKit
import QuartzCore
import GorAVPlaybackCore
import GorAVAudioClockSwift

/// CACurrentMediaTime-backed clock. mpv paces against the display link;
/// CACurrentMediaTime is the same mach_absolute_time base (mpv common.swift).
public final class ShellClock: PlaybackClock, @unchecked Sendable {
    private let t0 = CACurrentMediaTime()
    private let stateLock = NSLock()
    private var audioMaster: AudioMasterPacingClock?
    public init() {}

    /// Raw wall seconds on THIS clock's epoch. The audio pacing policy and
    /// the TimingLedger must share THIS reading (one epoch authority).
    /// Never pass nowSeconds() itself as the policy's host clock - that
    /// would recurse once audio is attached.
    public func rawWallSeconds() -> Double { CACurrentMediaTime() - t0 }

    /// The composition (J3) attaches the sink's pacing clock after start,
    /// and detaches (nil) on teardown. Attachment alone changes nothing:
    /// the audio master drives nowSeconds() only while it holds a proven
    /// anchor (hasMaster).
    public func attachAudioMaster(_ clock: AudioMasterPacingClock?) {
        stateLock.lock(); audioMaster = clock; stateLock.unlock()
    }

    public func nowSeconds() -> Double {
        stateLock.lock(); let a = audioMaster; stateLock.unlock()
        if let a {
            // A lost master after selection is a fail-stop signal (2.2 no
            // substitution); the session owner tears down on it.
            if a.masterLost { return .nan }
            if a.hasMaster { return a.nowSeconds() }
        }
        return CACurrentMediaTime() - t0
    }
}
#endif
