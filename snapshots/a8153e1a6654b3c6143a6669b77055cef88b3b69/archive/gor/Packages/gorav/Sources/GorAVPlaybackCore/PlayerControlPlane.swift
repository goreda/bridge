// PlayerControlPlane (block 168 m3, L7/L8 factory gap, trunk hook L1/C1) - candidate r3.
// PURE CORE: no AppKit/Metal/CoreAudio imports - compiles and unit-tests on Linux
// (GorAVPlaybackCore target is glob-sourced; tests live in Tests/PlayerControlPlaneTests).
// The Mac session (GorAVEmbeddedSession) and any facade arbitrate through this ONE
// plane, so an illegal transition is refused typed in exactly one place.
// r3 (review finding): seek PRESERVES its origin state - a seek begun from paused
// resolves back to paused on BOTH committed and refused outcomes, never silently
// resumes playback.
import Foundation

/// Monotonic player lifecycle. rawValue order is NOT the transition order;
/// legality is defined only by PlayerControlPlane.allows.
public enum PlayerLifecycleState: String, Sendable, Equatable, CaseIterable {
    case idle, loading, ready, playing, paused, seeking, closing, closed, failed
}

/// Host-callable controls. `fail` is the typed-error ingress from any leg
/// (decoder, sink, pump); it is legal from EVERY non-terminal state.
public enum PlayerControl: String, Sendable, Equatable, CaseIterable {
    case beginLoad, loadReady, loadFailed
    case play, pause, resume
    case beginSeek, seekCommitted, seekRefused, seekRequiresClose
    case close, closed, fail
}

public enum PlayerControlRefusal: Error, Sendable, Equatable {
    case illegalTransition(from: PlayerLifecycleState, control: PlayerControl)
    case terminal(PlayerLifecycleState)
}

/// Pure arbitration plane. Value type: the session owns exactly one instance and
/// applies transitions under its own isolation; there is no hidden shared state.
public struct PlayerControlPlane: Sendable, Equatable {
    public private(set) var state: PlayerLifecycleState = .idle
    /// Monotonic generation: advances on EVERY accepted transition. Consumers
    /// fence stale receipts by generation; a refused control never advances it.
    public private(set) var generation: UInt64 = 0
    /// The state a seek began from (.playing or .paused); nil when not seeking.
    /// Preserved so a resolved seek returns to its TRUE origin (r3 finding).
    public private(set) var seekOrigin: PlayerLifecycleState? = nil
    public init() {}

    /// The ONE transition table (origin-agnostic part). Seek resolution is
    /// handled in apply because it depends on the recorded origin.
    /// Terminal states: closed, failed. Re-entrant beginSeek while seeking is
    /// ILLEGAL: a second seek must wait for the first to resolve.
    public static func allows(_ from: PlayerLifecycleState, _ control: PlayerControl) -> PlayerLifecycleState? {
        switch (from, control) {
        case (.idle, .beginLoad): return .loading
        case (.loading, .loadReady): return .ready
        case (.loading, .loadFailed): return .failed
        case (.ready, .play): return .playing
        case (.playing, .pause): return .paused
        case (.paused, .resume): return .playing
        case (.playing, .beginSeek), (.paused, .beginSeek): return .seeking
        case (.seeking, .seekRequiresClose): return .closing
        case (.ready, .close), (.playing, .close), (.paused, .close), (.seeking, .close), (.closing, .close): return .closing
        case (.closing, .closed): return .closed
        case (_, .fail): return from == .closed || from == .failed ? nil : .failed
        default: return nil
        }
    }

    /// Apply a control. Returns the new state on success; refused transitions
    /// leave state, origin AND generation untouched (fail-closed, observable).
    @discardableResult
    public mutating func apply(_ control: PlayerControl) -> Result<PlayerLifecycleState, PlayerControlRefusal> {
        if state == .closed || state == .failed {
            return .failure(.terminal(state))
        }
        // Seek resolution returns to the RECORDED origin (paused stays paused).
        if state == .seeking, control == .seekCommitted || control == .seekRefused {
            let target = seekOrigin ?? .playing
            seekOrigin = nil
            state = target
            generation &+= 1
            return .success(target)
        }
        guard let next = PlayerControlPlane.allows(state, control) else {
            return .failure(.illegalTransition(from: state, control: control))
        }
        if control == .beginSeek { seekOrigin = state }
        if next == .closing || next == .closed || next == .failed { seekOrigin = nil }
        state = next
        generation &+= 1
        return .success(next)
    }

    /// True when the plane is in a state where the host may legally begin a seek.
    public var seekAllowed: Bool { state == .playing || state == .paused }
    /// True when audio should render silence, for the audio pump's shouldPause
    /// closure - pure derivation, no clock access here.
    public var audioSilenced: Bool { state == .paused || state == .seeking }
}
