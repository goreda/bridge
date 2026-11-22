// Lab yt-dlp adapter logic (G0745 / 195b-B6, lab: 1nstinct), additive consumer
// seam: line-faithful Swift port of kits/b6-ytdlp/ytdlp_adapter.py pure logic:
// secret redaction, cap invariant, argv construction, format resolution with
// per-URL header scoping, stderr classification. The Python carrier with its
// 16-test suite (incl. process timeout/cancel/kill behavior via fake_ytdlp)
// stays vendored in kits/b6-ytdlp as the executable witness. Process spawning
// itself is NOT ported: the seam ends at argv + Resolved; execution is the
// platform integrator's boundary (the lab marked the ABI PROPOSED).
// Python<->Swift parity harness in kit: scenario-driven digest diff.
// Mac/Metal NOT_TESTED.

import Foundation

public enum LabYtdlpError: Error, Equatable, CustomStringConvertible {
    case kind(String, String)
    public var description: String {
        switch self { case .kind(let k, let m): return m.isEmpty ? k : "\(k): \(LabYtdlp.redact(m))" }
    }
    public var kind: String { switch self { case .kind(let k, _): return k } }
}

public enum LabYtdlp {
    public static let maxHeight = 1080
    public static let maxStdout = 8 * 1024 * 1024
    public static let maxStderr = 64 * 1024

    static let secretKeys = "(?:token|sig|signature|key|auth|access_token|id_token|refresh_token|password|passwd|pwd|secret|session|sid|expires?|policy|key-pair-id|credential|apikey|api_key|jwt|bearer)"

