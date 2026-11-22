import Foundation

/// A delivery unit, fenced by source session and seek generation. Reset is an
/// unconditional clear, even when the helper has no remembered active cue.
public struct SubtitleCueBatch: Equatable, Sendable {
    public let session: UInt64
    public let generation: UInt64
    public let sequence: UInt64
    public let reset: Bool
    public let closed: Bool
    public let events: [CueOutputEvent]
    public init(session: UInt64, generation: UInt64, sequence: UInt64, reset: Bool,
                closed: Bool = false, events: [CueOutputEvent]) {
        self.session = session; self.generation = generation; self.sequence = sequence
        self.reset = reset; self.closed = closed; self.events = events
    }
}

/// Producer used by the embedded session's real film-clock observer. Calls are
/// serialized by that session; an await must capture and recheck generation.
public struct SubtitleCueProducer: Sendable {
    public let session: UInt64
    public private(set) var generation: UInt64 = 0
    private var output: SubtitleCueOutput
    private var sequence: UInt64 = 0
    private var closed = false
    public init(session: UInt64) { self.session = session; output = SubtitleCueOutput(session: session) }
    public mutating func sample(session: UInt64, generation: UInt64, filmTime: Double,
                                controller: SubtitleController) -> SubtitleCueBatch? {
        guard !closed, session == self.session, generation == self.generation, filmTime.isFinite else { return nil }
        let events = output.sample(session: session, clock: filmTime, controller: controller)
        guard !events.isEmpty else { return nil }
        return batch(reset: false, events: events)
    }
    /// Seek/reset/replace clears are returned for immediate delivery, not discarded.
    /// Refuses generation exhaustion rather than wrapping into a stale identity.
    public mutating func advance() -> SubtitleCueBatch? {
        guard !closed, generation < UInt64.max else { return nil }
        generation += 1
        return batch(reset: true, events: output.reset())
    }
    public mutating func close() -> SubtitleCueBatch? {
        guard !closed else { return nil }
        let events = output.reset(); closed = true
        return batch(reset: true, events: events, terminal: true)
    }
    private mutating func batch(reset: Bool, events: [CueOutputEvent], terminal: Bool = false) -> SubtitleCueBatch? {
        guard sequence < UInt64.max else { return nil }
        sequence += 1
        return SubtitleCueBatch(session: session, generation: generation, sequence: sequence,
                                reset: reset, closed: terminal, events: events)
    }
}

/// Render-side state, used directly by MetalPresenter before its text-view update.
/// Future generations must begin with a reset clear. Stale disappear events never
/// clear a newer cue with a different identity. Close permanently fences a session.
public struct SubtitleCueConsumer: Sendable {
    public struct Active: Equatable, Sendable {
        public let identity: SubtitleController.CueIdentity
        public let cue: SubtitleCue
    }
    public let session: UInt64
    public private(set) var generation: UInt64 = 0
    public private(set) var primary: Active?
    public private(set) var secondary: Active?
    private var sequence: UInt64 = 0
    private var closed = false
    public init(session: UInt64) { self.session = session }
    @discardableResult
    public mutating func consume(_ batch: SubtitleCueBatch) -> Bool {
        guard !closed, batch.session == session, batch.generation >= generation,
              batch.sequence > sequence, batch.generation == generation || batch.reset else { return false }
        if batch.reset { primary = nil; secondary = nil }
        generation = batch.generation; sequence = batch.sequence
        for event in batch.events {
            switch event {
            case .appeared(let slot, let id, let cue):
                let value = Active(identity: id, cue: cue)
                if slot == .primary { primary = value } else { secondary = value }
            case .disappeared(let slot, let id):
                if slot == .primary, primary?.identity == id { primary = nil }
                if slot == .secondary, secondary?.identity == id { secondary = nil }
            }
        }
        if batch.closed { primary = nil; secondary = nil; closed = true }
        return true
    }
}
