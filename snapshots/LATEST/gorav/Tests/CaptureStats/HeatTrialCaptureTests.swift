import Foundation
import XCTest
@testable import CaptureStats
final class HeatTrialCaptureTests: XCTestCase {
    struct Source: HeatTrialCaptureSource {
        var value: HeatTrialCaptureReading?
        func captureReading() -> HeatTrialCaptureReading? { value }
    }
    let process = UUID()
    func reading(pts: Double = 1, time: Double = 1, process: UUID? = nil,
                 epoch: UInt64 = 1, settings: String = String(repeating: "b", count: 64)) -> Source {
        Source(value: HeatTrialCaptureReading(processInstanceID: process ?? self.process,
            filmSHA256: String(repeating: "a", count: 64), settingsSHA256: settings,
            presentationEpoch: epoch, pts: pts, width: 1920, height: 1080,
            playbackRate: 1, cpu: ProcessCPUReading(monotonicSeconds: time,
                userSeconds: time / 2, systemSeconds: time / 4)))
    }
    func testCapturesObservedWindowAndRealCPU() throws {
        var capture = HeatTrialCapture(engine: .gorav)
        try capture.start(from: reading())
        let trial = try capture.finish(from: reading(pts: 3, time: 4))
        XCTAssertEqual(trial.workload.startPTS, 1)
        XCTAssertEqual(trial.workload.endPTS, 3)
        XCTAssertEqual(trial.cpuStart.userSeconds, 0.5)
        XCTAssertEqual(trial.cpuEnd.systemSeconds, 1)
        XCTAssertThrowsError(try capture.finish(from: reading(pts: 4, time: 5)))
    }
    func testUnavailableAndDoubleStartRefused() throws {
        var capture = HeatTrialCapture(engine: .mpv)
        XCTAssertThrowsError(try capture.start(from: Source(value: nil)))
        try capture.start(from: reading())
        XCTAssertThrowsError(try capture.start(from: reading()))
        XCTAssertThrowsError(try capture.finish(from: Source(value: nil)))
        XCTAssertThrowsError(try capture.finish(from: reading(pts: 2, time: 3)))
    }
    func testChangedIdentityAndDiscontinuityRefused() throws {
        for endpoint in [reading(pts: 2, time: 3, process: UUID()),
                         reading(pts: 2, time: 3, epoch: 2),
                         reading(pts: 2, time: 3, settings: String(repeating: "c", count: 64)),
                         reading(pts: 0, time: 3), reading(pts: 1, time: 3),
                         reading(pts: 2, time: 1), reading(pts: .nan, time: 3)] {
            var capture = HeatTrialCapture(engine: .gorav)
            try capture.start(from: reading())
            XCTAssertThrowsError(try capture.finish(from: endpoint))
        }
    }
}
