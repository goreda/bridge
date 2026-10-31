// SubtitleCueSelection.swift - M2 Q4 overlap-stacking rule, presenter side (block 168).
// DECIDED INTERFACE 2026-11-01 02:25 +03 (Documentation/gorav/M2-INTERFACE-DECISION-2026-11-01.md):
// half-open intervals [start,end); active set = cues covering t; one active -> render it;
// multiple -> LATEST-STARTING wins and every suppressed cue is REPORTED with its index
// (never silently stacked, never line-merged). Tie on equal start: earliest file order
// wins (strict > comparison, same convention as SubtitleSchedule.activeCue). Revisited
// when margin/alignment parsing lands (R2: those are unparsed today, never invented).
//
// Pure Swift, no Metal/AppKit/GorAVSubtitles import: the plan/cue TYPES stay
// goreda-owned; this selector is what our SubtitleCueProvider shim maps plan cues
// INTO. Linux-checkable standalone: swiftc -typecheck SubtitleCueSelection.swift
// Additive prep file: NOT in the GorAVMetalPresenter sources pin (wiring is the
// host-integration step, routed separately).

/// One cue's half-open timed interval, mapped from the producer plan model.
public struct CueInterval: Equatable, Sendable {
    /// Producer cue index (plan/model identity, echoed in findings).
    public let index: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public init(index: Int, startSeconds: Double, endSeconds: Double) {
        self.index = index; self.startSeconds = startSeconds; self.endSeconds = endSeconds
    }
    /// Half-open [start, end): a cue is active at its start, never at its end.
    public func contains(seconds t: Double) -> Bool {
        startSeconds <= t && t < endSeconds
    }
}

/// The Q4 finding: WHICH cue rendered and WHICH active cues were suppressed at t.
/// Reported (receipt/finding), counted never silent; a suppressed cue is a fact the
/// producer can audit, not a dropped error.
public struct SubtitleCueSelection: Equatable, Sendable {
    /// The cue to render (latest-starting active), nil when no cue covers t.
    public let activeIndex: Int?
    /// Indices of the OTHER cues that also cover t, ascending. Empty when no overlap.
    public let suppressedIndices: [Int]
    public init(activeIndex: Int?, suppressedIndices: [Int]) {
        self.activeIndex = activeIndex; self.suppressedIndices = suppressedIndices
    }
}

public enum SubtitleCueSelectionRule {
    /// Q4 decided rule. Result is independent of input ordering for the active pick
    /// (latest start wins; equal starts resolve to the earliest index among them).
    public static func select(at t: Double, cues: [CueInterval]) -> SubtitleCueSelection {
        var best: CueInterval? = nil
        var suppressed: [Int] = []
        for cue in cues where cue.contains(seconds: t) {
            if let b = best {
                if cue.startSeconds > b.startSeconds
                    || (cue.startSeconds == b.startSeconds && cue.index < b.index) {
                    suppressed.append(b.index)
                    best = cue
                } else {
                    suppressed.append(cue.index)
                }
            } else {
                best = cue
            }
        }
        return SubtitleCueSelection(activeIndex: best?.index, suppressedIndices: suppressed.sorted())
    }
}
