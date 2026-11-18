import Foundation

/// Time-ordered cue schedule with structural validation (lanes L5/L6, u2).
/// Pure model: the presenter hook (peer lane, interface pin pending) consumes
/// activeCue(at:). File order is preserved; structural issues are reported,
/// not silently repaired.
public struct SubtitleSchedule: Equatable, Sendable {

    public enum Issue: Equatable, Sendable {
        case outOfOrder(index: Int)          // start earlier than the previous cue's start
        case overlap(index: Int, previous: Int) // starts inside the previous cue's interval
    }

    public let cues: [SubtitleCue]
    public let issues: [Issue]

    public init(cues: [SubtitleCue]) {
        var found: [Issue] = []
        var maxStart = -Double.infinity
        for i in 0..<cues.count {
            // Out-of-order vs the running maximum start, not just the previous
            // cue: an early cue after several later ones is still flagged.
            if cues[i].startSeconds < maxStart {
                found.append(.outOfOrder(index: cues[i].index))
            }
            maxStart = max(maxStart, cues[i].startSeconds)
            // Overlap against EVERY earlier cue, not only the adjacent one:
            // out-of-order input can hide non-adjacent interval intersections.
            for j in 0..<i where cues[j].startSeconds < cues[i].endSeconds
                    && cues[i].startSeconds < cues[j].endSeconds {
                found.append(.overlap(index: cues[i].index, previous: cues[j].index))
            }
        }
        self.cues = cues
        self.issues = found
    }

    /// The active cue with the LATEST start whose half-open interval holds t,
    /// or nil. File order is irrelevant to the result (overlapping cues resolve
    /// to the latest-starting one; stacked rendering is a presenter decision,
    /// not a model one).
    public func activeCue(at t: Double) -> SubtitleCue? {
        var best: SubtitleCue? = nil
        for cue in cues where cue.contains(seconds: t) {
            if best == nil || cue.startSeconds > best!.startSeconds { best = cue }
        }
        return best
    }
}
