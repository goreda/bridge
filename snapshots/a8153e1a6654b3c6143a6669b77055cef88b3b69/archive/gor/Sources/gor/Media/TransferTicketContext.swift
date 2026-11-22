import Foundation

// Main-queue-only metadata, bound to the exact captured CDN URL. Contains no
// passwords/cookies; protected transfers keep their original captured ticket.
enum TransferTicketContext {
    private static var tickets: [String: (share: String, node: String)] = [:]

    static func remember(url: String?, shareURL: String, node: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let url, let parts = URLComponents(string: shareURL),
              parts.scheme == "https", parts.host?.lowercased() == "transfer.it",
              parts.path.hasPrefix("/t/"),
              let share = parts.path.split(separator: "/").last,
              share.range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil,
              node.range(of: "^[A-Za-z0-9_-]{8}$", options: .regularExpression) != nil else { return }
        if tickets.count > 32 { tickets.removeAll() }
        tickets[url] = (String(share), node)
    }

    static func lookup(_ url: String) -> (share: String, node: String)? {
        dispatchPrecondition(condition: .onQueue(.main))
        return tickets[url]
    }
}

// Exact relay identity is registered only by the transfer.it launch path.
// No localhost-port guessing: ordinary MEGA and local/magnet sources bypass it.
enum TransferProbeAdmission {
    private static let lock = NSLock()
    private static var source: String?
    private static var forward = 0.0
    private static var stalled = true
    private static var updated = 0.0
    private static var sampleStamp: String?
    static let minimumForward = 15.0

    static func configure(_ path: String?) {
        lock.lock(); defer { lock.unlock() }
        source = path; forward = 0; stalled = true; updated = 0; sampleStamp = nil
    }
    static func markerCommand(_ path: String?) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["command": ["set_property", "user-data/gor-transfer-source", path ?? ""]])
        return String(decoding: data, as: UTF8.self)
    }
    static func isSource(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; return source != nil && source == path
    }
    static func update(path: String, seconds: Double?, pausedForCache: Bool?, stamp: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard source == path else { return }
        if let stamp, stamp == sampleStamp { if pausedForCache == true { stalled = true }; return }
        sampleStamp = stamp
        forward = seconds ?? 0; stalled = pausedForCache != false
        updated = ProcessInfo.processInfo.systemUptime
    }
    static func admits(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard source != nil, source == path else { return true }
        return updated > 0 && ProcessInfo.processInfo.systemUptime - updated < 3 &&
            forward.isFinite && forward >= minimumForward && !stalled
    }
    // At most six seconds decoded per open, never a whole-film filter scan.
    // Keep at most 96 MiB of batch output (or one existing-size frame).
    static func cropBatch(_ positions: [Double], index: Int, frameBytes: Int) -> [Double] {
        guard positions.indices.contains(index), frameBytes > 0 else { return [] }
        let first = positions[index], cap = max(1, min(3, 96 * 1024 * 1024 / frameBytes))
        return Array(positions[index...].prefix(cap).prefix { $0 - first <= 6 })
    }
    static func cropSelection(_ times: [Double]) -> String {
        guard let first = times.first else { return "0" }
        return times.enumerated().map { i, t in
            "gte(t,\(String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), t - first)))*lt(selected_n,\(i + 1))"
        }.joined(separator: "+")
    }

}
