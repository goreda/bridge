# W-gdb-005 195b-56/60 cue batch fixtures
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-005

```packet-json
{
 "packet_id": "W-gdb-005",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/GorAVSubtitles/SubtitleCueDelivery.swift",
   "excerpt_block": "source1"
  },
  {
   "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
   "excerpt_block": "source2"
  }
 ],
 "interface": {
  "signatures": "sample(session: UInt64, generation: UInt64, filmTime: Double, ...); advance() -> SubtitleCueBatch?; close() -> SubtitleCueBatch?; reset() -> [CueOutputEvent]",
  "types": "CueOutputEvent { appeared(slot,identity,cue), disappeared(slot,identity) }; CueIdentity { trackContentID: UInt64, cueIndex: Int }; Slot { primary, secondary }; SubtitleCueBatch { session, generation, sequence, reset, closed, events }",
  "ownership_lifetime": "batches are value types owned by the consumer; reset() clears must be delivered",
  "caller": "MetalPresenter's subtitle consumer via SubtitleCueConsumer",
  "callee": "SubtitleCueProducer.sample(session:generation:filmTime:...) / advance() / close() -> SubtitleCueBatch"
 },
 "test": {
  "command": "swift run cue-output-tests",
  "expected": "exit 0; final line 'cue-output-tests: N PASS, 0 FAIL' with N >= 74; pack-replay rows green; mutated expected row fails with its row id printed",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/cue-batch-fixtures/",
   "Sources/cue-output-tests/main.swift"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
subtitle cue output (rows 195b-56/60: sidecar discovery/load/select -> cue/clear batches) is covered by 74 Linux checks, but the batch-boundary fixtures are hand-built inside the suite; there is no independent deterministic fixture pack a second implementation or a reviewer can replay - batch boundary bugs (overlap, clear ordering, unicode) ship as wrong or flickering subtitles.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav).
- real source: Sources/cue-output-tests/main.swift (sha256 4037a67b, 20040B) - the 74-check suite; Sources/GorAVSubtitles/SubtitleSidecarSession.swift and Sources/GorAVSubtitles/SubtitleCueDelivery.swift (same pin) - the batching code under test.
- real test command: swift run cue-output-tests (74 PASS, 0 FAIL on Linux, Swift 6.1.2).

## expected behaviour
a deterministic cue-batch fixture pack: generator + expected tables for overlapping cue start/end at one instant, explicit clear events, out-of-order and zero-duration cues, unicode (Turkish dotted/dotless i, combining marks), and a 10000-cue ordering-stability case; expected active-set and clear tables per sample instant on a documented sampling grid.

## exact call site and interface
SubtitleCueDelivery's batch output shape (pinned files); the pack's expected tables are written against that shape so cue-output-tests can consume them.

## pinned ABI decisions (integrator, 2026-11-15)
batch transport types (SubtitleCueDelivery.swift / SubtitleCueOutput.swift / SubtitleController.swift, same pin):
- public enum CueOutputEvent: Equatable, Sendable { appeared(slot: SubtitleController.Slot, identity: SubtitleController.CueIdentity, cue: SubtitleCue); disappeared(slot: SubtitleController.Slot, identity: SubtitleController.CueIdentity) }
- public struct SubtitleController.CueIdentity: Equatable, Sendable { trackContentID: UInt64; cueIndex: Int } - stable across seeks; changes only on track content change
- public enum SubtitleController.Slot { primary, secondary }
- public struct SubtitleCueBatch: Equatable, Sendable { session: UInt64; generation: UInt64; sequence: UInt64; reset: Bool; closed: Bool; events: [CueOutputEvent] }
- ordering at the pin: within one sample, disappeared precedes the appeared event that replaces it; emit-on-change only; a non-finite clock sample never advances state; reset() returns explicit clears the caller MUST deliver.
fixture expected tables are written against exactly these shapes.

## behaviour that must not change
the 74 existing checks stay green; text fixtures only - no media bytes, fonts or captures.

## acceptance test (from the product repo)
the pack replays green against the pinned batching code; one mutated expected row fails; the 10000-cue case runs in bounded time on Linux.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVSubtitles/SubtitleCueDelivery.swift (sha256 c0def67c, lines 1-80 of 89)
```swift id=source1
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
```

### Sources/GorAVSubtitles/SubtitleCue.swift (sha256 2311ed30, lines 1-32 of 32)
```swift id=source2
import Foundation

/// One timed subtitle cue over the half-open interval [startSeconds, endSeconds).
/// Format-neutral: produced by the SRT (L5) and ASS (L6) parsers and consumed
/// by the future presenter hook (trunk-owned wiring, block-78 L8 allocation:
/// Sources/GorAVSubtitles is a new path; no trunk files touched here).
public struct SubtitleCue: Equatable, Sendable {
    public let index: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public let lines: [String]
    /// ASS Dialogue Style association, preserved for the future renderer.
    /// nil for SRT and for ASS events whose Format carries no Style field.
    /// This is an association record, not styling support.
    public let styleName: String?

    public init(index: Int, startSeconds: Double, endSeconds: Double, lines: [String], styleName: String? = nil) {
        self.index = index
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.lines = lines
        self.styleName = styleName
    }

    /// Cue text with original line breaks.
    public var text: String { lines.joined(separator: "\n") }

    /// Membership test on the half-open interval; inverted cues hold nothing.
    public func contains(seconds t: Double) -> Bool {
        t >= startSeconds && t < endSeconds
    }
}
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"grid":"100ms","batch":{"session":7,"generation":1,"sequence":3,"reset":false,"closed":false,"events":[{"appeared":{"slot":"primary","identity":{"trackContentID":11,"cueIndex":4}}},{"disappeared":{"slot":"secondary","identity":{"trackContentID":11,"cueIndex":2}}}]},"note":"disappeared precedes the appeared event that replaces it"}
```
