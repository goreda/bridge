import Foundation

/// One process/player's current WT endpoint, admitted from its owned child's
/// STREAM readiness only. A loopback URL or a token-shaped query alone is not
/// proof that another local server belongs to this player.
enum PlayerTorrentEndpoint {
    private static let lock = NSLock()
    private static var current: URLComponents?
    @discardableResult static func admit(_ raw: String) -> Bool {
        guard let u = URLComponents(string: raw), u.scheme == "http",
              u.user == nil, u.password == nil,
              let host = u.host?.lowercased(), ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host),
              let port = u.port, (1...65535).contains(port),
              u.path == "/", u.fragment == nil else { return false }
        lock.lock(); current = u; lock.unlock()
        return true
    }
    static func clear() { lock.lock(); current = nil; lock.unlock() }
    static func isCurrent(_ raw: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return matchesLocked(raw)
    }
    private static func matchesLocked(_ raw: String) -> Bool {
        guard let u = URLComponents(string: raw), let c = current else { return false }
        return u.scheme == c.scheme && u.host?.lowercased() == c.host?.lowercased() && u.port == c.port
            && u.path == c.path && u.percentEncodedQuery == c.percentEncodedQuery && u.user == nil && u.password == nil && u.fragment == nil
    }
    static func playbackToken(_ raw: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard matchesLocked(raw), let u = URLComponents(string: raw),
              let values = u.queryItems?.filter({ $0.name == "gor_stream" }), values.count == 1,
              let token = values[0].value, !token.isEmpty else { return nil }
        return token
    }
    /// Build and submit under the same endpoint generation lock. The callback
    /// must only create/resume its request and must not call this registry.
    /// Rotation/clear cannot interleave identity validation and submission.
    @discardableResult static func withControlURL(for media: String, token: String? = nil,
                                                path: String, submit: (URL) -> Void) -> Bool {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("?"), !path.contains("#") else { return false }
        lock.lock(); defer { lock.unlock() }
        guard matchesLocked(media), var c = current else { return false }
        if let token {
            let values = c.queryItems?.filter { $0.name == "gor_stream" } ?? []
            guard values.count == 1, values[0].value == token, !token.isEmpty else { return false }
        }
        c.path = path; c.query = nil; c.fragment = nil
        guard let url = c.url else { return false }
        submit(url)
        return true
    }
    static func controlURL(path: String) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("?"), !path.contains("#") else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard var c = current else { return nil }
        c.path = path; c.query = nil; c.fragment = nil
        return c.url
    }
}
