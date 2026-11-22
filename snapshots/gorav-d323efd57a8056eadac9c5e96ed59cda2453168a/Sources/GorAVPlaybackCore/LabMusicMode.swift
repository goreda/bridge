// Lab music-mode classification (G0747 / 195b-B10, lab: 1nstinct), additive
// consumer seam. Ported line-faithful from the classification core of
// kits/b10-musicmode/src/music_mode.c (mm_session_evaluate); the C carrier
// with its own 45-check suite stays vendored in kits/b10-musicmode as the
// executable witness.
//
// SCOPE (narrowed per the 052 gate verdict): identity/classification ONLY.
// Artwork byte extraction (artwork_extract.c: ID3v2 APIC / FLAC PICTURE /
// MP4 covr) is NOT ported - no pinned artwork byte API exists at this pin and
// no pinned read(trackIndex) exists, so bytes cannot be grounded. The
// background state is therefore reported WITHOUT artwork distinction
// (black, no-art variant) and artwork availability is always false here.
//
// PIN MAPPING: the lab's raw n_video==0 rule becomes the pinned product rule
// "audio present AND zero NON-attached-picture video tracks" - callers derive
// nonAttachedVideoTracks from MediaInventory filtering Track.isAttachedPicture
// (an attached picture is album art, not a playable video track).

public enum LabMusicEngineMode: String, Equatable, Sendable {
    case video, audioOnly
}

public enum LabMusicModeReason: String, Equatable, Sendable {
    case none, explicitToggle, noVideoTrack
}

/// Background the render core should show, per the lab state machine. The
/// artwork-present variant is unreachable from this seam (see header note).
public enum LabMusicBackground: String, Equatable, Sendable {
    case video, black, blackNoArt
}

public struct LabMusicPresentation: Equatable, Sendable {
    public var engineMode: LabMusicEngineMode = .video
    public var reason: LabMusicModeReason = .none
    public var background: LabMusicBackground = .video
    /// Always false from this seam: artwork bytes are unpinnable at this pin.
    public var artworkAvailable = false
    /// Monotonic per-session identity; bump via reset(reason:) on track change.
    public var sessionGeneration = 0
    public init() {}
}

/// Audio-only/music-session classifier. Value type: one per source session.
/// Mirrors mm_session_create/reset/set_explicit_audio_only/
/// set_track_inventory/evaluate from the vendored C.
public struct LabMusicModeSession: Equatable, Sendable {
    public private(set) var presentation = LabMusicPresentation()
    private var explicitAudioOnly = false
    private var nonAttachedVideoTracks = 0
    private var audioTracks = 0

    public init() {}

    /// Call on track change (the C mm_session_reset): clears the inventory
    /// and bumps the generation, so stale presentations are detectable by
    /// identity. The explicit toggle SURVIVES reset, exactly like the C
    /// carrier (music_mode.h: "clears artwork, keeps explicit-toggle
    /// intent") - an earlier revision cleared it here, diverging from the
    /// carrier; caught by the kits/b10-musicmode parity harness.
    public mutating func reset() {
        nonAttachedVideoTracks = 0
        audioTracks = 0
        presentation.sessionGeneration &+= 1
    }

    /// Host toggle: explicit audio-only wins over the inventory rule.
    public mutating func setExplicitAudioOnly(_ on: Bool) { explicitAudioOnly = on }

    /// Inventory from MediaInventory: audio track count, and video track
    /// count EXCLUDING attached pictures (the pinned music-session rule).
    public mutating func setTrackInventory(audioTracks: Int, nonAttachedVideoTracks: Int) {
        self.audioTracks = max(0, audioTracks)
        self.nonAttachedVideoTracks = max(0, nonAttachedVideoTracks)
    }

    /// The lab mm_session_evaluate precedence, exactly:
    /// explicit toggle > audio present with zero non-attached video > video.
    public mutating func evaluate() -> LabMusicPresentation {
        if explicitAudioOnly {
            presentation.engineMode = .audioOnly
            presentation.reason = .explicitToggle
        } else if audioTracks > 0 && nonAttachedVideoTracks == 0 {
            presentation.engineMode = .audioOnly
            presentation.reason = .noVideoTrack
        } else {
            presentation.engineMode = .video
            presentation.reason = .none
        }
        presentation.background = presentation.engineMode == .audioOnly ? .blackNoArt : .video
        return presentation
    }
}
