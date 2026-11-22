import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Isolated lifecycle preparation, not a production hook. Owns exactly one
/// child's already-configured combined stdout/stderr read handle. Register
/// before spawning the child. The supplied consume callback owns raw delivery
/// and line parsing; finishTail must flush that parser's final partial row.
/// No raw spool, timeout-based completion, or child termination policy here.
final class PlayerSessionPipeDrain {
    enum Failure: Error { case alreadyStarted, notStarted }
    private let gate = NSLock()
    private let reader = DispatchQueue(label: "gor.player-session.pipe-drain", qos: .utility)
    private let files: PlayerSessionBarrierAdapter?
    let producer: PlayerSessionDrainPlan.Producer?
    private let consume: (Data) throws -> Void
    private let finishTail: () throws -> Void
    private var started = false
    private var failure: Error?
    private var terminalFailure = false
    private var exitSeen = false
    private var exitAcknowledged = false
    private var eofSeen = false
    private var tailFinished = false
    private var eofAcknowledged = false

    init(adapter: PlayerSessionBarrierAdapter?, kind: String,
         consume: @escaping (Data) throws -> Void,
         finishTail: @escaping () throws -> Void) throws {
        files = adapter
        producer = try adapter?.register(kind: kind, barriers: ["exit", "combined-eof"])
        self.consume = consume; self.finishTail = finishTail
    }

    /// One kernel read returns the bytes currently available, without waiting
    /// for a 64KiB Foundation fill. This keeps a live child's protocol timely.
    static func readAvailableChunk(_ handle:FileHandle)throws->Data {
        var buffer=[UInt8](repeating:0,count:65536)
        while true {
            let count=buffer.withUnsafeMutableBytes { raw in
                read(handle.fileDescriptor,raw.baseAddress,raw.count)
            }
            if count<0 && errno==EINTR {continue}
            guard count>=0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
            return Data(buffer.prefix(count))
        }
    }
    /// Starts one bounded-chunk blocking reader on its own worker, never main.
    /// Both child streams must point at this same pipe before launch. A child
    /// or descendant holding a writer open keeps EOF pending, even after exit.
    func start(handle: FileHandle) throws {
        gate.lock()
        guard !started else { gate.unlock(); throw Failure.alreadyStarted }
        started = true
        gate.unlock()
        reader.async { [self] in
            do {
                var discard=false
                while true {
                    let data=try Self.readAvailableChunk(handle)
                    if data.isEmpty {break}
                    if !discard {
                        do {try consume(data)}
                        catch {recordFailure(error,terminal:true);discard=true}
                    }
                }
            } catch { recordFailure(error, terminal: true); return }
            // Real EOF, not Process termination or a timer.
            gate.lock(); eofSeen = true; gate.unlock()
            do { try acknowledgeEOF() } catch { recordFailure(error) }
        }
    }

    /// Call from that exact child's termination handler only. This does not
    /// infer EOF; pending tail/pipe bytes still prevent helper drain.
    func childExited() {
        gate.lock(); exitSeen = true; gate.unlock()
        do { try acknowledgeExit() } catch { recordFailure(error) }
    }

    /// Metadata failure can be retried without replaying raw chunks or the
    /// tail. A consume/read/tail failure is not recoverable through this API:
    /// caller must use an incomplete/crash route and preserve its evidence.
    func retryEvidence() throws {
        try acknowledgeExit()
        try acknowledgeEOF()
    }
    var lastFailure: Error? { gate.lock(); defer { gate.unlock() }; return failure }

    private func recordFailure(_ error: Error, terminal: Bool = false) {
        gate.lock(); if failure == nil { failure = error }; terminalFailure = terminalFailure || terminal; gate.unlock()
    }
    private func acknowledgeExit() throws {
        gate.lock(); defer { gate.unlock() }
        guard exitSeen, !exitAcknowledged else { return }
        if let files, let producer { try files.observe("exit", producer: producer) }
        exitAcknowledged = true
    }
    private func acknowledgeEOF() throws {
        gate.lock(); defer { gate.unlock() }
        guard eofSeen, !eofAcknowledged, !terminalFailure else { return }
        if !tailFinished {
            do { try finishTail() }
            catch { terminalFailure = true; throw error }
            tailFinished = true
        }
        if let files, let producer { try files.observe("combined-eof", producer: producer) }
        eofAcknowledged = true
    }
}
