# W-gdb-049 195b-B5 HLS/IPTV: consuming pin
state: candidate
solver lab: 1nstinct
reviewer lab: unclaimed
id: W-gdb-049

```packet-json
{
 "packet_id": "W-gdb-049",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {
   "path": "Sources/GorAVCore/OpenURLRouter.swift",
   "excerpt_block": "source1"
  },
  {
   "path": "Sources/CFFmpeg/shim.h",
   "excerpt_block": "source2"
  }
 ],
 "interface": {
  "signatures": "OpenURLRouter.route(_ url: String) -> OpenURLRoute (pinned excerpt, full body); gorav_r3_open_input(ctx, url, headers, cookies) -> Int32 (pinned C seam); additive provider layer: variant select(budget: Int64) -> variant; probe-refined seekable; named additive avformat option set (values + FFmpeg version pinned below)",
  "types": "OpenURLRoute { directRemote(id, seekable), needsMegaResolver, needsWebTorrentBridge(subject), refused(Reason) }; Reason 6 cases (pinned)",
  "ownership_lifetime": "avformat context owned by the driver; snapshots immutable; no global cache",
  "caller": "remote open path (video-remote-open)",
  "callee": "the lab HLS/avformat driver behind the pinned admission + option set"
 },
 "test": {
  "command": "python3 kits/b5-hls-pin/check.py kits/b5-hls-pin/fixtures.json",
  "expected": "exit 0; stdout 'b5-hls-pin: 3/3 rows PASS'; selection respects budget and segment boundaries; live edge never offers seek",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVCore/",
   "Sources/GorAVFFmpegAdapter/",
   "kits/b5-hls-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
HLS/IPTV (195b-B5) enters through the pinned URL router and avformat; without pinned provider options and selection/seek/cache rules a lab driver mis-selects variants or offers impossible seeks.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0284/B5; the lab module implements against the pinned interface below.

## expected behaviour
an HLS driver behind the pinned admission seam: OpenURLRouter.route (full body pinned in source1) admits generic http(s) as directRemote(id: url, seekable: true) - the pinned route output's seekable is a STATIC true, not a probe result. The additive provider layer (new layer, NOT the router) sits after admission: it opens via the pinned C seam gorav_r3_open_input (source2; the pinned option set is headers + cookies ONLY - nothing else is pinned), probes the opened context, and MAY downgrade seekable per probe (live edge -> no seek); the probe-refined value lives only in the provider's snapshot, the router is untouched. The provider's EXTRA avformat options are additive and must be named with values and version: pinned here against FFmpeg 8.0.1 (the lab static tree): live_start_index=-1, reconnect=1, reconnect_streamed=1, reconnect_delay_max=7, reconnect_on_network_error=1, reconnect_on_http_error="4xx,5xx", rw_timeout=15000000 (microseconds); these names/values are FFmpeg-version-sensitive, so the 8.0.1 pin is part of the contract. Variant selection: highest variant within a stated bandwidth budget, switch only at segment boundaries; live edge: no seek, live_start_index=-1 policy as above; cache: none beyond avformat-internal buffering (integrator decision; an app-level cache is a separate packet).

## exact call site and interface
OpenURLRouter.swift (pinned excerpt) is the admission gate; SnapshotInput/ActiveTransportSnapshot feed truthful transport state; delivery as driver code + kits/b5-hls-pin/ synthetic-server fixtures.

## behaviour that must not change
the router's refusal taxonomy and redirect-following rule are untouched; non-admitted schemes stay typed refusals.

## acceptance test (from the product repo)
python3 kits/b5-hls-pin/check.py kits/b5-hls-pin/fixtures.json exits 0 against the synthetic loopback server; selection/seek/live-edge rows match goldens.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVCore/OpenURLRouter.swift (sha256 8b60f350, lines 11-101 of 101) (full route() body included)
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
        // transfer.it share links are direct-download http(s) (avformat
        // follows the redirect chain); range-capable, so seekable.
        if hostMatches(host, "transfer.it") { return .directRemote(id: url, seekable: true) }
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
```
### Sources/CFFmpeg/shim.h (sha256 0caee44b, lines 617-631 of 709) (pinned remote-open C seam: the ONLY pinned avformat option set is headers + cookies)
```c id=source2
/* =================== AUTHORED_R3 section begins ===================
 * R3 (arch-195b): remote open with transport options. AVDictionary is not
 * importable by Swift, so the dictionary is built, passed and freed entirely
 * on the C side; Swift only supplies the already-joined strings (or NULL).
 * Returns the avformat_open_input result code. */
static inline int gorav_r3_open_input(AVFormatContext **ctx, const char *url,
                                      const char *headers, const char *cookies) {
    AVDictionary *d = NULL;
    int rc;
    if (headers != NULL && headers[0] != '\0') { av_dict_set(&d, "headers", headers, 0); }
    if (cookies != NULL && cookies[0] != '\0') { av_dict_set(&d, "cookies", cookies, 0); }
    rc = avformat_open_input(ctx, url, NULL, d != NULL ? &d : NULL);
    av_dict_free(&d);
    return rc;
}
```


## roles and state
solver lab: 1nstinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"url": "https://edge.example/master.m3u8", "expect": "router -> directRemote(id: url, seekable: true) per the pinned body (static true, not a probe result); the additive provider layer may later downgrade seekable per probe in its own snapshot"}, {"url": "hls variant set bw budget 1.2M of 1.5M", "expect": "highest variant within budget; switch only at segment boundary"}, {"url": "live edge, probe reports not seekable", "expect": "provider layer offers no seek (router output unchanged); live_start_index=-1 and reconnect option values per the pinned FFmpeg 8.0.1 additive set"}]
```
