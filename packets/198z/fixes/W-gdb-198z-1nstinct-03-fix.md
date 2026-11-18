# W-gdb-198z-1nstinct-03-fix - Fence subtitle presentation by source generation

state: OPEN / unclaimed

Content identity is insufficient when a new source loads identical cues. Locate current source/session generation boundaries first. Add an explicit generation-bound request API that refuses prior-source requests even for identical cue content; preserve existing supported API behavior and clearly label the legacy content-only method. If enforcement requires SubtitleSidecarSession or host edits outside this lease, return the proposed interface and exact extra path instead of silently expanding scope. Add actual Swift same-content source-replacement negative regression plus seek/reset/primary-secondary isolation tests.

Boundary: No claim of renderer application or receipt-schema closure until producer wiring is separately verified.

Earliest verified claim; 2h progress lease. Work only on listed source and own tests. Isolated branch only, no product-main/delivery refs. Acceptance requires actual module Swift test and full provider package build; source models and excerpts do not establish integration. This fix packet is not counted in startable stock until its executable starter is supplied.

```packet-json
{
  "packet_id": "W-gdb-198z-1nstinct-03-fix",
  "lab": "1nstinct",
  "product_repo": "goreda/gorav",
  "product_sha": "d30de19c87377bab5b6b0bba68d3ed3ab02f5042",
  "paths": [
    "Sources/GorAVSubtitles/SubtitleController.swift"
  ],
  "test_paths": [
    "Tests/Architecture/198z/W-gdb-198z-1nstinct-03-fix.swift"
  ],
  "state": "OPEN",
  "lease_hours": 2,
  "scope": "product-fix",
  "evidence": "lane-b report85e0507605cafa84a473f69dfcaf39f4ffbda27899edc710b9d844a6a76c4c53",
  "stock_status": "NOT_COUNTED until executable exact-source starter and reviewed test binding are supplied"
}
```

## Sources/GorAVSubtitles/SubtitleController.swift sha256 0272a599b66f255062aaefcb541d252b10cd65818189dac237a688dc567f1144
```swift
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
    /// Per-slot font scale, clamped to [0.25, 4.0]; default 1.0.
    public private(set) var primaryFontScale: Double = 1
    public private(set) var secondaryFontScale: Double = 1
    /// Per-slot vertical position as a fraction of screen height, clamped to
    /// [0.0, 1.0]; default 1.0 (bottom, mpv sub-pos convention).
    public private(set) var primaryVerticalPosition: Double = 1
    public private(set) var secondaryVerticalPosition: Double = 1

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

    public static let delayLimitSeconds = 600.0
    public static let fontScaleRange: ClosedRange<Double> = 0.25...4.0

    /// Delay is clamped to +/-600s; non-finite values are ignored as before.
    public mutating func setDelay(_ seconds: Double, slot: Slot) {
        guard seconds.isFinite else { return }
        let clamped = min(max(seconds, -SubtitleController.delayLimitSeconds), SubtitleController.delayLimitSeconds)
        switch slot {
        case .primary: primaryDelay = clamped
        case .secondary: secondaryDelay = clamped
        }
    }

    /// Font scale, clamped to fontScaleRange; non-finite values are ignored.
    public mutating func setFontScale(_ scale: Double, slot: Slot) {
        guard scale.isFinite else { return }
        let clamped = min(max(scale, SubtitleController.fontScaleRange.lowerBound), SubtitleController.fontScaleRange.upperBound)
        switch slot {
        case .primary: primaryFontScale = clamped
        case .secondary: secondaryFontScale = clamped
        }
    }

    /// Vertical position as a screen-height fraction, clamped to [0, 1].
    public mutating func setVerticalPosition(_ position: Double, slot: Slot) {
        guard position.isFinite else { return }
        let clamped = min(max(position, 0), 1)
        switch slot {
        case .primary: primaryVerticalPosition = clamped
        case .secondary: secondaryVerticalPosition = clamped
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
        primaryFontScale = 1
        secondaryFontScale = 1
        primaryVerticalPosition = 1
        secondaryVerticalPosition = 1
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

    /// Settings readback for one slot.
    public struct PresentationSettings: Equatable, Sendable {
        public let fontScale: Double
        public let verticalPosition: Double
        public let delay: Double
        public let visible: Bool
        public init(fontScale: Double, verticalPosition: Double, delay: Double, visible: Bool) {
            self.fontScale = fontScale; self.verticalPosition = verticalPosition
            self.delay = delay; self.visible = visible
        }
    }

    public enum PresentationRefusal: Error, Equatable, Sendable {
        /// Settings were addressed to a source generation that is no longer
        /// loaded in the slot: rejected, never silently applied.
        case staleSource
        /// Stereo/3D depth for subtitles is not supported: a named refusal,
        /// never a silent no-op or a guessed value.
        case stereoDepthUnsupported
    }

    /// Readback of the live presentation settings for one slot.
    public func presentationReadback(slot: Slot) -> PresentationSettings {
        switch slot {
        case .primary:
            return PresentationSettings(fontScale: primaryFontScale, verticalPosition: primaryVerticalPosition, delay: primaryDelay, visible: primaryVisible)
        case .secondary:
            return PresentationSettings(fontScale: secondaryFontScale, verticalPosition: secondaryVerticalPosition, delay: secondaryDelay, visible: secondaryVisible)
        }
    }

    /// The content ID of the track loaded in one slot, nil when empty.
    public func contentID(slot: Slot) -> UInt64? {
        switch slot {
        case .primary: return primary == nil ? nil : primaryContentID
        case .secondary: return secondary == nil ? nil : secondaryContentID
        }
    }

    /// Apply a full settings snapshot addressed to the slot's current content
    /// ID. A stale source identity is rejected and nothing is applied.
    @discardableResult
    public mutating func applyPresentation(_ settings: PresentationSettings, slot: Slot, forContentID expected: UInt64) -> Result<Void, PresentationRefusal> {
        guard contentID(slot: slot) == expected else { return .failure(.staleSource) }
        setFontScale(settings.fontScale, slot: slot)
        setVerticalPosition(settings.verticalPosition, slot: slot)
        setDelay(settings.delay, slot: slot)
        setVisible(settings.visible, slot: slot)
        return .success(())
    }

    /// Stereo depth stays a named refusal; there is no supported value.
    @discardableResult
    public mutating func setStereoDepth(_ depth: Double, slot: Slot) -> PresentationRefusal {
        .stereoDepthUnsupported
    }
}

```

Executable RED starter published at packets/198z/fix-starters/W-gdb-198z-1nstinct-03-fix/run.py. From bridge root: python3 packets/198z/fix-starters/W-gdb-198z-1nstinct-03-fix/run.py. PRODUCT_ROOT points at your modified exact-pin product checkout. Starter kind whole-subtitle-source-set; provider/full integration gate remains NOT_RUN. Preserve legacy APIs; new generation API needs new acceptance tests.
