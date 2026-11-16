# M2-YTDLP-BASELINE-01: measured product <=1080p logic baseline
state: candidate

```packet-json
{
  "packet_id": "M2-YTDLP-BASELINE-01",
  "writer": "gdb",
  "code_owner": "M2-source product lane",
  "product_repo": "goreda/gorav",
  "product_sha": "a34e2cd96b6825932a196424a17cc62962e910a7",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/LabYtdlpAdapter.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "LabYtdlp.checkCap(_:) throws -> Int; argv construction; resolveFormats(_:maxH:) throws -> Resolved",
    "types": "Resolved with selected videoUrl/audioUrl/height, per-URL headers, capped indicator; typed LabYtdlpError",
    "ownership_lifetime": "Pure value-based selection/redaction/argv model; process execution remains outside the Swift seam",
    "caller": "kits/b6-ytdlp/main.swift scenario driver compiled with swiftc",
    "callee": "Product LabYtdlpAdapter.swift at the pin"
  },
  "test": {
    "command": "bash kits/m2-source-packets/ytdlp-baseline.sh",
    "expected": "exit0;16 unittest cases OK;compiled Swift/Python outputs byte-identical;exact marker PARITY OK: 57 scenarios, 172 lines byte-identical; final YTDLP_BASELINE python=0 product_parity=0 exact_marker=0. Does not prove real process spawning or resolved URL playback.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "kits/m2-source-packets/ytdlp-baseline.sh"
    ],
    "return_form": "module"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/m2-source-packets/ytdlp-baseline.sh",
        "block": "runner"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "a34e2cd96b6825932a196424a17cc62962e910a7",
    "command": "bash kits/m2-source-packets/ytdlp-baseline.sh",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-16T11:31:07.725632+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "YTDLP_BASELINE python=0 product_parity=0 exact_marker=0",
    "inline_files": [
      {
        "path": "kits/m2-source-packets/ytdlp-baseline.sh",
        "block": "runner",
        "sha256": "c1ddb7983672c8eb2e6bd4a9be2194a85a0bdfe24a2db0fc68903f0e878f3f36"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "b68702160750f1807084f71f545efef3affbfd03240dbbe04710e3b73135750e",
    "last_5_lines": [
      "Ran 16 tests in 1.015s",
      "",
      "OK",
      "PARITY OK: 57 scenarios, 172 lines byte-identical",
      "YTDLP_BASELINE python=0 product_parity=0 exact_marker=0"
    ],
    "receipt_sha256": "314d91e600b8481c4226ebb335f19432b7988136d034d32a6a13670403a73c54"
  }
}
```

## Scope
Real compiled product selection/cap/argv/redaction logic, compared with the same-lineage Python carrier. Python16 tests include fake process tests; Swift does not spawn a process. No live ytdlp, media-open, TLS or service availability acceptance.

## Count correction
At this pin scenarios.json holds57 entries; parity.py emits one marker per entry. README58 is stale. Prior recipe58 failure remains history. This packet asserts57 and172 exactly without changing any scenario or product assertion.

## Product source (whole file sha256 dc04b472b9feb7e36d8b3596e3d60f81b6f719a91221eab96c290a9af66c3217)
```swift id=source1
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
```

