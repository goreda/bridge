import Foundation

public struct ProcessCPUReading: Equatable, Sendable {
    public let monotonicSeconds: Double
    public let userSeconds: Double
    public let systemSeconds: Double
    public init(monotonicSeconds: Double, userSeconds: Double, systemSeconds: Double) {
        self.monotonicSeconds = monotonicSeconds
        self.userSeconds = userSeconds
        self.systemSeconds = systemSeconds
    }
}

public protocol ProcessCPUReadingSource {
    /// nil means unavailable, not zero CPU use.
    func readCPU() -> ProcessCPUReading?
}

public enum ProcessCPUState: Equatable, Sendable {
    case unavailable, warmingUp, invalidReading, counterRegressed, nonIncreasingTime
    case measured(ProcessCPUInterval)
}

public struct ProcessCPUInterval: Equatable, Sendable {
    public let wallSeconds: Double
    public let userSeconds: Double
    public let systemSeconds: Double
    /// One unit means one CPU core busy for the whole interval. May exceed one.
    public let coreUtilization: Double
}

/// Owner-scoped value state, called serially by its future runtime owner.
/// Reads and deltas describe the whole process, never a specific decoder frame.
public struct ProcessCPUProducer: Sendable {
    private var previous: ProcessCPUReading?
    public init() {}
    public mutating func reset() { previous = nil }

    public mutating func sample<Source: ProcessCPUReadingSource>(from source: Source) -> ProcessCPUState {
        guard let reading = source.readCPU() else {
            previous = nil
            return .unavailable
        }
        let fields = [reading.monotonicSeconds, reading.userSeconds, reading.systemSeconds]
        guard fields.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            previous = nil
            return .invalidReading
        }
        guard let before = previous else {
            previous = reading
            return .warmingUp
        }
        previous = reading
        let elapsed = reading.monotonicSeconds - before.monotonicSeconds
        guard elapsed > 0, elapsed.isFinite else { return .nonIncreasingTime }
        let user = reading.userSeconds - before.userSeconds
        let system = reading.systemSeconds - before.systemSeconds
        guard user >= 0, system >= 0 else { return .counterRegressed }
        let utilization = user / elapsed + system / elapsed
        guard utilization.isFinite else { return .invalidReading }
        return .measured(ProcessCPUInterval(wallSeconds: elapsed,
            userSeconds: user, systemSeconds: system, coreUtilization: utilization))
    }
}

public enum CaptureThermalState: String, Equatable, Sendable {
    case nominal, fair, serious, critical, unknown
}
public protocol CaptureThermalSource {
    func readThermalState() -> CaptureThermalState?
}
public struct CaptureThermalEvent: Equatable, Sendable {
    public let monotonicSeconds: Double
    public let previous: CaptureThermalState?
    public let current: CaptureThermalState?
}
public enum ThermalSampleResult: Equatable, Sendable {
    case unchanged, event, invalidTimestamp
}

/// Fixed bound, FIFO retention. nil thermal state is recorded as unavailability.
/// First observation is an event, not a fabricated transition from nominal.
public struct CaptureThermalProducer: Sendable {
    public static let maximumCapacity = 1024
    public let capacity: Int
    public private(set) var events: [CaptureThermalEvent] = []
    public private(set) var droppedEvents: UInt64 = 0
    public private(set) var current: CaptureThermalState?
    private var hasSample = false
    private var lastTime: Double?

    public init(capacity: Int = 64) {
        self.capacity = min(max(capacity, 0), Self.maximumCapacity)
    }

    static func incrementDropped(_ count: UInt64) -> UInt64 {
        count == .max ? .max : count + 1
    }

    @discardableResult
    public mutating func sample<Source: CaptureThermalSource>(from source: Source,
                                                               monotonicSeconds: Double) -> ThermalSampleResult {
        guard monotonicSeconds.isFinite, monotonicSeconds >= 0,
              lastTime.map({ monotonicSeconds >= $0 }) ?? true else { return .invalidTimestamp }
        lastTime = monotonicSeconds
        let next = source.readThermalState()
        guard !hasSample || next != current else { return .unchanged }
        let event = CaptureThermalEvent(monotonicSeconds: monotonicSeconds,
                                       previous: current, current: next)
        hasSample = true
        current = next
        if capacity == 0 {
            droppedEvents = Self.incrementDropped(droppedEvents)
        } else {
            if events.count == capacity {
                events.removeFirst()
                droppedEvents = Self.incrementDropped(droppedEvents)
            }
            events.append(event)
        }
        return .event
    }
}

/// Additive mapping of independent evidence into the threshold-free report.
/// CPU state and thermal events are not treated as display or heat acceptance.
public struct CaptureHeatEvidence: Equatable, Sendable {
    public let report: CaptureHeatReport
    public let processCPU: ProcessCPUState
    public let thermalState: CaptureThermalState?
    public let thermalEvents: [CaptureThermalEvent]
    public let droppedThermalEvents: UInt64
    public init(report: CaptureHeatReport, processCPU: ProcessCPUState,
                thermal: CaptureThermalProducer) {
        self.report = report
        self.processCPU = processCPU
        thermalState = thermal.current
        thermalEvents = thermal.events
        droppedThermalEvents = thermal.droppedEvents
    }
}