    static func rx(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    static let rUserinfo = rx("(?i)(\\w+://)[^/@\\s]*@")
    static let rHdrLine = rx("(?i)((?:set-)?cookie|(?:proxy-)?authorization|x-[\\w-]*(?:token|key|auth|secret|session)[\\w-]*|[\\w-]*(?:token|secret|api-?key)[\\w-]*)\\s*[:=]\\s*[^\\r\\n]*")
    static let rSecretQs = rx("(?i)([?&;]" + secretKeys + "=)[^&\\s\"']*")
    static let rBearer = rx("(?i)\\b(bearer|basic|token)\\s+[A-Za-z0-9._~+/=-]{6,}")
    static let rKv = rx("(?i)([\"']?" + secretKeys + "[\"']?\\s*[:=]\\s*[\"']?)[^\\s,;&\"'}]+")
    static let rJwt = rx("\\beyJ[\\w-]{5,}\\.[\\w-]{5,}(?:\\.[\\w-]*)?")
    static let rLongtok = rx("\\b[A-Za-z0-9_-]{32,}\\b")
    static let rSecretName = rx("(?i)token|secret|auth|cookie|session|api-?key|credential")

    /// Replace matches left-to-right in a single pass (python re.sub semantics:
    /// replacements are never rescanned). repl(currentBase, groupRanges);
    /// groupRanges[0] is the whole match.
    static func sub(_ rx: NSRegularExpression, _ text: String, _ repl: (String, [Range<String.Index>]) -> String) -> String {
        var result = text
        var searchStart = result.startIndex
        while searchStart < result.endIndex,
              let m = rx.firstMatch(in: result, range: NSRange(searchStart..., in: result)) {
            var groups: [Range<String.Index>] = []
            for i in 0..<m.numberOfRanges {
                if let r = Range(m.range(at: i), in: result) { groups.append(r) } else { groups.append(result.endIndex..<result.endIndex) }
            }
            let replacement = repl(result, groups)
            result.replaceSubrange(groups[0], with: replacement)
            searchStart = result.index(groups[0].lowerBound, offsetBy: replacement.count)
        }
        return result
    }

    public static func redact(_ text: String) -> String {
        var t = text
        t = sub(rUserinfo, t) { (b, g) in String(b[g[1]]) + "REDACTED@" }
        t = sub(rHdrLine, t) { (b, g) in String(b[g[1]]) + ": REDACTED" }
        t = sub(rSecretQs, t) { (b, g) in String(b[g[1]]) + "REDACTED" }
        t = sub(rBearer, t) { (b, g) in String(b[g[1]]) + " REDACTED" }
        t = sub(rKv, t) { (b, g) in String(b[g[1]]) + "REDACTED" }
        t = sub(rJwt, t) { (_, _) in "REDACTED" }
        t = sub(rLongtok, t) { (_, _) in "REDACTED" }
        return t
    }

    public static func isSecretHeader(_ name: String) -> Bool {
        let n = name.lowercased()
        let sensitive: Set<String> = ["cookie", "set-cookie", "authorization", "proxy-authorization", "x-api-key"]
        if sensitive.contains(n) { return true }
        return rSecretName.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
    }

    public static func redactHeaders(_ h: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in h { out[k] = isSecretHeader(k) ? "REDACTED" : redact(v) }
        return out
    }

    // Cap is a domain invariant: int in [1, 1080]; anything else is rejected, never clamped.
    // bool / float / string / nil are all invalid, exactly like the Python isinstance checks.
    public static func checkCap(_ maxH: Any?) throws -> Int {
        func invalid() -> LabYtdlpError { .kind("cap_invalid", "max_h must be int in 1..\(maxHeight)") }
        guard let v = maxH else { throw invalid() }
        if let n = v as? NSNumber {
            let t = String(cString: n.objCType)
            if t == "c" || t == "B" { throw invalid() }            // bool
            if t == "d" || t == "f" { throw invalid() }            // float/double
            guard let i = Int(exactly: n), (1...maxHeight).contains(i) else { throw invalid() }
            return i
        }
        if let i = v as? Int, (1...maxHeight).contains(i) { return i }
        throw invalid()
    }

    public static func buildArgv(_ url: String, exe: String = "yt-dlp", cookiesFile: String? = nil, maxH: Any? = maxHeight) throws -> [String] {
        let cap = try checkCap(maxH)
        guard url.range(of: "(?i)^https?://", options: .regularExpression) != nil else {
            throw LabYtdlpError.kind("bad_url", "only http(s) accepted")
        }
        var argv = [exe, "-J", "--no-playlist", "--no-warnings", "--ignore-config",
                    "-f", "bv*[height<=\(cap)]+ba/b[height<=\(cap)]", "--socket-timeout", "15", "--retries", "2"]
        if let cf = cookiesFile {
            guard FileManager.default.fileExists(atPath: cf) else {
                throw LabYtdlpError.kind("cookies_missing", "cookie file not found")
            }
            argv += ["--cookies", cf]  // path handed off, content never read/logged here
        }
        return argv + ["--", url]
    }

    // MARK: format resolution

    public struct Resolved {
        public var title: String = ""
        public var videoUrl: String? = nil
        public var audioUrl: String? = nil
        public var height: Int? = nil
        public var vcodec: String? = nil
        public var acodec: String? = nil
        public var videoHeaders: [String: String] = [:]   // scoped to videoUrl ONLY
        public var audioHeaders: [String: String] = [:]   // scoped to audioUrl ONLY
        public var capped = false
        public var droppedGlobalSecretHeaders = 0

        public func `public`() -> [String: Any?] {
            ["title": String(LabYtdlp.redact(title).prefix(200)),
             "video_url": videoUrl.map { LabYtdlp.redact($0) },
             "audio_url": audioUrl.map { LabYtdlp.redact($0) },
             "height": height, "vcodec": vcodec, "acodec": acodec, "capped": capped,
             "video_headers": LabYtdlp.redactHeaders(videoHeaders),
             "audio_headers": LabYtdlp.redactHeaders(audioHeaders),
             "dropped_global_secret_headers": droppedGlobalSecretHeaders]
        }
    }

    public typealias Format = [String: Any]

    static func has(_ f: Format, _ k: String) -> Bool {
        guard let v = f[k] else { return false }
        if v is NSNull { return false }
        if let s = v as? String { return s != "none" && s != "" }
        return true
    }

    static func height(_ f: Format) -> Int? {
        guard let h = f["height"] else { return nil }
        if let n = h as? NSNumber {
            let t = String(cString: n.objCType)
            if t == "c" || t == "B" || t == "d" || t == "f" { return nil }  // bool/float not admitted
            if let i = Int(exactly: n), i > 0 { return i }
            return nil
        }
        return nil
    }

    static func scoped(_ info: Format, _ f: Format?) -> [String: String] {
        guard let f = f else { return [:] }
        var h: [String: String] = [:]
        for (k, v) in (info["http_headers"] as? [String: Any] ?? [:]) where !isSecretHeader(k) {
            h[k] = "\(v)"
        }
        for (k, v) in (f["http_headers"] as? [String: Any] ?? [:]) { h[k] = "\(v)" }
        return h
    }

    static func num(_ f: Format, _ k: String) -> Double {
        if let n = f[k] as? NSNumber { return n.doubleValue }
        return 0
    }

    public static func resolveFormats(_ infoIn: Format, maxH: Any? = maxHeight) throws -> Resolved {
        let cap = try checkCap(maxH)
        var fm = infoIn["formats"] as? [Format] ?? []
        if fm.isEmpty, infoIn["url"] != nil { fm = [infoIn] }
        if fm.isEmpty { throw LabYtdlpError.kind("no_formats", "") }
        let usable = fm.filter { f in
            guard let u = f["url"] as? String,
                  u.range(of: "(?i)^https?://", options: .regularExpression) != nil else { return false }
            let proto = f["protocol"] as? String ?? ""
            return !proto.hasPrefix("mhtml")
        }
        func video(_ f: Format) -> Bool { has(f, "vcodec") }
        let vids = usable.filter { video($0) && (height($0) ?? 1_000_000_000) <= cap }
        let capped = usable.contains { video($0) && (height($0) == nil || height($0)! > cap) }
        let auds = usable.filter { has($0, "acodec") && !video($0) }
        let key: (Format) -> (Int, Double) = { (height($0) ?? 0, num($0, "tbr")) }
        let akey: (Format) -> Double = { num($0, "abr") != 0 ? num($0, "abr") : num($0, "tbr") }
        let muxed = vids.filter { has($0, "acodec") }
        let vonly = vids.filter { !has($0, "acodec") }
        var v: Format? = nil, a: Format? = nil
        if !vonly.isEmpty, !auds.isEmpty {
            v = vonly.max(by: { key($0) < key($1) })
            a = auds.max(by: { akey($0) < akey($1) })
            if let m = muxed.max(by: { key($0) < key($1) }), let vv = v {
                if key(m) >= key(vv) { v = m; a = nil }
            }
        } else if !muxed.isEmpty {
            v = muxed.max(by: { key($0) < key($1) })
        } else if !vonly.isEmpty {
            v = vonly.max(by: { key($0) < key($1) })
        } else if !auds.isEmpty, !usable.contains(where: { video($0) }) {
            a = auds.max(by: { num($0, "abr") < num($1, "abr") })
        } else {
            throw LabYtdlpError.kind("no_format_within_cap", "no video with known height <= \(cap)p")
        }
        let dropped = (infoIn["http_headers"] as? [String: Any] ?? [:]).keys.filter { isSecretHeader($0) }.count
        var r = Resolved()
        r.title = infoIn["title"] as? String ?? ""
        r.videoUrl = v?["url"] as? String
        r.audioUrl = a?["url"] as? String
        r.height = v.flatMap { height($0) }
        r.vcodec = v?["vcodec"] as? String
        r.acodec = (a ?? v)?["acodec"] as? String
        r.videoHeaders = scoped(infoIn, v)
        r.audioHeaders = scoped(infoIn, a)
        r.capped = capped
        r.droppedGlobalSecretHeaders = dropped
        return r
    }

    static let classes: [(String, String)] = [
        ("auth_required", "sign in|login required|private video|members[- ]only|cookies"),
        ("geo_blocked", "geo|not available in your country"),
        ("unsupported_url", "unsupported url"),
        ("network", "timed out|connection|unable to download|http error 5"),
        ("unavailable", "unavailable|removed|does not exist|http error 404"),
    ]

    public static func classify(_ stderr: String) -> String {
        let s = stderr.lowercased()
        for (k, p) in classes {
            if s.range(of: p, options: .regularExpression) != nil { return k }
        }
        return "extractor_failed"
    }
}