## Pinned scenarios
```json id=fixtures1
[
 {"op":"redact","text":"ERROR: Authorization: Basic dXNlcjpwYXNz end"},
 {"op":"redact","text":"ERROR: authorization=Bearer abc.def.ghi123 end"},
 {"op":"redact","text":"ERROR: Proxy-Authorization: Basic QQQQQQQQ end"},
 {"op":"redact","text":"ERROR: Set-Cookie: a=SECRETX; Path=/ end"},
 {"op":"redact","text":"ERROR: X-Api-Key: SECRETX end"},
 {"op":"redact","text":"ERROR: x-goog-auth-token: SECRETX end"},
 {"op":"redact","text":"ERROR: X-Session-Id: SECRETX end"},
 {"op":"redact","text":"ERROR: https://u:SECRETX@h.invalid/p end"},
 {"op":"redact","text":"ERROR: https://SECRETX@h.invalid/p end"},
 {"op":"redact","text":"ERROR: https://h/p?Signature=SECRETX&Policy=SECRETX&Key-Pair-Id=SECRETX end"},
 {"op":"redact","text":"ERROR: https://h/p;token=SECRETX end"},
 {"op":"redact","text":"ERROR: {\"password\": \"SECRETX\"} end"},
 {"op":"redact","text":"ERROR: password=SECRETX end"},
 {"op":"redact","text":"ERROR: access_token: SECRETX end"},
 {"op":"redact","text":"ERROR: eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJTRUNSRVRYIn0.sigsigsig end"},
 {"op":"redact","text":"ERROR: id=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA end"},
 {"op":"redact","text":"ERROR: COOKIE:SECRETX end"},
 {"op":"redact","text":"ERROR: cookie = SECRETX; b=SECRETX end"},
 {"op":"redact_headers","headers":{"X-Custom-Token":"v","Proxy-Authorization":"v","Referer":"https://r/"}},
 {"op":"is_secret","name":"X-Session-Id"},
 {"op":"is_secret","name":"User-Agent"},
 {"op":"is_secret","name":"x-api-key"},
 {"op":"check_cap","value":1080},
 {"op":"check_cap","value":1081},
 {"op":"check_cap","value":0},
 {"op":"check_cap","value":-1},
 {"op":"check_cap","value":"1080"},
 {"op":"check_cap","value":null},
 {"op":"check_cap","value":1080.0},
 {"op":"check_cap","value":true},
 {"op":"check_cap","value":1},
 {"op":"argv","url":"https://e.invalid/?a=1&b=2; rm -rf /"},
 {"op":"argv","url":"file:///etc/passwd"},
 {"op":"argv","url":"--exec=x"},
 {"op":"argv","url":"ftp://x"},
 {"op":"argv","url":"https://e.invalid/","cookies_file":"/nonexistent"},
 {"op":"argv","url":"https://e.invalid/","cookies_file":"fixtures/ok.json"},
 {"op":"argv","url":"https://e.invalid/","max_h":720},
 {"op":"resolve","info_file":"ok.json"},
 {"op":"resolve","info_file":"xorigin.json"},
 {"op":"resolve","info":{"formats":[{"url":"https://e/u1","height":720,"vcodec":"a","acodec":"b","tbr":1},{"url":"https://e/u2","height":720,"vcodec":"a","acodec":"none","tbr":2},{"url":"https://e/u3","vcodec":"none","acodec":"o","abr":9}]}},
 {"op":"resolve","info":{"formats":[{"url":"https://e.invalid/n","vcodec":"av01","acodec":"opus"}]}},
 {"op":"resolve","info":{"formats":[{"url":"https://e.invalid/n","vcodec":"av01","acodec":"opus","height":"720"}]}},
 {"op":"resolve","info":{"formats":[{"url":"https://e.invalid/n","vcodec":"av01","acodec":"opus","height":0}]}},
 {"op":"resolve","info":{"formats":[{"url":"https://e/x","vcodec":"a","acodec":"b","height":1081},{"url":"https://e/y","vcodec":"a","acodec":"b","height":1080}]},"max_h":1080},
 {"op":"resolve","info":{"formats":[{"url":"https://e/x","vcodec":"a","acodec":"b","height":720},{"url":"https://e/y","vcodec":"a","acodec":"b","height":480}]},"max_h":600},
 {"op":"resolve","info":{"formats":[{"format_id":"x","height":2160,"vcodec":"av01","acodec":"opus","url":"https://e.invalid/x"}]}},
 {"op":"resolve","info":{"title":"only audio","formats":[{"url":"https://e/a1","vcodec":"none","acodec":"opus","abr":128},{"url":"https://e/a2","vcodec":"none","acodec":"aac","abr":64}]}},
 {"op":"resolve","info":{"url":"https://e.invalid/direct","height":720,"vcodec":"avc1","acodec":"aac"}},
 {"op":"resolve","info":{"formats":[]}},
 {"op":"resolve","info":{"formats":[{"url":"https://e/m","height":100,"vcodec":"a","acodec":"b","protocol":"mhtml"}]}},
 {"op":"classify","stderr":"ERROR: Sign in to confirm. Cookie: sid=x"},
 {"op":"classify","stderr":"This video is not available in your country"},
 {"op":"classify","stderr":"ERROR: Unsupported URL: https://x"},
 {"op":"classify","stderr":"unable to download video data: timed out"},
 {"op":"classify","stderr":"ERROR: HTTP Error 404: Not Found"},
 {"op":"classify","stderr":"something entirely novel happened"}
]
```

