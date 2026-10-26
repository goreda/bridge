// AUTHORED NEW (2026-10-17, K6 shell): macOS clock + window/display/audio
// sinks for GorAVPlaybackCore. Derived from mpv 0.41.0 macOS implementation
// (study-only, GPLv2+): video/out/mac/window.swift + view.swift (NSWindow/
// NSView ownership), common.swift (CVDisplayLink/CADisplayLink pacing),
// audio/out/ao_audiounit.m (AudioUnit render-callback pull model).
// Linux-safe: the whole module is AppKit-gated; core stays Linux-testable.
#if canImport(AppKit) && canImport(CoreAudio)
import AppKit
import QuartzCore
import GorAVPlaybackCore

/// CACurrentMediaTime-backed clock. mpv paces against the display link;
/// CACurrentMediaTime is the same mach_absolute_time base (mpv common.swift).
public final class ShellClock: PlaybackClock, @unchecked Sendable {
    private let t0 = CACurrentMediaTime()
    public init() {}
    public func nowSeconds() -> Double { CACurrentMediaTime() - t0 }
}
#endif
