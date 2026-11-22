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
    /// First 64 witnesses in original document order.
    public let issues: [Issue]
    /// Exact count, including witnesses beyond the bounded list.
    public let issueTotal: Int

    /// Coordinate-compressed Fenwick index of earlier cue (start,end) pairs.
    /// Each prefix node contains a second Fenwick tree over its end values.
    private struct OverlapIndex {
        var starts: [Double]
        var ends: [[Double]]
        var counts: [[Int]]

        static func lowerBound(_ values: [Double], _ value: Double) -> Int {
            var lo = 0, hi = values.count
            while lo < hi {
                let mid = lo + (hi - lo) / 2
                if values[mid] < value { lo = mid + 1 } else { hi = mid }
            }
            return lo
        }
        static func upperBound(_ values: [Double], _ value: Double) -> Int {
            var lo = 0, hi = values.count
            while lo < hi {
                let mid = lo + (hi - lo) / 2
                if values[mid] <= value { lo = mid + 1 } else { hi = mid }
            }
            return lo
        }
        static func unique(_ values: [Double]) -> [Double] {
            var result: [Double] = []
            for value in values.sorted() where result.last != value { result.append(value) }
            return result
        }
        init(_ cues: [SubtitleCue]) {
            starts = Self.unique(cues.filter { !$0.startSeconds.isNaN && !$0.endSeconds.isNaN }.map(\.startSeconds))
            ends = Array(repeating: [], count: starts.count + 1)
            counts = []
            for cue in cues where !cue.startSeconds.isNaN && !cue.endSeconds.isNaN {
                var node = Self.lowerBound(starts, cue.startSeconds) + 1
                while node < ends.count {
                    ends[node].append(cue.endSeconds)
                    node += node & -node
                }
            }
            for node in ends.indices { ends[node] = Self.unique(ends[node]) }
            counts = ends.map { Array(repeating: 0, count: $0.count + 1) }
        }
        mutating func insert(_ cue: SubtitleCue) {
            guard !cue.startSeconds.isNaN, !cue.endSeconds.isNaN else { return }
            var node = Self.lowerBound(starts, cue.startSeconds) + 1
            while node < ends.count {
                var position = Self.lowerBound(ends[node], cue.endSeconds) + 1
                while position < counts[node].count {
                    counts[node][position] += 1
                    position += position & -position
                }
                node += node & -node
            }
        }
        func overlaps(_ cue: SubtitleCue) -> Int {
            guard !cue.startSeconds.isNaN, !cue.endSeconds.isNaN else { return 0 }
            // start < current.end AND end > current.start, exactly as before.
            var node = Self.lowerBound(starts, cue.endSeconds)
            var result = 0
            while node > 0 {
                func prefix(_ limit: Int) -> Int {
                    var position = limit, sum = 0
                    while position > 0 {
                        sum += counts[node][position]
                        position -= position & -position
                    }
                    return sum
                }
                result += prefix(ends[node].count) - prefix(Self.upperBound(ends[node], cue.startSeconds))
                node -= node & -node
            }
            return result
        }
    }

    public init(cues: [SubtitleCue]) {
        var found: [Issue] = []
        var total = 0
        var index = OverlapIndex(cues)
        var maxStart = -Double.infinity
        for i in cues.indices {
            if cues[i].startSeconds < maxStart {
                total += 1
                if found.count < 64 { found.append(.outOfOrder(index: cues[i].index)) }
            }
            maxStart = max(maxStart, cues[i].startSeconds)
            let overlaps = index.overlaps(cues[i])
            total += overlaps
            // A scan is needed only while recovering bounded witnesses and
            // only on a row known to contain an overlap. At most 64 rows scan.
            if found.count < 64 && overlaps > 0 {
                for j in 0..<i where cues[j].startSeconds < cues[i].endSeconds
                        && cues[i].startSeconds < cues[j].endSeconds {
                    found.append(.overlap(index: cues[i].index, previous: cues[j].index))
                    if found.count == 64 { break }
                }
            }
            index.insert(cues[i])
        }
        self.cues = cues
        self.issues = found
        self.issueTotal = total
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
