import Foundation

/// Typed ingress for a HUD renderer. Rates are uploads/second, never display FPS.
/// This model does not alter the photon HUD or publish an OSD payload.
public struct CaptureHUDFeed: Equatable, Sendable {
    public enum IntervalState: Equatable, Sendable {
        case awaitingPreviousSample
        case measured
        case refused(CaptureStatsError)
    }
    public let snapshot: CaptureStatsSnapshot
    public let intervalState: IntervalState
    public let elapsedSeconds: Double?
    public let uploadsPerSecond: Double?
    public let visibleUploadsPerSecond: Double?
    public let readbacksPerSecond: Double?
    public let rejectedUploadsPerSecond: Double?

    public init(current: CaptureStatsSnapshot, previous: CaptureStatsSnapshot? = nil) {
        snapshot = current
        var interval: CaptureStatsInterval?
        if let previous {
            do {
                interval = try CaptureStatsInterval(from: previous, to: current)
                intervalState = .measured
            } catch let error as CaptureStatsError {
                intervalState = .refused(error)
            } catch {
                // CaptureStatsInterval currently throws only CaptureStatsError.
                intervalState = .refused(.invalidTimestamp)
            }
        } else {
            intervalState = .awaitingPreviousSample
        }
        elapsedSeconds = interval?.elapsedSeconds
        uploadsPerSecond = interval?.ratesPerSecond[.uploads]
        visibleUploadsPerSecond = interval?.ratesPerSecond[.visibleUploads]
        readbacksPerSecond = interval?.ratesPerSecond[.readbacks]
        rejectedUploadsPerSecond = interval?.ratesPerSecond[.uploadRejections]
    }
}
