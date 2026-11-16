import Foundation

// R3 (arch-195l, dispatch L6): open(url:) classification for transfer.it /
// mega / torrent. Pure classification over the URL string; no networking.
// Refusal reasons are typed tokens ONLY - they never carry URL content, so
// nothing here needs redaction. Routing policy follows AdmissionTable: the
// engine admits resolved http(s) URLs only; mega links need the external
// mega resolve/decrypt step first, magnet/.torrent needs the wt_server
// bridge first (both re-enter later as admitted http(s) descriptors).

public enum OpenURLRoute: Equatable, Sendable {
    /// Admitted remote open: the URL goes to the admitted remote path as-is
    /// (only already-resolved media URLs, not transfer.it share pages).
    case directRemote(id: String, seekable: Bool)
    /// mega.nz / mega.co.nz link: the external mega step must resolve and
    /// decrypt to an admitted http(s) URL before the engine can open it.
    case needsTransferResolver
    case needsMegaResolver
    /// magnet: URI or .torrent URL: the wt_server bridge must serve an
    /// admitted http(s) URL first. `subject` is the normalized btih
    /// infohash (40-hex lowercased, or 32-char base32 uppercased) for
    /// magnet:, or the original .torrent URL.
    case needsWebTorrentBridge(subject: String)
    /// Typed refusal; reason is a token, never URL content.
    case refused(Reason)

    public enum Reason: String, Equatable, Sendable {
        case unparseable
        case schemeNotAdmitted
        case emptyHost
        case magnetMissingBtih
        case magnetBadInfoHash
        case megaLinkShape
        case transferLinkShape
    }
}

public enum OpenURLRouter {
    /// Lowercased host of an admitted-scheme URL: userinfo and port
    /// stripped, nil when no "://" or the authority is empty.
    static func host(of url: String, schemeEnd: String.Index) -> String? {
        let rest = url[schemeEnd...].dropFirst(3)   // past "://"
        var authority = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if let at = authority.lastIndex(of: "@") { authority = authority[authority.index(after: at)...] }
        let host = authority.prefix { $0 != ":" }
        guard !host.isEmpty else { return nil }
        return host.lowercased()
    }

    static func hostMatches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    /// Normalize a btih infohash: 40-char hex (lowercased) or 32-char
    /// base32 (uppercased); nil otherwise.
    static func normalizeInfoHash(_ raw: String) -> String? {
        if raw.count == 40, raw.allSatisfy({ $0.isHexDigit }) { return raw.lowercased() }
        if raw.count == 32, raw.allSatisfy({ ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("2"..."7").contains($0) }) {
            return raw.uppercased()
        }
        return nil
    }

    public static func route(_ url: String) -> OpenURLRoute {
        guard !url.isEmpty else { return .refused(.unparseable) }
        // magnet: has no "//", so it never survives the scheme gate; handle first.
        if url.lowercased().hasPrefix("magnet:") {
            guard let q = url.firstIndex(of: "?") else { return .refused(.magnetMissingBtih) }
            let params = url[url.index(after: q)...].split(separator: "&")
            for p in params {
                let lower = p.lowercased()
                if lower.hasPrefix("xt=urn:btih:") {
                    let raw = String(p.dropFirst("xt=urn:btih:".count))
                    guard let hash = normalizeInfoHash(raw) else { return .refused(.magnetBadInfoHash) }
                    return .needsWebTorrentBridge(subject: hash)
                }
            }
            return .refused(.magnetMissingBtih)
        }
        guard let r = url.range(of: "://"),
              let scheme = AdmissionTable.remoteScheme(of: url),
              AdmissionTable.admittedRemoteSchemes.contains(scheme) else {
            return .refused(url.range(of: "://") == nil ? .unparseable : .schemeNotAdmitted)
        }
        guard let host = host(of: url, schemeEnd: r.lowerBound) else { return .refused(.emptyHost) }
        // A share page is not media. Only the measured transfer URL shape
        // reaches explicit preparation; never guess a file within a transfer.
        if hostMatches((URLComponents(string: url)?.host ?? host).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")), "transfer.it") {
            guard let parsed = URLComponents(string: url),
                  parsed.scheme?.lowercased() == "https", parsed.host?.lowercased() == "transfer.it",
                  parsed.user == nil, parsed.password == nil, parsed.port == nil,
                  parsed.query == nil, parsed.fragment == nil, parsed.percentEncodedPath == parsed.path else { return .refused(.transferLinkShape) }
            let parts = parsed.path.split(separator: "/", omittingEmptySubsequences: true)
            guard parts.count == 2, parts[0] == "t", !parts[1].isEmpty,
                  parts[1].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
                  parsed.path == "/t/" + String(parts[1]) || parsed.path == "/t/" + String(parts[1]) + "/" else { return .refused(.transferLinkShape) }
            return .needsTransferResolver
        }
        // mega links carry their key material in the fragment; the engine
        // never speaks the mega API.
        if hostMatches(host, "mega.nz") || hostMatches(host, "mega.co.nz") {
            let ok = url.contains("/file/") || url.contains("/folder/") || url.contains("#!")
            return ok ? .needsMegaResolver : .refused(.megaLinkShape)
        }
        // A .torrent file URL goes to the bridge like a magnet.
        let pathOnly = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
        if pathOnly.lowercased().hasSuffix(".torrent") {
            return .needsWebTorrentBridge(subject: url)
        }
        // Everything else on an admitted scheme is a plain remote source.
        return .directRemote(id: url, seekable: true)
    }
}
