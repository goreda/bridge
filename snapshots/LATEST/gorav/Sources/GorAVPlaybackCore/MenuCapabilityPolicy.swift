// Pure capability-to-menu policy. A method existing in source is not evidence
// that its session dependencies are installed. Hosts supply a fresh snapshot.
// This policy does not install handlers or claim host-menu integration.
public enum MenuPlaybackAction: String, CaseIterable, Hashable, Sendable {
    case pause, resume, seek, volume, audioTrack, audioDelay
    case subtitleSelect, subtitleDelay, subtitleVisibility, hostTransform
}

public struct MenuCapabilitySnapshot: Equatable, Sendable {
    public let lifecycle: PlayerLifecycleState
    // Only include operations whose runtime dependencies are available now.
    // Empty by default: never infer support from an engine name or a code ledger.
    public let available: Set<MenuPlaybackAction>
    public let fenced: Bool
    public let tornDown: Bool
    public let handoffPending: Bool
    public let preparedTimeline: Bool

    public init(lifecycle: PlayerLifecycleState,
                available: Set<MenuPlaybackAction> = [],
                fenced: Bool = false, tornDown: Bool = false,
                handoffPending: Bool = false, preparedTimeline: Bool = false) {
        self.lifecycle = lifecycle; self.available = available
        self.fenced = fenced; self.tornDown = tornDown
        self.handoffPending = handoffPending; self.preparedTimeline = preparedTimeline
    }
}

public protocol MenuCapabilityProviding {
    var menuCapabilitySnapshot: MenuCapabilitySnapshot { get }
}

public enum MenuCapabilityRefusal: Equatable, Sendable {
    case sessionUnavailable, transitionInProgress, dependencyUnavailable
    case lifecycleUnavailable, preparedTimelineOwnsSeek
}

public enum MenuCapabilityDecision: Equatable, Sendable {
    case enabled
    case disabled(MenuCapabilityRefusal)
    public var isEnabled: Bool { self == .enabled }
}

public enum MenuCapabilityPolicy {
    public static func decision(for action: MenuPlaybackAction,
                                snapshot s: MenuCapabilitySnapshot) -> MenuCapabilityDecision {
        if s.fenced || s.tornDown { return .disabled(.sessionUnavailable) }
        switch s.lifecycle {
        case .idle, .loading, .closing, .closed, .failed:
            return .disabled(.sessionUnavailable)
        case .ready, .playing, .paused, .seeking: break
        }
        if s.handoffPending { return .disabled(.transitionInProgress) }
        guard s.available.contains(action) else { return .disabled(.dependencyUnavailable) }
        switch action {
        case .pause:
            guard PlayerControlPlane.allows(s.lifecycle, .pause) != nil else {
                return .disabled(.lifecycleUnavailable)
            }
        case .resume:
            guard PlayerControlPlane.allows(s.lifecycle, .resume) != nil else {
                return .disabled(.lifecycleUnavailable)
            }
        case .seek:
            if s.preparedTimeline { return .disabled(.preparedTimelineOwnsSeek) }
            guard PlayerControlPlane.allows(s.lifecycle, .beginSeek) != nil else {
                return .disabled(.lifecycleUnavailable)
            }
        case .volume, .audioTrack, .audioDelay, .subtitleSelect,
             .subtitleDelay, .subtitleVisibility, .hostTransform:
            // Conservatively serialize menu operations with a seek. Runtime
            // handlers still own argument validation and final admission.
            guard s.lifecycle == .playing || s.lifecycle == .paused else {
                return .disabled(.lifecycleUnavailable)
            }
        }
        return .enabled
    }
}
