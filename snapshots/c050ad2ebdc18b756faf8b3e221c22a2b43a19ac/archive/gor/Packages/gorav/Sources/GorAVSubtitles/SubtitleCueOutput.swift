import Foundation

// Row 195b-56 (arch-195b): clock/session-fenced subtitle cue output. Sits
// Cue transition helper. SubtitleCueDelivery adds generation-tagged transport;
// the embedded session samples its film clock and MetalPresenter consumes batches.
// Sits between SubtitleController (selection state) and the renderer: per clock
// sample it emits typed appear/disappear events, emit-on-change only, fenced
// to one session, with the same one-clock rule as the timePos gate (a
// non-finite clock sample never advances or corrupts output state).

public enum CueOutputEvent: Equatable, Sendable {
    /// A cue became active for the slot. Carries the cue for direct render.
    case appeared(slot: SubtitleController.Slot, identity: SubtitleController.CueIdentity, cue: SubtitleCue)
    /// The slot's active cue ended (left its window) or was replaced.
    case disappeared(slot: SubtitleController.Slot, identity: SubtitleController.CueIdentity)
}

public struct SubtitleCueOutput: Sendable {

    public struct Counters: Equatable, Sendable {
        public var appeared = 0
        public var disappeared = 0
        /// Samples refused because the clock was non-finite.
        public var skippedNonFiniteClock = 0
        /// Samples refused because they carried another session.
        public var fencedSamples = 0
        /// Samples that changed nothing (steady state, no events).
        public var steady = 0
        /// reset() transitions that emitted clears for active slots.
        public var resets = 0
        public init() {}
    }

    public let session: UInt64
    public private(set) var counters = Counters()
    private var currentPrimary: SubtitleController.CueIdentity?
    private var currentSecondary: SubtitleController.CueIdentity?

    public init(session: UInt64) { self.session = session }

    /// Return explicit clears before dropping state. The caller must deliver
    /// these to its consumer or an old cue can remain visible through a seek.
    @discardableResult
    public mutating func reset() -> [CueOutputEvent] {
        var events: [CueOutputEvent] = []
        if let currentPrimary { events.append(.disappeared(slot: .primary, identity: currentPrimary)) }
        if let currentSecondary { events.append(.disappeared(slot: .secondary, identity: currentSecondary)) }
        counters.disappeared += events.count
        currentPrimary = nil
        currentSecondary = nil
        counters.resets += 1
        return events
    }

    /// One clock sample -> zero or more events. Order within a sample:
    /// disappeared events precede the appeared event that replaces them.
    @discardableResult
    public mutating func sample(session: UInt64, clock: Double,
                                controller: SubtitleController) -> [CueOutputEvent] {
        guard session == self.session else {
            counters.fencedSamples += 1
            return []
        }
        guard clock.isFinite else {
            counters.skippedNonFiniteClock += 1
            return []
        }
        var events: [CueOutputEvent] = []
        for slot in [SubtitleController.Slot.primary, .secondary] {
            let now = controller.activeCueIdentity(at: clock, slot: slot)
            let was = slot == .primary ? currentPrimary : currentSecondary
            guard now != was else { continue }
            if let was {
                events.append(.disappeared(slot: slot, identity: was))
                counters.disappeared += 1
            }
            if let now, let cue = controller.activeCue(at: clock, slot: slot) {
                events.append(.appeared(slot: slot, identity: now, cue: cue))
                counters.appeared += 1
            }
            if slot == .primary { currentPrimary = now } else { currentSecondary = now }
        }
        if events.isEmpty { counters.steady += 1 }
        return events
    }
}
