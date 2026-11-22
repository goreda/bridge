import Foundation

/// Request routing only. NSWorkspace carries documents through one document
/// AppleEvent, never a second copy in argv. A receiver waits for that initial
/// document even if applicationDidFinishLaunching ran first.
struct IndependentDocumentRouter {
    static let receiverArgument = "--gor-document-receiver"
    enum Action: Equatable { case initial(String), launch(String), acknowledge }
    private(set) var initialPath: String?
    private var awaitingDocument: Bool
    private var commandLineAcknowledgment: String?
    private var startupReady = false
    private var playerStarted = false

    init(commandLinePath: String?, receiver: Bool) {
        initialPath = commandLinePath
        commandLineAcknowledgment = commandLinePath.map(Self.canonical)
        awaitingDocument = receiver && commandLinePath == nil
    }
    mutating func replacePendingInitial(_ path: String) {
        initialPath = path
        awaitingDocument = false
    }
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
    /// The outer optional distinguishes waiting from starting an empty player.
    mutating func startup() -> String?? {
        startupReady = true
        guard !awaitingDocument, !playerStarted else { return nil }
        playerStarted = true
        return .some(initialPath)
    }
    mutating func receive(_ path: String) -> Action {
        let key = Self.canonical(path)
        // Legacy command-line launches may also receive their initial document
        // once as an AppleEvent. This is an acknowledgment, not a new player.
        // No permanent same-path ignore: a later request may reopen that file.
        if commandLineAcknowledgment == key {
            commandLineAcknowledgment = nil
            return .acknowledge
        }
        if awaitingDocument || (!playerStarted && initialPath == nil) {
            awaitingDocument = false
            initialPath = path
            if startupReady { playerStarted = true }
            return .initial(path)
        }
        return .launch(path)
    }
}

/// Pure admission policy. The caller supplies a fresh process-count snapshot
/// and monotonic time. Snapshot count is not an atomic cross-process semaphore.
enum IndependentSpawnFence {
    static func refusal(receiverInitial: Bool, runningCount: Int,
                        recentSpawnTimes: [Double], now: Double) -> String? {
        if receiverInitial { return "receiver-initial" }
        if runningCount >= 6 { return "running-count" }
        if recentSpawnTimes.filter({ now - $0 < 10 && now >= $0 }).count >= 2 {
            return "process-rate"
        }
        return nil
    }
}
