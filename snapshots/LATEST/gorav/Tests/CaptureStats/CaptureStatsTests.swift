import Foundation
import XCTest
@testable import CaptureStats

final class CaptureStatsTests: XCTestCase {
    private func sample(_ t: Double, _ counters: [CaptureCounter: UInt64],
                        id: UUID) throws -> CaptureStatsSnapshot {
        try CaptureStatsSnapshot(source: .metalPresenter, sessionID: id,
            monotonicSeconds: t, counters: counters, closedByUser: false)
    }

    func testUnavailableIsNotMeasuredZero() throws {
        let s = try sample(0, [.uploads: 0], id: UUID())
        XCTAssertEqual(s[.uploads], 0)
        XCTAssertNil(s[.visibleUploads])
    }

    func testRateUsesActualDeltaAndElapsedTime() throws {
        let id = UUID()
        let a = try sample(2, [.uploads: 10, .visibleUploads: 9], id: id)
        let b = try sample(4, [.uploads: 16, .visibleUploads: 11, .readbacks: 5], id: id)
        let interval = try CaptureStatsInterval(from: a, to: b)
        XCTAssertEqual(interval.elapsedSeconds, 2)
        XCTAssertEqual(interval.deltas[.uploads], 6)
        XCTAssertEqual(interval.ratesPerSecond[.uploads], 3)
        XCTAssertEqual(interval.ratesPerSecond[.visibleUploads], 1)
        XCTAssertNil(interval.deltas[.readbacks])
    }

    func testSessionAndTimeRefusals() throws {
        let id = UUID()
        let a = try sample(2, [.uploads: 10], id: id)
        XCTAssertThrowsError(try CaptureStatsInterval(from: a,
            to: sample(3, [.uploads: 12], id: UUID()))) {
            XCTAssertEqual($0 as? CaptureStatsError, .differentSession)
        }
        for t in [1.0, 2.0] {
            XCTAssertThrowsError(try CaptureStatsInterval(from: a,
                to: sample(t, [.uploads: 12], id: id))) {
                XCTAssertEqual($0 as? CaptureStatsError, .nonIncreasingTime)
            }
        }
        for t in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertThrowsError(try sample(t, [:], id: id))
        }
    }

    func testCounterRegressionRefusedButGaugeMayDecrease() throws {
        let id = UUID()
        let a = try sample(1, [.uploads: 8, .sealResidualPending: 4], id: id)
        XCTAssertThrowsError(try CaptureStatsInterval(from: a,
            to: sample(2, [.uploads: 7], id: id))) {
            XCTAssertEqual($0 as? CaptureStatsError, .counterRegressed(.uploads))
        }
        let good = try CaptureStatsInterval(from: a,
            to: sample(2, [.uploads: 9, .sealResidualPending: 0], id: id))
        XCTAssertNil(good.deltas[.sealResidualPending])
    }

    func testOverflowDoesNotWrap() throws {
        let id = UUID()
        let a = try sample(1, [.uploads: 0], id: id)
        let b = try sample(2, [.uploads: UInt64.max], id: id)
        XCTAssertEqual(try CaptureStatsInterval(from: a, to: b).deltas[.uploads], UInt64.max)
        let c = try sample(Double.leastNonzeroMagnitude, [.uploads: UInt64.max], id: id)
        XCTAssertThrowsError(try CaptureStatsInterval(from: sample(0, [.uploads: 0], id: id), to: c))
    }

    func testProductionPresenterWiringAndResetIdentity() async throws {
        try await MainActor.run {
            MetalPresenterTelemetry.reset()
            let a = try MetalPresenterTelemetry.captureStatsSnapshot()
            XCTAssertEqual(a.counters.count, CaptureCounter.allCases.count)
            XCTAssertEqual(a[.uploads], 0)
            MetalPresenterTelemetry.uploads = 37
            MetalPresenterTelemetry.visibleUploads = 12
            MetalPresenterTelemetry.closedByUser = true
            MetalPresenterTelemetry.readbacks = -1
            let b = try MetalPresenterTelemetry.captureStatsSnapshot()
            XCTAssertEqual(a.sessionID, b.sessionID)
            XCTAssertEqual(b[.uploads], 37)
            XCTAssertEqual(b[.visibleUploads], 12)
            XCTAssertTrue(b.closedByUser)
            XCTAssertNil(b[.readbacks])
            XCTAssertGreaterThanOrEqual(b.monotonicSeconds, a.monotonicSeconds)
            MetalPresenterTelemetry.reset()
            let c = try MetalPresenterTelemetry.captureStatsSnapshot()
            XCTAssertNotEqual(b.sessionID, c.sessionID)
            XCTAssertEqual(c[.uploads], 0)
            MetalPresenterTelemetry.beginSession()
            XCTAssertNotEqual(c.sessionID, try MetalPresenterTelemetry.captureStatsSnapshot().sessionID)
        }
    }
    func testEveryCounterIsWiredWithoutSubstitution() async throws {
        try await MainActor.run {
            MetalPresenterTelemetry.reset()
            MetalPresenterTelemetry.uploads = 1
            MetalPresenterTelemetry.visibleUploads = 2
            MetalPresenterTelemetry.noPixels = 3
            MetalPresenterTelemetry.resizeEvents = 4
            MetalPresenterTelemetry.fullscreenEntries = 5
            MetalPresenterTelemetry.fullscreenExits = 6
            MetalPresenterTelemetry.drawableNilPresents = 7
            MetalPresenterTelemetry.readbacks = 8
            MetalPresenterTelemetry.uploadRejections = 9
            MetalPresenterTelemetry.staleWorkAfterClose = 10
            MetalPresenterTelemetry.sealResidualEvents = 11
            MetalPresenterTelemetry.sealResidualPending = 12
            MetalPresenterTelemetry.geometryRejections = 13
            MetalPresenterTelemetry.windowModeNoOps = 14
            MetalPresenterTelemetry.sequenceExhausted = 15
            MetalPresenterTelemetry.ticketedCommits = 16
            MetalPresenterTelemetry.ticketRefusals = 17
            let s = try MetalPresenterTelemetry.captureStatsSnapshot()
            XCTAssertEqual(s[.uploads], 1)
            XCTAssertEqual(s[.visibleUploads], 2)
            XCTAssertEqual(s[.noPixels], 3)
            XCTAssertEqual(s[.resizeEvents], 4)
            XCTAssertEqual(s[.fullscreenEntries], 5)
            XCTAssertEqual(s[.fullscreenExits], 6)
            XCTAssertEqual(s[.drawableNilPresents], 7)
            XCTAssertEqual(s[.readbacks], 8)
            XCTAssertEqual(s[.uploadRejections], 9)
            XCTAssertEqual(s[.staleWorkAfterClose], 10)
            XCTAssertEqual(s[.sealResidualEvents], 11)
            XCTAssertEqual(s[.sealResidualPending], 12)
            XCTAssertEqual(s[.geometryRejections], 13)
            XCTAssertEqual(s[.windowModeNoOps], 14)
            XCTAssertEqual(s[.sequenceExhausted], 15)
            XCTAssertEqual(s[.ticketedCommits], 16)
            XCTAssertEqual(s[.ticketRefusals], 17)
            MetalPresenterTelemetry.reset()
        }
    }

}
