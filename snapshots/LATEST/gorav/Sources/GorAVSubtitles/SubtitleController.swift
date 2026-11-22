import Foundation

/// R7 (arch-195b): primary/secondary text cue selection with per-slot delay,
/// across seeks and reset. The schedule lookup is stateless, so a seek needs
/// no reload: cue identity (trackContentID, cue.index) survives any number of
/// seeks because the track content never changes under the controller.
public struct SubtitleController: Equatable, Sendable {

    public enum Slot: Equatable, Sendable { case primary, secondary }

    /// Identity of the currently displayed cue: stable across seeks, changes
    /// only when track content changes (a different file or a reload).
    public struct CueIdentity: Equatable, Sendable {
        public let trackContentID: UInt64
        public let cueIndex: Int
        public init(trackContentID: UInt64, cueIndex: Int) {
            self.trackContentID = trackContentID
            self.cueIndex = cueIndex
        }
    }

    public private(set) var primary: SubtitleTrack.Track?
    public private(set) var secondary: SubtitleTrack.Track?
    /// Seconds added to the cue timeline per slot: a positive delay shows cues
    /// later (query time minus delay). Default 0.
    public private(set) var primaryDelay: Double = 0
    public private(set) var secondaryDelay: Double = 0
    /// Set false to hide a slot without unloading it (mpv sub-visibility).
    public private(set) var primaryVisible = true
    public private(set) var secondaryVisible = true

    private var primaryContentID: UInt64 = 0
    private var secondaryContentID: UInt64 = 0
    private var primarySchedule: SubtitleSchedule?
    private var secondarySchedule: SubtitleSchedule?

    public init() {}

    public mutating func selectPrimary(_ track: SubtitleTrack.Track) {
        primary = track
        primarySchedule = SubtitleSchedule(cues: track.cues)
        primaryContentID = SubtitlePlanContentID.compute(cues: track.cues, styles: track.styles, playResX: track.playResX, playResY: track.playResY, unsupportedOverrides: track.unsupportedOverrides, skippedStyles: track.skippedStyles)
        primaryVisible = true
    }

    public mutating func selectSecondary(_ track: SubtitleTrack.Track) {
        secondary = track
        secondarySchedule = SubtitleSchedule(cues: track.cues)
        secondaryContentID = SubtitlePlanContentID.compute(cues: track.cues, styles: track.styles, playResX: track.playResX, playResY: track.playResY, unsupportedOverrides: track.unsupportedOverrides, skippedStyles: track.skippedStyles)
        secondaryVisible = true
    }

    public mutating func setDelay(_ seconds: Double, slot: Slot) {
        guard seconds.isFinite else { return }
        switch slot {
        case .primary: primaryDelay = seconds
        case .secondary: secondaryDelay = seconds
        }
    }

    public mutating func setVisible(_ visible: Bool, slot: Slot) {
        switch slot {
        case .primary: primaryVisible = visible
        case .secondary: secondaryVisible = visible
        }
    }

    /// Reset selection state: secondary unloaded, delays zeroed, both slots
    /// visible. The primary track stays loaded (mpv sub-reset semantics: the
    /// current external file remains the selected one).
    public mutating func reset() {
        secondary = nil
        secondarySchedule = nil
        secondaryContentID = 0
        primaryDelay = 0
        secondaryDelay = 0
        primaryVisible = true
        secondaryVisible = true
    }

    /// Active cue for one slot at film time `t` (delay applied). nil when the
    /// slot is empty, hidden, or no cue covers the shifted time.
    public func activeCue(at t: Double, slot: Slot) -> SubtitleCue? {
        switch slot {
        case .primary:
            guard primaryVisible, let s = primarySchedule else { return nil }
            return s.activeCue(at: t - primaryDelay)
        case .secondary:
            guard secondaryVisible, let s = secondarySchedule else { return nil }
            return s.activeCue(at: t - secondaryDelay)
        }
    }

    /// Identity of the active cue for one slot at film time `t`.
    public func activeCueIdentity(at t: Double, slot: Slot) -> CueIdentity? {
        guard let cue = activeCue(at: t, slot: slot) else { return nil }
        let tid = slot == .primary ? primaryContentID : secondaryContentID
        return CueIdentity(trackContentID: tid, cueIndex: cue.index)
    }
}
