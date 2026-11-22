import Foundation

/// WT stdout is a protocol, stderr is not. Keep both streams independent and
/// acknowledge their EOF only after their own final parser tail is consumed.
final class WTSessionPipeDrain {
    enum Failure: Error { case alreadyStarted }
    let producer: PlayerSessionDrainPlan.Producer?
    private let adapter: PlayerSessionBarrierAdapter?
    private let lock = NSRecursiveLock()
    private var started = false
    private var seen: Set<String> = []
    private var acknowledged: Set<String> = []
    private var failure: Error?
    private var terminal: Set<String> = []
    init(adapter: PlayerSessionBarrierAdapter?) throws {
        self.adapter = adapter
        producer = try adapter?.register(kind: "webtorrent", barriers: ["exit", "stdout-eof-tail", "stderr-eof-tail"])
    }
    private init() { adapter = nil; producer = nil }
    static func uncaptured() -> WTSessionPipeDrain { WTSessionPipeDrain() }
    func start(stdout: FileHandle, stderr: FileHandle,
               consumeStdout: @escaping (Data) throws -> Void,
               consumeStderr: @escaping (Data) throws -> Void,
               finishStdout: @escaping () throws -> Void,
               finishStderr: @escaping () throws -> Void) throws {
        lock.lock()
        guard !started else { lock.unlock(); throw Failure.alreadyStarted }
        started = true
        lock.unlock()
        read(stdout, barrier: "stdout-eof-tail", consume: consumeStdout, finish: finishStdout)
        read(stderr, barrier: "stderr-eof-tail", consume: consumeStderr, finish: finishStderr)
    }
    private func read(_ handle: FileHandle, barrier: String,
                      consume: @escaping (Data) throws -> Void,
                      finish: @escaping () throws -> Void) {
        DispatchQueue(label: "gor.wt.drain." + barrier, qos: .utility).async { [self] in
            defer { try? handle.close() }
            var failed = false
            do {
                while true {
                    let data = try PlayerSessionPipeDrain.readAvailableChunk(handle)
                    if data.isEmpty { break }
                    // Keep consuming protocol after a raw-sink failure so logs
                    // cannot stop playback or stall child shutdown. The caller
                    // parses before append; failure still forbids drain success.
                    do { try consume(data) }
                    catch { failed = true; recordTerminal(error, barrier: barrier) }
                }
                try finish()
            } catch { recordTerminal(error, barrier: barrier); return }
            if !failed { evidence(barrier) }
        }
    }
    private func recordTerminal(_ error: Error, barrier: String) {
        lock.lock(); defer { lock.unlock() }
        terminal.insert(barrier)
        if failure == nil { failure = error }
    }
    /// Only call from this particular Process's terminationHandler.
    func childExited() { evidence("exit") }
    private func evidence(_ barrier: String) {
        lock.lock(); defer { lock.unlock() }
        seen.insert(barrier)
        do { try acknowledge(barrier) }
        catch { if failure == nil { failure = error } }
    }
    private func acknowledge(_ barrier: String) throws {
        guard seen.contains(barrier), !acknowledged.contains(barrier), !terminal.contains(barrier) else { return }
        if let adapter, let producer { try adapter.observe(barrier, producer: producer) }
        acknowledged.insert(barrier)
    }
    /// Retries metadata only. Never replays parser or raw-sink writes.
    func retryEvidence() throws {
        lock.lock(); defer { lock.unlock() }
        for barrier in seen.sorted() { try acknowledge(barrier) }
    }
    var lastFailure: Error? { lock.lock(); defer { lock.unlock() }; return failure }
}
