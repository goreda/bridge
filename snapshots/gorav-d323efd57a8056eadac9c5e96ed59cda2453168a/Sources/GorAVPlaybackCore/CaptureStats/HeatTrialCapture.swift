import Foundation

/// A runtime adapter must sample its own decoder and process, not a sibling's.
public protocol HeatTrialCaptureSource {
    func captureReading() -> HeatTrialCaptureReading?
}
public struct HeatTrialCaptureReading: Sendable {
    public let processInstanceID: UUID
    public let filmSHA256: String
    public let settingsSHA256: String
    public let presentationEpoch: UInt64
    public let pts: Double
    public let width: Int
    public let height: Int
    public let playbackRate: Double
    public let cpu: ProcessCPUReading
    public init(processInstanceID: UUID, filmSHA256: String, settingsSHA256: String,
                presentationEpoch: UInt64, pts: Double, width: Int, height: Int,
                playbackRate: Double, cpu: ProcessCPUReading) {
        self.processInstanceID = processInstanceID; self.filmSHA256 = filmSHA256
        self.settingsSHA256 = settingsSHA256; self.presentationEpoch = presentationEpoch
        self.pts = pts; self.width = width; self.height = height
        self.playbackRate = playbackRate; self.cpu = cpu
    }
}
public enum HeatTrialCaptureError: Error, Equatable {
    case unavailable, notStarted, alreadyStarted, identityChanged, discontinuity
    case invalidReading, invalidCPU(ProcessCPUState)
}
/// Two endpoint samples, no timer or log. Runtime is responsible for delivering
/// genuine current-film hashes, settings and PTS, and incrementing epoch on seek.
public struct HeatTrialCapture: Sendable {
    private struct CPU: ProcessCPUReadingSource {
        let value: ProcessCPUReading
        func readCPU() -> ProcessCPUReading? { value }
    }
    private var first: HeatTrialCaptureReading?
    private let engine: HeatComparisonEngine
    private let runID: UUID
    public init(engine: HeatComparisonEngine, runID: UUID = UUID()) {
        self.engine = engine; self.runID = runID
    }
    private func validate(_ value: HeatTrialCaptureReading) throws {
        func hash(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
            }
        }
        guard hash(value.filmSHA256), hash(value.settingsSHA256),
              value.pts.isFinite, value.pts >= 0, value.width > 0, value.height > 0,
              value.playbackRate.isFinite, value.playbackRate > 0,
              [value.cpu.monotonicSeconds, value.cpu.userSeconds, value.cpu.systemSeconds]
                .allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw HeatTrialCaptureError.invalidReading }
    }
    public mutating func start<Source: HeatTrialCaptureSource>(from source: Source) throws {
        guard first == nil else { throw HeatTrialCaptureError.alreadyStarted }
        guard let value = source.captureReading() else { throw HeatTrialCaptureError.unavailable }
        try validate(value)
        first = value
    }
    public mutating func finish<Source: HeatTrialCaptureSource>(from source: Source) throws -> HeatTrial {
        guard let begin = first else { throw HeatTrialCaptureError.notStarted }
        // Any finish attempt consumes the trial, including a failed sample.
        first = nil
        guard let end = source.captureReading() else { throw HeatTrialCaptureError.unavailable }
        try validate(end)
        guard begin.processInstanceID == end.processInstanceID,
              begin.filmSHA256 == end.filmSHA256, begin.settingsSHA256 == end.settingsSHA256,
              begin.width == end.width, begin.height == end.height,
              begin.playbackRate == end.playbackRate else { throw HeatTrialCaptureError.identityChanged }
        guard begin.presentationEpoch == end.presentationEpoch,
              end.pts > begin.pts else { throw HeatTrialCaptureError.discontinuity }
        var producer = ProcessCPUProducer()
        _ = producer.sample(from: CPU(value: begin.cpu))
        let state = producer.sample(from: CPU(value: end.cpu))
        guard case .measured = state else { throw HeatTrialCaptureError.invalidCPU(state) }
        return HeatTrial(engine: engine, runID: runID, processInstanceID: begin.processInstanceID,
            workload: HeatWorkload(filmSHA256: begin.filmSHA256,
                settingsSHA256: begin.settingsSHA256, startPTS: begin.pts, endPTS: end.pts,
                width: begin.width, height: begin.height, playbackRate: begin.playbackRate),
            cpuStart: begin.cpu, cpuEnd: end.cpu)
    }
}
