import Foundation

/// K8(b): build identity shown in About and written to the synced log at launch.
/// Source: <bundle>/Contents/Resources/build-id.txt, written by build.sh.
/// The legacy key is commit=, but its value is the SHA256 of the compiled
/// source manifest, not a Git commit. Keep the format backward compatible.
/// A missing, unreadable or malformed file never crashes the app: the value is
/// "unknown" and the log line is still written on every launch (no skipping).
enum BuildID {
    static let resourceName = "build-id"
    static let resourceExtension = "txt"
    static let unknown = "unknown"

    /// Pure parser (no I/O). Returns the source identity value, or nil when the text has
    /// no usable `commit=` line (empty value or value containing whitespace).
    static func parseCommit(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("commit=") else { continue }
            let value = String(line.dropFirst("commit=".count)).trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value.contains(where: { $0.isWhitespace }) { return nil }
            return value
        }
        return nil
    }

    /// Value for display and log: the source identity, or "unknown".
    static func value(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let commit = parseCommit(text) else { return unknown }
        return commit
    }

    /// Pure parser (no I/O). Returns the delivered archive/gor tree sha, or nil when the
    /// text has no usable `tree=` line (must be exactly 40 lowercase hex chars).
    static func parseTree(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("tree=") else { continue }
            let value = String(line.dropFirst("tree=".count)).trimmingCharacters(in: .whitespaces)
            guard value.count == 40, value.allSatisfy({ $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) }) else { return nil }
            return value
        }
        return nil
    }

    /// Delivered archive/gor tree sha, or "unknown". Same never-crash contract as value().
    static func tree(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let tree = parseTree(text) else { return unknown }
        return tree
    }

    /// UTC launch timestamp for the launch line (ISO 8601, seconds precision).
    static func launchTimestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Exact launch log line: installed BuildID sha, archive/gor tree sha, launch time.
    /// One bounded ASCII line per launch; gor-periodic-capture carries it to the repo.
    static func launchLine(value: String, tree: String, at: Date = Date()) -> String {
        let safeValue = (value.isEmpty || value.contains(where: { $0.isWhitespace })) ? unknown : value
        let safeTree = (tree.isEmpty || tree.contains(where: { $0.isWhitespace })) ? unknown : tree
        return "[GOR] build-id \(safeValue) tree=\(safeTree) launch=\(launchTimestamp(at))"
    }

    /// Short form for the About label (7 chars of the source identity, else as-is).
    static func shortValue(_ value: String) -> String {
        value == unknown ? unknown : String(value.prefix(7))
    }
}
