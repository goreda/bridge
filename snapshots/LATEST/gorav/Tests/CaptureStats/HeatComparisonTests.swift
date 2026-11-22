import Foundation
import XCTest
@testable import CaptureStats

final class HeatComparisonTests: XCTestCase {
    let film = String(repeating: "a", count: 64)
    let settings = String(repeating: "b", count: 64)
    func workload(film: String? = nil, settings: String? = nil, start: Double = 10,
                  end: Double = 20, width: Int = 1920, rate: Double = 1) -> HeatWorkload {
        HeatWorkload(filmSHA256: film ?? self.film, settingsSHA256: settings ?? self.settings,
            startPTS: start, endPTS: end, width: width, height: 1080, playbackRate: rate)
    }
    func trial(_ engine: HeatComparisonEngine, work: HeatWorkload? = nil,
               run: UUID = UUID(), process: UUID = UUID(), userEnd: Double = 3,
               systemEnd: Double = 1, endTime: Double = 12) -> HeatTrial {
        HeatTrial(engine: engine, runID: run, processInstanceID: process,
            workload: work ?? workload(),
            cpuStart: ProcessCPUReading(monotonicSeconds: 2, userSeconds: 1, systemSeconds: 0),
            cpuEnd: ProcessCPUReading(monotonicSeconds: endTime, userSeconds: userEnd, systemSeconds: systemEnd))
    }

    func testDifferentFilmWindowSettingsGeometryAndRateRefused() throws {
        let a = trial(.gorav)
        for work in [workload(film: String(repeating: "c", count: 64)),
                     workload(settings: String(repeating: "c", count: 64)),
                     workload(start: 11), workload(end: 21), workload(width: 1280), workload(rate: 2)] {
            XCTAssertThrowsError(try HeatComparison(gorav: a, mpv: trial(.mpv, work: work))) {
                XCTAssertEqual($0 as? HeatComparisonError, .differentWorkload)
            }
        }
    }
    func testEngineRunAndProcessIdentityRefused() throws {
        let a = trial(.gorav)
        XCTAssertThrowsError(try HeatComparison(gorav: a, mpv: trial(.gorav)))
        XCTAssertThrowsError(try HeatComparison(gorav: a, mpv: trial(.mpv, run: a.runID))) {
            XCTAssertEqual($0 as? HeatComparisonError, .reusedRun)
        }
        XCTAssertThrowsError(try HeatComparison(gorav: a, mpv: trial(.mpv, process: a.processInstanceID))) {
            XCTAssertEqual($0 as? HeatComparisonError, .reusedProcess)
        }
    }
    func testMeasuredComparisonAndZeroReference() throws {
        let v = try HeatComparison(gorav: trial(.gorav), mpv: trial(.mpv, userEnd: 2, systemEnd: 0))
        XCTAssertEqual(v.goravCoreUtilization, 0.3, accuracy: 1e-12)
        XCTAssertEqual(v.mpvCoreUtilization, 0.1, accuracy: 1e-12)
        XCTAssertEqual(v.coreUtilizationDifference, 0.2, accuracy: 1e-12)
        XCTAssertNotNil(v.goravToMPVRatio)
        if let ratio = v.goravToMPVRatio { XCTAssertEqual(ratio, 3, accuracy: 1e-12) }
        let zero = try HeatComparison(gorav: trial(.gorav), mpv: trial(.mpv, userEnd: 1, systemEnd: 0))
        XCTAssertEqual(zero.mpvCoreUtilization, 0)
        XCTAssertNil(zero.goravToMPVRatio)
    }
    func testInvalidWorkloadAndCPURefused() throws {
        for work in [workload(film: ""), workload(settings: "unknown"), workload(start: .nan),
                     workload(start: -1), workload(end: 10), workload(end: .infinity),
                     workload(width: 0), workload(rate: 0)] {
            XCTAssertThrowsError(try HeatComparison(gorav: trial(.gorav, work: work), mpv: trial(.mpv, work: work)))
        }
        for b in [trial(.mpv, userEnd: 0), trial(.mpv, systemEnd: -1),
                  trial(.mpv, userEnd: .nan), trial(.mpv, endTime: 2)] {
            XCTAssertThrowsError(try HeatComparison(gorav: trial(.gorav), mpv: b))
        }
    }
}
