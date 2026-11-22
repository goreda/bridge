import Foundation
import XCTest
@testable import CaptureStats

final class HeatProducerTests: XCTestCase {
    struct CPU: ProcessCPUReadingSource {
        var reading: ProcessCPUReading?
        func readCPU() -> ProcessCPUReading? { reading }
        init(_ time: Double, _ user: Double, _ system: Double) {
            reading = ProcessCPUReading(monotonicSeconds: time, userSeconds: user, systemSeconds: system)
        }
        init() { reading = nil }
    }
    struct Thermal: CaptureThermalSource {
        var state: CaptureThermalState?
        func readThermalState() -> CaptureThermalState? { state }
    }

    func testCPUUserAndSystemDeltasAndMulticore() {
        var p = ProcessCPUProducer()
        XCTAssertEqual(p.sample(from: CPU(1, 10, 5)), .warmingUp)
        guard case .measured(let v) = p.sample(from: CPU(3, 13, 6)) else {
            return XCTFail("expected measured interval")
        }
        XCTAssertEqual(v.wallSeconds, 2)
        XCTAssertEqual(v.userSeconds, 3)
        XCTAssertEqual(v.systemSeconds, 1)
        XCTAssertEqual(v.coreUtilization, 2)
    }

    func testCPUZeroIsMeasuredAndUnavailableBreaksContinuity() {
        var p = ProcessCPUProducer()
        _ = p.sample(from: CPU(1, 0, 0))
        guard case .measured(let zero) = p.sample(from: CPU(2, 0, 0)) else {
            return XCTFail("zero must be measured")
        }
        XCTAssertEqual(zero.coreUtilization, 0)
        XCTAssertEqual(p.sample(from: CPU()), .unavailable)
        XCTAssertEqual(p.sample(from: CPU(3, 0, 0)), .warmingUp)
        p.reset()
        XCTAssertEqual(p.sample(from: CPU(4, 0, 0)), .warmingUp)
    }

    func testCPUInvalidRegressionAndClockRefusal() {
        var p = ProcessCPUProducer()
        for x in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertEqual(p.sample(from: CPU(x, 0, 0)), .invalidReading)
            XCTAssertEqual(p.sample(from: CPU(1, x, 0)), .invalidReading)
            XCTAssertEqual(p.sample(from: CPU(1, 0, x)), .invalidReading)
        }
        _ = p.sample(from: CPU(1, 4, 3))
        XCTAssertEqual(p.sample(from: CPU(2, 3, 3)), .counterRegressed)
        XCTAssertEqual(p.sample(from: CPU(2, 3, 3)), .nonIncreasingTime)
        XCTAssertEqual(p.sample(from: CPU(1, 3, 3)), .nonIncreasingTime)
    }

    func testThermalTransitionsIncludeUnavailableWithoutInventingNominal() {
        var p = CaptureThermalProducer(capacity: 3)
        XCTAssertEqual(p.sample(from: Thermal(state: nil), monotonicSeconds: 1), .event)
        XCTAssertNil(p.events[0].previous)
        XCTAssertNil(p.events[0].current)
        XCTAssertEqual(p.sample(from: Thermal(state: nil), monotonicSeconds: 2), .unchanged)
        XCTAssertEqual(p.sample(from: Thermal(state: .serious), monotonicSeconds: 3), .event)
        XCTAssertEqual(p.sample(from: Thermal(state: .critical), monotonicSeconds: 4), .event)
        XCTAssertEqual(p.sample(from: Thermal(state: nil), monotonicSeconds: 5), .event)
        XCTAssertEqual(p.events.count, 3)
        XCTAssertEqual(p.droppedEvents, 1)
        XCTAssertNil(p.current)
        XCTAssertEqual(p.events.last?.previous, .critical)
    }

    func testThermalBoundsAndInvalidTimestamps() {
        var p = CaptureThermalProducer(capacity: 0)
        for i in 0..<2000 {
            _ = p.sample(from: Thermal(state: i % 2 == 0 ? .nominal : .fair), monotonicSeconds: Double(i))
        }
        XCTAssertEqual(p.events.count, 0)
        XCTAssertEqual(p.droppedEvents, 2000)
        for t in [Double.nan, .infinity, -1, 1] {
            XCTAssertEqual(p.sample(from: Thermal(state: .critical), monotonicSeconds: t), .invalidTimestamp)
        }
        XCTAssertEqual(p.current, .fair)
        XCTAssertEqual(CaptureThermalProducer(capacity: Int.max).capacity, 1024)
        XCTAssertEqual(CaptureThermalProducer(capacity: -1).capacity, 0)
    }

    func testReportMappingPreservesUnavailable() throws {
        let snapshot = try CaptureStatsSnapshot(source: .metalPresenter, sessionID: UUID(),
            monotonicSeconds: 10, counters: [:], closedByUser: false)
        let report = try CaptureHeatReport(presenter: CaptureHUDFeed(current: snapshot))
        let v = CaptureHeatEvidence(report: report, processCPU: .unavailable,
                                    thermal: CaptureThermalProducer())
        XCTAssertEqual(v.processCPU, .unavailable)
        XCTAssertNil(v.thermalState)
        XCTAssertTrue(v.thermalEvents.isEmpty)
        XCTAssertNil(v.report.meanSubmissionWallSeconds)
    }

    func testOffDarwinSourcesAreUnavailable() {
        #if !canImport(Darwin)
        XCTAssertNil(DarwinProcessCPUSource().readCPU())
        XCTAssertNil(ProcessInfoThermalSource().readThermalState())
        #endif
    }
    func testDroppedEventSaturationBoundary() {
        XCTAssertEqual(CaptureThermalProducer.incrementDropped(0), 1)
        XCTAssertEqual(CaptureThermalProducer.incrementDropped(.max - 1), .max)
        XCTAssertEqual(CaptureThermalProducer.incrementDropped(.max), .max)
    }

    func testCPURegressionRecoveryAndExplicitReset() {
        var p = ProcessCPUProducer()
        _ = p.sample(from: CPU(1, 10, 10))
        XCTAssertEqual(p.sample(from: CPU(2, 9, 10)), .counterRegressed)
        guard case .measured(let recovered) = p.sample(from: CPU(3, 10, 11)) else {
            return XCTFail("regression must rebase the next interval")
        }
        XCTAssertEqual(recovered.userSeconds, 1)
        XCTAssertEqual(recovered.systemSeconds, 1)
        p.reset()
        XCTAssertEqual(p.sample(from: CPU(4, 11, 12)), .warmingUp)
        XCTAssertEqual(p.sample(from: CPU(5, 11, 11)), .counterRegressed)
    }

}
