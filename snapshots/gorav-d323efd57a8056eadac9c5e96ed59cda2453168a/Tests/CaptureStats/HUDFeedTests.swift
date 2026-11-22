import Foundation
import XCTest
@testable import CaptureStats

final class HUDFeedTests: XCTestCase {
    private func snapshot(_ time: Double = 10, _ counters: [CaptureCounter: UInt64] = [:],
                          id: UUID) throws -> CaptureStatsSnapshot {
        try CaptureStatsSnapshot(source: .metalPresenter, sessionID: id,
            monotonicSeconds: time, counters: counters, closedByUser: false)
    }

    func testFirstSampleHasNoInventedRate() throws {
        let feed = CaptureHUDFeed(current: try snapshot(10, [.uploads: 100], id: UUID()))
        XCTAssertEqual(feed.intervalState, .awaitingPreviousSample)
        XCTAssertEqual(feed.snapshot[.uploads], 100)
        XCTAssertNil(feed.elapsedSeconds)
        XCTAssertNil(feed.uploadsPerSecond)
    }

    func testMeasuredZeroAndMissingValuesRemainDistinct() throws {
        let id = UUID()
        let a = try snapshot(1, [.uploads: 10, .readbacks: 4], id: id)
        let b = try snapshot(3, [.uploads: 16, .readbacks: 4], id: id)
        let feed = CaptureHUDFeed(current: b, previous: a)
        XCTAssertEqual(feed.intervalState, .measured)
        XCTAssertEqual(feed.uploadsPerSecond, 3)
        XCTAssertEqual(feed.readbacksPerSecond, 0)
        XCTAssertNil(feed.visibleUploadsPerSecond)
        XCTAssertNil(feed.rejectedUploadsPerSecond)
    }

    func testRefusedIntervalNeverLeaksPreviousRate() throws {
        let id = UUID()
        let a = try snapshot(1, [.uploads: 10], id: id)
        for (b, reason) in [
            (try snapshot(2, [.uploads: 9], id: id), CaptureStatsError.counterRegressed(.uploads)),
            (try snapshot(1, [.uploads: 12], id: id), .nonIncreasingTime),
            (try snapshot(2, [.uploads: 12], id: UUID()), .differentSession)
        ] {
            let feed = CaptureHUDFeed(current: b, previous: a)
            XCTAssertEqual(feed.intervalState, .refused(reason))
            XCTAssertNil(feed.uploadsPerSecond)
            XCTAssertNil(feed.elapsedSeconds)
        }
    }

    func testHeatReportMissingProbesAreUnavailableNotZero() throws {
        let feed = CaptureHUDFeed(current: try snapshot(id: UUID()))
        let report = try CaptureHeatReport(presenter: feed)
        XCTAssertEqual(report.completeSubmissionSamples, 0)
        XCTAssertNil(report.meanSubmissionWallSeconds)
        XCTAssertNil(report.maxSubmissionWallSeconds)
    }

    func testHeatReportComputesOnlyMeasuredSubmissionWallTime() throws {
        let id = UUID()
        let feed = CaptureHUDFeed(current: try snapshot(id: id))
        let samples = [
            CaptureSubmissionSample(sessionID: id, frameID: 1, beginSeconds: 1, commitEndSeconds: 1.25),
            CaptureSubmissionSample(sessionID: id, frameID: 2, beginSeconds: 2, commitEndSeconds: 2.75),
            CaptureSubmissionSample(sessionID: id, frameID: 3, beginSeconds: 3, commitEndSeconds: nil)
        ]
        let report = try CaptureHeatReport(presenter: feed, submissionSamples: samples)
        XCTAssertEqual(report.completeSubmissionSamples, 2)
        XCTAssertEqual(report.incompleteSubmissionSamples, 1)
        XCTAssertEqual(report.meanSubmissionWallSeconds, 0.5)
        XCTAssertEqual(report.maxSubmissionWallSeconds, 0.75)
    }

    func testHeatReportRefusesForeignDuplicateAndInvalidEvidence() throws {
        let id = UUID()
        let feed = CaptureHUDFeed(current: try snapshot(id: id))
        let valid = CaptureSubmissionSample(sessionID: id, frameID: 1, beginSeconds: 1, commitEndSeconds: 2)
        XCTAssertThrowsError(try CaptureHeatReport(presenter: feed, submissionSamples: [valid, valid])) {
            XCTAssertEqual($0 as? CaptureHeatReportError, .duplicateFrame)
        }
        XCTAssertThrowsError(try CaptureHeatReport(presenter: feed, submissionSamples: [
            CaptureSubmissionSample(sessionID: UUID(), frameID: 1, beginSeconds: 1, commitEndSeconds: 2)])) {
            XCTAssertEqual($0 as? CaptureHeatReportError, .foreignSession)
        }
        for (begin, end) in [(Double.nan, 2.0), (-1, 2), (3, 2), (1, .infinity), (1, 11), (11, 12)] {
            XCTAssertThrowsError(try CaptureHeatReport(presenter: feed, submissionSamples: [
                CaptureSubmissionSample(sessionID: id, frameID: 1, beginSeconds: begin, commitEndSeconds: end)])) {
                XCTAssertEqual($0 as? CaptureHeatReportError, .invalidSubmissionTime)
            }
        }
    }
}
