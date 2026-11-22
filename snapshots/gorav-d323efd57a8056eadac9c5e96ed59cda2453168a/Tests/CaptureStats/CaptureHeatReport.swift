import Foundation

/// D8Probes-compatible CPU submission timestamps, not CPU service time or GPU time.
/// A bridge must supply the presenter's session identity; no identity is inferred.
public struct CaptureSubmissionSample: Equatable, Sendable {
    public let sessionID: UUID
    public let frameID: UInt64
    public let beginSeconds: Double
    public let commitEndSeconds: Double?

    public init(sessionID: UUID, frameID: UInt64, beginSeconds: Double,
                commitEndSeconds: Double?) {
        self.sessionID = sessionID
        self.frameID = frameID
        self.beginSeconds = beginSeconds
        self.commitEndSeconds = commitEndSeconds
    }
}

public enum CaptureHeatReportError: Error, Equatable, Sendable {
    case foreignSession
    case duplicateFrame
    case invalidSubmissionTime
}

/// Threshold-free evidence only. No pass/fail, heat diagnosis, CPU percentage,
/// thermal state, watts, decode duration or GPU completion is inferred from counts.
/// Missing D8 probes remain unavailable, even when upload counters are present.
public struct CaptureHeatReport: Equatable, Sendable {
    public let presenter: CaptureHUDFeed
    public let completeSubmissionSamples: Int
    public let incompleteSubmissionSamples: Int
    public let meanSubmissionWallSeconds: Double?
    public let maxSubmissionWallSeconds: Double?

    public init(presenter: CaptureHUDFeed,
                submissionSamples: [CaptureSubmissionSample] = []) throws {
        var seen = Set<UInt64>()
        var durations: [Double] = []
        var incomplete = 0
        for sample in submissionSamples {
            guard sample.sessionID == presenter.snapshot.sessionID else {
                throw CaptureHeatReportError.foreignSession
            }
            guard seen.insert(sample.frameID).inserted else {
                throw CaptureHeatReportError.duplicateFrame
            }
            guard sample.beginSeconds.isFinite, sample.beginSeconds >= 0,
                  sample.beginSeconds <= presenter.snapshot.monotonicSeconds else {
                throw CaptureHeatReportError.invalidSubmissionTime
            }
            guard let end = sample.commitEndSeconds else {
                incomplete += 1
                continue
            }
            guard end.isFinite, end >= sample.beginSeconds,
                  end <= presenter.snapshot.monotonicSeconds else {
                throw CaptureHeatReportError.invalidSubmissionTime
            }
            let duration = end - sample.beginSeconds
            guard duration.isFinite else { throw CaptureHeatReportError.invalidSubmissionTime }
            durations.append(duration)
        }
        self.presenter = presenter
        completeSubmissionSamples = durations.count
        incompleteSubmissionSamples = incomplete
        // Divide before summing to avoid overflow from a large finite total.
        let mean = durations.isEmpty ? nil : durations.reduce(0) { $0 + $1 / Double(durations.count) }
        if let mean, !mean.isFinite { throw CaptureHeatReportError.invalidSubmissionTime }
        meanSubmissionWallSeconds = mean
        maxSubmissionWallSeconds = durations.max()
    }
}
