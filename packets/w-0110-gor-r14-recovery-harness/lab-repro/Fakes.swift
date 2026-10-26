import Foundation

// ============================================================================
// W-0110 harness fakes. Every type here is an explicitly LABELED FAKE per the
// packet: fake process/controller/Dispatch executors allowed only when labeled.
// No sleeps anywhere; ordering is gates/ACK only.
// ============================================================================

/// LABELED FAKE (Dispatch executor): deterministic gated executor.
/// Work items queue in FIFO and run only when the harness ACKs via
/// runNext()/runAll(). This is how tests assert intermediate state between
/// the production code's async hops without any sleep.
final class GatedExecutor: RecoveryExecutor {
    let label: String
    private(set) var pendingCount = 0
    private var pending: [() -> Void] = []
    private(set) var ranCount = 0

    init(label: String) { self.label = label }

    func async(_ work: @escaping () -> Void) {
        pending.append(work)
        pendingCount = pending.count
    }

    /// ACK: run the oldest queued block. Returns false if the gate is empty.
    @discardableResult
    func runNext() -> Bool {
        guard !pending.isEmpty else { return false }
        let work = pending.removeFirst()
        pendingCount = pending.count
        ranCount += 1
        work()
        return true
    }

    func runAll() { while runNext() {} }
}

/// LABELED FAKE (Process): scripted `-U` updater.
/// When `replacementBytes` is set, run() actually rewrites the file at
/// executableURL on disk, so the production before/after `Data(contentsOf:)`
/// byte comparison executes against real file contents, not a mock of it.
final class FakeUpdateProcess: UpdateProcess {
    var executableURL: URL?
    var arguments: [String]?
    var standardOutput: Any?
    var standardError: Any?
    private(set) var terminationStatus: Int32 = -1
    private(set) var runCallCount = 0

    let scriptedStatus: Int32
    let replacementBytes: [UInt8]?
    let launchError: Error?

    init(status: Int32, replacementBytes: [UInt8]? = nil, launchError: Error? = nil) {
        self.scriptedStatus = status
        self.replacementBytes = replacementBytes
        self.launchError = launchError
    }

    func run() throws {
        runCallCount += 1
        if let launchError { throw launchError }
        if let replacementBytes, let path = executableURL?.path {
            try Data(replacementBytes).write(to: URL(fileURLWithPath: path))
        }
        terminationStatus = scriptedStatus
    }

    func waitUntilExit() {}
}

/// Convenience handle so tests can count how many update processes the
/// production flow created.
final class FakeUpdateFactory {
    private(set) var created: [FakeUpdateProcess] = []
    let script: () -> FakeUpdateProcess
    init(script: @escaping () -> FakeUpdateProcess) { self.script = script }
    func make() -> UpdateProcess {
        let p = script()
        created.append(p)
        return p
    }
}
