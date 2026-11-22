import Foundation

/// Per-host, per-source one-shot permit. MainActor serializes event and UI races.
/// No playback occurs here. The caller must verify host and open generation at
/// every suspension and immediately before consuming this permit.
@MainActor
final class GorAVPostOpenFallback {
    enum Phase { case waiting, opened, claimed, draining, ready, consumed, cancelled }
    private(set) var phase: Phase = .waiting
    private(set) var reason: String?
    private(set) var wasClaimed = false
    static func isTerminal(_ reason: String) -> Bool {
        reason.hasPrefix("pump:") || reason.hasPrefix("plane:") ||
        reason.hasPrefix("audioSeek:") ||
        ["seekFrame0Timeout", "seekCommittedButPumpRefused", "seekRequiresClose"].contains(reason)
    }
    func opened() { if phase == .waiting { phase = .opened } }
    func claim(_ reason: String) -> Bool {
        guard phase == .opened, !reason.isEmpty else { return false }
        self.reason = reason; wasClaimed = true; phase = .claimed
        return true
    }
    func beginDrain() -> Bool {
        guard phase == .claimed else { return false }
        phase = .draining; return true
    }
    func drained(definitivelyClosed: Bool) -> Bool {
        guard phase == .draining else { return false }
        phase = definitivelyClosed ? .ready : .cancelled
        return definitivelyClosed
    }
    var isReady: Bool { phase == .ready }
    func consume(current: Bool) -> Bool {
        guard phase == .ready, current else { return false }
        phase = .consumed; return true
    }
    func cancel() { if phase != .consumed { phase = .cancelled } }
}
