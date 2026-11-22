import Foundation

public enum HeatComparisonEngine: String, Sendable { case gorav, mpv }
public struct HeatWorkload: Equatable, Sendable {
    public let filmSHA256: String
    public let settingsSHA256: String
    public let startPTS: Double
    public let endPTS: Double
    public let width: Int
    public let height: Int
    public let playbackRate: Double
    public init(filmSHA256: String, settingsSHA256: String, startPTS: Double,
                endPTS: Double, width: Int, height: Int, playbackRate: Double) {
        self.filmSHA256 = filmSHA256; self.settingsSHA256 = settingsSHA256
        self.startPTS = startPTS; self.endPTS = endPTS
        self.width = width; self.height = height; self.playbackRate = playbackRate
    }
}
public struct HeatTrial: Sendable {
    public let engine: HeatComparisonEngine
    public let runID: UUID
    public let processInstanceID: UUID
    public let workload: HeatWorkload
    public let cpuStart: ProcessCPUReading
    public let cpuEnd: ProcessCPUReading
    public init(engine: HeatComparisonEngine, runID: UUID, processInstanceID: UUID,
                workload: HeatWorkload, cpuStart: ProcessCPUReading, cpuEnd: ProcessCPUReading) {
        self.engine = engine; self.runID = runID; self.processInstanceID = processInstanceID
        self.workload = workload; self.cpuStart = cpuStart; self.cpuEnd = cpuEnd
    }
}
public enum HeatComparisonError: Error, Equatable {
    case wrongEnginePair, reusedRun, reusedProcess, invalidWorkload, differentWorkload
    case invalidCPU(ProcessCPUState)
}
/// Caller-supplied identities are comparison keys, not authenticated receipts.
/// This contract cannot prove the film was played or the readings were collected
/// in that process. Native same-run evidence remains a separate prerequisite.
/// No thermal verdict or default-switch threshold is encoded here.
public struct HeatComparison: Sendable {
    public let goravCoreUtilization: Double
    public let mpvCoreUtilization: Double
    public let coreUtilizationDifference: Double
    public let goravToMPVRatio: Double?
    public init(gorav: HeatTrial, mpv: HeatTrial) throws {
        guard gorav.engine == .gorav, mpv.engine == .mpv else {
            throw HeatComparisonError.wrongEnginePair
        }
        guard gorav.runID != mpv.runID else { throw HeatComparisonError.reusedRun }
        guard gorav.processInstanceID != mpv.processInstanceID else { throw HeatComparisonError.reusedProcess }
        func valid(_ work: HeatWorkload) -> Bool {
            func hash(_ value: String) -> Bool {
                value.utf8.count == 64 && value.utf8.allSatisfy {
                    ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
                }
            }
            return hash(work.filmSHA256) && hash(work.settingsSHA256)
                && work.startPTS.isFinite && work.startPTS >= 0
                && work.endPTS.isFinite && work.endPTS > work.startPTS
                && work.width > 0 && work.height > 0
                && work.playbackRate.isFinite && work.playbackRate > 0
        }
        guard valid(gorav.workload), valid(mpv.workload) else { throw HeatComparisonError.invalidWorkload }
        guard gorav.workload == mpv.workload else { throw HeatComparisonError.differentWorkload }
        struct Reading: ProcessCPUReadingSource {
            let value: ProcessCPUReading
            func readCPU() -> ProcessCPUReading? { value }
        }
        func utilization(_ trial: HeatTrial) throws -> Double {
            var producer = ProcessCPUProducer()
            let first = producer.sample(from: Reading(value: trial.cpuStart))
            guard first == .warmingUp else { throw HeatComparisonError.invalidCPU(first) }
            let last = producer.sample(from: Reading(value: trial.cpuEnd))
            guard case .measured(let interval) = last else { throw HeatComparisonError.invalidCPU(last) }
            return interval.coreUtilization
        }
        let a = try utilization(gorav), b = try utilization(mpv)
        goravCoreUtilization = a
        mpvCoreUtilization = b
        coreUtilizationDifference = a - b
        let ratio = b > 0 ? a / b : nil
        goravToMPVRatio = ratio.flatMap { $0.isFinite ? $0 : nil }
    }
}