## Packet runner
```sh id=runner
#!/usr/bin/env bash
set -u -o pipefail
cd kits/b6-ytdlp
export SWIFTC=${SWIFTC:-swiftc} PYTHONDONTWRITEBYTECODE=1
"$SWIFTC" --version || exit 2
python3 -m unittest test_ytdlp_adapter -v; prc=$?
bash run_parity.sh | tee /tmp/m2-ytdlp-canonical.out; src=$?
grep -qx 'PARITY OK: 57 scenarios, 172 lines byte-identical' /tmp/m2-ytdlp-canonical.out; mrc=$?
printf 'YTDLP_BASELINE python=%s product_parity=%s exact_marker=%s\n' "$prc" "$src" "$mrc"
[ "$prc" -eq 0 ] && [ "$src" -eq 0 ] && [ "$mrc" -eq 0 ]
```

```text id=actual_run_log
Swift version 6.1.2 (swift-6.1.2-RELEASE)
Target: x86_64-unknown-linux-gnu
test_1080_cap (test_ytdlp_adapter.T) ... /tmp/packet-proof-6ixfpahj/tree/kits/b6-ytdlp/test_ytdlp_adapter.py:5: ResourceWarning: unclosed file <_io.BufferedReader name=4>
  return Y.resolve("https://example.invalid/watch?v=1", exe=FAKE, env={"FAKE_MODE": mode}, **kw)
ResourceWarning: Enable tracemalloc to get the object allocation traceback
/tmp/packet-proof-6ixfpahj/tree/kits/b6-ytdlp/test_ytdlp_adapter.py:5: ResourceWarning: unclosed file <_io.BufferedReader name=6>
  return Y.resolve("https://example.invalid/watch?v=1", exe=FAKE, env={"FAKE_MODE": mode}, **kw)
ResourceWarning: Enable tracemalloc to get the object allocation traceback
ok
test_adversarial_redaction (test_ytdlp_adapter.T) ... /usr/lib/python3.10/traceback.py:236: ResourceWarning: unclosed file <_io.BufferedReader name=4>
  tb.tb_frame.clear()
ResourceWarning: Enable tracemalloc to get the object allocation traceback
/usr/lib/python3.10/traceback.py:236: ResourceWarning: unclosed file <_io.BufferedReader name=6>
  tb.tb_frame.clear()
ResourceWarning: Enable tracemalloc to get the object allocation traceback
ok
test_argv_safety (test_ytdlp_adapter.T) ... ok
test_bad_json (test_ytdlp_adapter.T) ... ok
test_cancel (test_ytdlp_adapter.T) ... ok
test_cap_is_invariant (test_ytdlp_adapter.T) ... ok
test_cookie_file_handoff (test_ytdlp_adapter.T) ... ok
test_env_not_inherited (test_ytdlp_adapter.T) ... /tmp/packet-proof-6ixfpahj/tree/kits/b6-ytdlp/test_ytdlp_adapter.py:47: ResourceWarning: unclosed file <_io.BufferedReader name=4>
  os.environ["LEAK_TEST"]="1"; r = Y.resolve("https://e.invalid/", exe=FAKE, env={"FAKE_MODE":"argv"}); self.assertTrue(r.video_url)
ResourceWarning: Enable tracemalloc to get the object allocation traceback
/tmp/packet-proof-6ixfpahj/tree/kits/b6-ytdlp/test_ytdlp_adapter.py:47: ResourceWarning: unclosed file <_io.BufferedReader name=6>
  os.environ["LEAK_TEST"]="1"; r = Y.resolve("https://e.invalid/", exe=FAKE, env={"FAKE_MODE":"argv"}); self.assertTrue(r.video_url)
ResourceWarning: Enable tracemalloc to get the object allocation traceback
ok
test_failure_classified_and_redacted (test_ytdlp_adapter.T) ... ok
test_headers_scoped_per_url (test_ytdlp_adapter.T) ... ok
test_muxed_preferred_only_if_not_worse (test_ytdlp_adapter.T) ... ok
test_no_format_within_cap (test_ytdlp_adapter.T) ... ok
test_redaction (test_ytdlp_adapter.T) ... ok
test_timeout_kills (test_ytdlp_adapter.T) ... ok
test_title_redacted (test_ytdlp_adapter.T) ... ok
test_unknown_height_rejected_not_zero (test_ytdlp_adapter.T) ... ok

----------------------------------------------------------------------
Ran 16 tests in 1.015s

OK
PARITY OK: 57 scenarios, 172 lines byte-identical
YTDLP_BASELINE python=0 product_parity=0 exact_marker=0
```
