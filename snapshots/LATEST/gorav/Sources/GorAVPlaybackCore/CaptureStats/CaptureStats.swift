import Foundation

/// Counters retain their producer's meaning. Upload is not proof of presentation.
public enum CaptureCounter: String, CaseIterable, Sendable {
    case uploads, visibleUploads, noPixels, resizeEvents
    case fullscreenEntries, fullscreenExits, drawableNilPresents, readbacks
    case uploadRejections, staleWorkAfterClose, sealResidualEvents
    case sealResidualPending, geometryRejections, windowModeNoOps
    case sequenceExhausted, ticketedCommits, ticketRefusals
}

public enum CaptureStatsSource: String, Sendable { case metalPresenter }

public enum CaptureStatsError: Error, Equatable {
    case invalidTimestamp
    case differentSource
    case differentSession
    case nonIncreasingTime
    case counterRegressed(CaptureCounter)
}

/// A measured zero is present as zero; an unmeasured counter is absent.
/// No FPS, CPU, thermal, decoder, or display-completion claim is synthesized.
public struct CaptureStatsSnapshot: Equatable, Sendable {
    public let source: CaptureStatsSource
    public let sessionID: UUID
    public let monotonicSeconds: Double
    public let counters: [CaptureCounter: UInt64]
    public let closedByUser: Bool

    public init(source: CaptureStatsSource, sessionID: UUID,
                monotonicSeconds: Double, counters: [CaptureCounter: UInt64],
                closedByUser: Bool) throws {
        guard monotonicSeconds.isFinite, monotonicSeconds >= 0 else {
            throw CaptureStatsError.invalidTimestamp
        }
        self.source = source
        self.sessionID = sessionID
        self.monotonicSeconds = monotonicSeconds
        self.counters = counters
        self.closedByUser = closedByUser
    }

    public subscript(_ counter: CaptureCounter) -> UInt64? { counters[counter] }
}

/// Rates apply only to counters observed at both endpoints in the same session.
/// sealResidualPending is a gauge and is never turned into a rate.
public struct CaptureStatsInterval: Equatable, Sendable {
    public let elapsedSeconds: Double
    public let deltas: [CaptureCounter: UInt64]
    public let ratesPerSecond: [CaptureCounter: Double]

    public init(from earlier: CaptureStatsSnapshot, to later: CaptureStatsSnapshot) throws {
        guard earlier.source == later.source else { throw CaptureStatsError.differentSource }
        guard earlier.sessionID == later.sessionID else { throw CaptureStatsError.differentSession }
        let elapsed = later.monotonicSeconds - earlier.monotonicSeconds
        guard elapsed.isFinite, elapsed > 0 else { throw CaptureStatsError.nonIncreasingTime }
        var deltas: [CaptureCounter: UInt64] = [:]
        var rates: [CaptureCounter: Double] = [:]
        for key in CaptureCounter.allCases where key != .sealResidualPending {
            guard let before = earlier[key], let after = later[key] else { continue }
            guard after >= before else { throw CaptureStatsError.counterRegressed(key) }
            let delta = after - before
            let rate = Double(delta) / elapsed
            guard rate.isFinite else { throw CaptureStatsError.invalidTimestamp }
            deltas[key] = delta
            rates[key] = rate
        }
        elapsedSeconds = elapsed
        self.deltas = deltas
        ratesPerSecond = rates
    }
}
