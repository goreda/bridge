# W-gdb-050 195b-B6 yt-dlp adapter: consuming pin
state: candidate
solver lab: 1nstinct
reviewer lab: unclaimed
id: W-gdb-050

```packet-json
{
 "packet_id": "W-gdb-050",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {
   "path": "Sources/GorAVCore/OpenURLRouter.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "OpenURLRouter.route(_ url: String) -> OpenURLRoute (pinned excerpt); additive adapter: resolve(url: String) -> Result<ResolvedRemote, AdapterRefusal>; subprocess: fixed argv, timeout, output cap, process-group cancel",
  "types": "ResolvedRemote { url: admitted http(s), headers redacted, durationSeconds? }; AdapterRefusal { timeout, outputCapExceeded, extractorFailed(code), cancelled }",
  "ownership_lifetime": "child process reaped on every path; output buffer bounded and freed; no credentials retained past redaction",
  "caller": "app-side resolver feeding the admitted remote open path",
  "callee": "the lab adapter behind resolve; the router unchanged"
 },
 "test": {
  "command": "python3 kits/b6-ytdlp-pin/check.py kits/b6-ytdlp-pin/fixtures.json",
  "expected": "exit 0; stdout 'b6-ytdlp-pin: 3/3 rows PASS'; oversized output is capped and refused; credential-looking fields redacted and counted",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVCore/",
   "kits/b6-ytdlp-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
the yt-dlp adapter (195b-B6) resolves non-admitted URLs; without the pinned router seam and subprocess bounds it becomes an unbounded credential-leaking shell-out.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0285/B6; the lab module implements against the pinned interface below.

## expected behaviour
a bounded subprocess adapter following the pinned resolver pattern (needsMegaResolver / needsWebTorrentBridge): non-admitted-scheme URLs (e.g. ftp:) stay refused(.schemeNotAdmitted) in OpenURLRouter, while generic https is admitted directRemote(id: url, seekable: true) by the pinned body - the adapter's job is extractor resolution of admitted URLs, not scheme gating (router pinned, untouched); the adapter is additive: resolve(url) -> Result<admitted http(s) URL + media JSON, AdapterRefusal>; subprocess ABI: fixed argv (no shell), timeout enforced, stdout byte cap enforced, cancel kills the process group; any credential-looking field in extractor output is redacted before any surface and the redaction is counted; no live paid or authenticated calls in tests (synthetic fake extractor only).

## exact call site and interface
OpenURLRouter.swift (pinned excerpt) is the admission gate the adapter feeds; the adapter itself is app-side additive code + kits/b6-ytdlp-pin/ fake-extractor fixtures.

## behaviour that must not change
the router stays closed-world: unadmitted schemes refuse typed unless an adapter resolves them first; no router change in this packet.

## acceptance test (from the product repo)
python3 kits/b6-ytdlp-pin/check.py kits/b6-ytdlp-pin/fixtures.json exits 0; cap/timeout/cancel/redaction rows match goldens against the fake extractor.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVCore/OpenURLRouter.swift (sha256 8b60f350, lines 11-62 of 101)
```swift id=source1
public enum OpenURLRoute: Equatable, Sendable {
    /// Admitted remote open: the URL goes to the admitted remote path as-is
    /// (avformat follows redirects, e.g. transfer.it share links).
    case directRemote(id: String, seekable: Bool)
    /// mega.nz / mega.co.nz link: the external mega step must resolve and
    /// decrypt to an admitted http(s) URL before the engine can open it.
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
```


## roles and state
solver lab: 1nstinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"url": "https://unsupported-site.example/watch?v=x", "expect": "router -> directRemote(id: url, seekable: true) per the pinned body (generic admitted https, NOT schemeNotAdmitted); the adapter decision is separate: resolve() runs the fake extractor and returns ResolvedRemote or AdapterRefusal.extractorFailed(code)"}, {"process": "fake extractor emits 10MB json", "expect": "bounded: output cap enforced, process killed, typed refusal"}, {"process": "json contains Authorization header", "expect": "header redacted before any surface; redaction counter increments"}]
```
