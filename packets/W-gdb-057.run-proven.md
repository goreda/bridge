# W-gdb-057 R3 open-url routing witness (product suite, M2-sources lane)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-057

```packet-json
{
  "packet_id": "W-gdb-057",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
  "touched_files": [
    {
      "path": "Sources/GorAVCore/OpenURLRouter.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "OpenURLRouter.route(_ url: String) -> OpenURLRoute",
    "types": "OpenURLRoute { directRemote(id:seekable:) / needsMegaResolver / needsWebTorrentBridge(subject:) / refused(Reason) }",
    "ownership_lifetime": "pure classification over the URL string; no networking; refusal reasons are typed tokens only",
    "caller": "open(url:) admission on the live open path",
    "callee": "GorAVCore.OpenURLRouter (pinned, excerpted)"
  },
  "test": {
    "command": "swift run open-url-tests",
    "expected": "exit 0; final line matches '^open-url-tests: [1-9][0-9]* PASS, 0 FAIL$' with N >= 19; the product's own R3 witness suite",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "Sources/open-url-tests/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/open-url-tests/main.swift",
        "block": "rf1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
    "command": "swift run open-url-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:58:06.161132+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "open-url-tests: 19 PASS, 0 FAIL",
    "inline_files": [
      {
        "path": "Sources/open-url-tests/main.swift",
        "block": "rf1",
        "sha256": "4c31fb42ce1308f20bfa8db4f0e59755ae075a592f8fd7d62b0fa9d5c4f6ee91"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "94f3ed02b215d7e2f6fbf760a2bd03a520c96d8f8403914c022b82834d2e9622",
    "last_5_lines": [
      "[13/16] Wrapping AST for open-url-tests for debugging",
      "[14/16] Write Objects.LinkFileList",
      "[15/16] Linking open-url-tests",
      "Build complete! (2.56s)",
      "open-url-tests: 19 PASS, 0 FAIL"
    ],
    "receipt_sha256": "0cb8501d213bcd0d72b4f568f4e6b263de716ac1e27e423b7b838df6d87dc3b5"
  }
}
```

## problem (what fails for the user)
gor's daily path opens transfer.it / mega / torrent sources today; if gorav's
open(url:) routing misclassifies one (a mega link opened raw, a magnet handed
to avformat), the owner hits a dead open with no typed reason.

## reproducer
- repo: goreda/gorav @ 91a359f7b38cc0e6c4974661d85f389ef6041b1f (branch main).
- real source: Sources/GorAVCore/OpenURLRouter.swift (excerpt below).
- real test command: swift run open-url-tests (the product's own R3 witness target, Linux).

## expected behaviour
the product suite's 19 rows stay green at the pin: transfer.it direct; mega to
its resolver; magnet/.torrent to the wt_server bridge; typed refusals with no
URL content. Companion matrix W-gdb-056 covers the remaining M2 kinds.

```text id=rf1
import Foundation
import GorAVCore

// R3 (arch-195l) witness: open(url:) classification for transfer.it, mega,
// torrent/magnet and generic admitted remotes; typed refusals; no URL
// content in reasons.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

// transfer.it
check("R1-transferit-share", OpenURLRouter.route("https://transfer.it/s/AbCdEf123")
      == .directRemote(id: "https://transfer.it/s/AbCdEf123", seekable: true))
check("R2-transferit-subdomain", OpenURLRouter.route("https://www.transfer.it/t/xyz")
      == .directRemote(id: "https://www.transfer.it/t/xyz", seekable: true))

// mega
check("R3-mega-file", OpenURLRouter.route("https://mega.nz/file/AbC123#SecretKey") == .needsMegaResolver)
check("R4a-mega-folder", OpenURLRouter.route("https://mega.nz/folder/AbC#key") == .needsMegaResolver)
check("R4b-mega-conz-legacy", OpenURLRouter.route("https://mega.co.nz/#!abc!def") == .needsMegaResolver)
check("R5-mega-bare", OpenURLRouter.route("https://mega.nz/") == .refused(.megaLinkShape))

// torrent / magnet
check("R6-magnet-hex", OpenURLRouter.route("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=x")
      == .needsWebTorrentBridge(subject: "0123456789abcdef0123456789abcdef01234567"))
check("R6b-magnet-hex-case", OpenURLRouter.route("magnet:?xt=urn:btih:0123456789ABCDEF0123456789ABCDEF01234567")
      == .needsWebTorrentBridge(subject: "0123456789abcdef0123456789abcdef01234567"))
check("R7-magnet-base32", OpenURLRouter.route("magnet:?xt=urn:btih:ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
      == .needsWebTorrentBridge(subject: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"))
check("R8-magnet-no-xt", OpenURLRouter.route("magnet:?dn=nohash") == .refused(.magnetMissingBtih))
check("R9-magnet-bad-hash", OpenURLRouter.route("magnet:?xt=urn:btih:0123") == .refused(.magnetBadInfoHash))
check("R10-torrent-url", OpenURLRouter.route("https://example.com/files/a.torrent?x=1")
      == .needsWebTorrentBridge(subject: "https://example.com/files/a.torrent?x=1"))
check("R10b-torrent-case", OpenURLRouter.route("https://example.com/A.TORRENT")
      == .needsWebTorrentBridge(subject: "https://example.com/A.TORRENT"))

// generic remote + refusals
check("R11-generic-https", OpenURLRouter.route("https://cdn.example.com/film.mkv")
      == .directRemote(id: "https://cdn.example.com/film.mkv", seekable: true))
check("R12-ftp-refused", OpenURLRouter.route("ftp://example.com/film.mkv") == .refused(.schemeNotAdmitted))
check("R13-unparseable", OpenURLRouter.route("not a url") == .refused(.unparseable))
check("R14-empty-host", OpenURLRouter.route("https:///path/file.mkv") == .refused(.emptyHost))
check("R15-userinfo-port", OpenURLRouter.route("https://user:secret@mega.nz:8443/file/a#k") == .needsMegaResolver)
check("R16-uppercase", OpenURLRouter.route("HTTPS://TRANSFER.IT/s/x")
      == .directRemote(id: "HTTPS://TRANSFER.IT/s/x", seekable: true))

print("open-url-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)

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

```text id=fixtures1
fixtures embedded in the product suite (Sources/open-url-tests/main.swift):
transfer.it share + subdomain; mega file/folder/legacy-co.nz + bare-host refusal;
magnet btih 40-hex (both cases) / 32-base32 / missing xt / bad hash; .torrent URL
(both cases); generic https; ftp refusal; unparseable; empty host; userinfo+port
mega; uppercase scheme+host.
```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-j915x9d1/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-j915x9d1/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-j915x9d1/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/8] Write sources
[2/8] Compiling GorAVCAtomics gorav_atomics.c
[3/8] Write swift-version--9C6B84B6E025C5B.txt
[5/11] Emitting module GorAVCore
[6/11] Compiling GorAVCore AdmissionTable.swift
[7/11] Compiling GorAVCore Boundary.swift
[8/12] Compiling GorAVCore OpenURLRouter.swift
[9/13] Wrapping AST for GorAVCore for debugging
[11/15] Emitting module open_url_tests
[12/15] Compiling open_url_tests main.swift
[13/16] Wrapping AST for open-url-tests for debugging
[14/16] Write Objects.LinkFileList
[15/16] Linking open-url-tests
Build complete! (2.56s)
open-url-tests: 19 PASS, 0 FAIL
```
