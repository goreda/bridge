# W-gdb-198y-in2tinct-15
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVCore/OpenURLRouter.swift in shipping-path engine station GorAVCore. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-15.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-15",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVCore/OpenURLRouter.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVCore/OpenURLRouter.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: OpenURLRoute, Reason, OpenURLRouter, host, hostMatches, normalizeInfoHash, route",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-15.py",
    "callee": "Sources/GorAVCore/OpenURLRouter.swift owning station GorAVCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-15.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-15.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-15.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.893507+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVCore/OpenURLRouter.swift",
        "block": "source1",
        "sha256": "0f3fa4238a8d7d9e3cff41bf625b20b1f9da28027667720f81f8424bf8c6ead6"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-15.py",
        "block": "fixtures1",
        "sha256": "4d4ced7e5cc52f90986c3a0af7531ef2e3fd773315a3fab1211b6bdf36e7baf2"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "e986c8ff386d0a45f06c891f8830af13786a4b3bc203b3a7de42c21d53ef4205",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-15: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "dcf68d3342b356f5fab1945296128477d2759243ab98826954ff4b283ee6f6c6"
  }
}
```

```swift id=source1
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
            // URLComponents.host percent-decodes on corelibs Foundation.
            // Enforce raw authority shape before that normalization.
            let rawAuthority = url[r.upperBound...].prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            guard !rawAuthority.contains("%") else { return .refused(.transferLinkShape) }
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

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVCore/OpenURLRouter.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='0f3fa4238a8d7d9e3cff41bf625b20b1f9da28027667720f81f8424bf8c6ead6', 'pinned source changed: rebase and review, never bless silently'
for token in ['OpenURLRoute', 'Reason', 'OpenURLRouter', 'host', 'hostMatches', 'normalizeInfoHash', 'route']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='0f3fa4238a8d7d9e3cff41bf625b20b1f9da28027667720f81f8424bf8c6ead6'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-15: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-15: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
