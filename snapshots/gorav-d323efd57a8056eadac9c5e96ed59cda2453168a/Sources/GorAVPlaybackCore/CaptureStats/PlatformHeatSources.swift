import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Opt-in source only. No timer, task, observer, disk writes or playback mutation.
public struct DarwinProcessCPUSource: ProcessCPUReadingSource {
    public init() {}
    public func readCPU() -> ProcessCPUReading? {
        #if canImport(Darwin)
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        func seconds(_ value: timeval) -> Double {
            Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
        }
        return ProcessCPUReading(monotonicSeconds: ProcessInfo.processInfo.systemUptime,
            userSeconds: seconds(usage.ru_utime), systemSeconds: seconds(usage.ru_stime))
        #else
        return nil
        #endif
    }
}

/// Polling ingress; transition tracking belongs to CaptureThermalProducer.
/// Linux is unavailable rather than pretending to be nominal.
public struct ProcessInfoThermalSource: CaptureThermalSource {
    public init() {}
    public func readThermalState() -> CaptureThermalState? {
        #if canImport(Darwin)
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
        #else
        return nil
        #endif
    }
}
