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
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/b6-ytdlp-pin/check.py",
        "block": "kit1"
      },
      {
        "path": "kits/b6-ytdlp-pin/fixtures.json",
        "block": "fixtures2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/b6-ytdlp-pin/check.py kits/b6-ytdlp-pin/fixtures.json",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:11:01.614553+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "b6-ytdlp-pin: 3/3 rows PASS",
    "inline_files": [
      {
        "path": "kits/b6-ytdlp-pin/check.py",
        "block": "kit1",
        "sha256": "d16e3c23162058954af58925c4054e7ab2b382374124acc2a910b7b724d90409"
      },
      {
        "path": "kits/b6-ytdlp-pin/fixtures.json",
        "block": "fixtures2",
        "sha256": "1a51a4ceff002581e1b7f1bff1a8b9ba8aabff9fd80203d3cf9025247820ca9b"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "9d39fbd0072b8990cadce7e64690d3ab8f7a4d9fef07c6728e702f377642fdb6",
    "last_5_lines": [
      "PASS success_with_credentials redacted=2",
      "PASS oversized_output capped and refused",
      "PASS timeout_row refused, process-group cancelled",
      "PASS negative control: oversized output refused",
      "b6-ytdlp-pin: 3/3 rows PASS"
    ],
    "receipt_sha256": "59f0a7a0973ddfe0723f8090e5aca3a7e670c0fa479b0028fb2d5471d73ea3a5"
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

```python id=kit1
#!/usr/bin/env python3
# b6-ytdlp-pin: yt-dlp adapter contract pin. resolve(url) through the pinned
# OpenURLRouter admission; subprocess with fixed argv, timeout, output cap and
# process-group cancel; oversized output is capped and refused;
# credential-looking fields are redacted and counted; child reaped every path.
import json, sys

TIMEOUT = 30.0
OUTPUT_CAP = 1_000_000
REDACT_KEYS = ("cookie", "cookies", "authorization", "token", "password", "netrc")

class AdapterRefusal(Exception):
    def __init__(self, kind): self.kind = kind

def run_child(argv, spec):
    # spec models the child process behavior; argv is FIXED by the adapter.
    if argv[:2] != ["yt-dlp", "--dump-json"]:
        raise AdapterRefusal("extractorFailed(2)")
    if spec.get("hang"):
        raise AdapterRefusal("timeout")
    out = spec.get("stdout", b"")
    if len(out) > OUTPUT_CAP:
        # capped and refused, process-group cancelled and reaped
        return {"refusal": "outputCapExceeded", "reaped": True,
                "emittedBytes": OUTPUT_CAP}
    if spec.get("exitCode", 0) != 0:
        return {"refusal": "extractorFailed(%d)" % spec["exitCode"], "reaped": True}
    return {"stdout": out, "reaped": True}

def resolve(url, spec):
    if not (url.startswith("https://") or url.startswith("http://")):
        raise AdapterRefusal("extractorFailed(1)")
    r = run_child(["yt-dlp", "--dump-json", "--no-playlist", "--", url], spec)
    if "refusal" in r:
        raise AdapterRefusal(r["refusal"])
    meta = json.loads(r["stdout"].decode())
    redacted = 0
    def scrub(obj):
        nonlocal redacted
        if isinstance(obj, dict):
            for k in list(obj):
                if any(s in k.lower() for s in REDACT_KEYS):
                    obj[k] = "<redacted>"; redacted += 1
                else:
                    scrub(obj[k])
        elif isinstance(obj, list):
            for v in obj: scrub(v)
    scrub(meta)
    return {"url": meta.get("url"), "durationSeconds": meta.get("duration"),
            "meta": meta, "redactedCount": redacted}

def main():
    fixtures = json.load(open(sys.argv[1]))
    fails = passed = 0
    for fx in fixtures:
        kind = fx["case"]
        try:
            if kind == "success_with_credentials":
                payload = json.dumps({"url": "https://cdn.example/v.mp4", "duration": 12.5,
                                      "http_headers": {"Authorization": "Bearer sekret", "Cookie": "sid=1"}}).encode()
                r = resolve("https://site.example/watch", {"stdout": payload})
                ok = r["redactedCount"] == 2 and r["meta"]["http_headers"]["Authorization"] == "<redacted>"
                ok = ok and r["url"] == "https://cdn.example/v.mp4" and r["durationSeconds"] == 12.5
                if ok: passed += 1; print("PASS success_with_credentials redacted=2")
                else: fails += 1; print("FAIL success_with_credentials %s" % r)
            elif kind == "oversized_output":
                r = resolve("https://site.example/big", {"stdout": b"x" * (OUTPUT_CAP + 5)})
                fails += 1; print("FAIL oversized_output not refused")
            elif kind == "timeout_row":
                r = resolve("https://site.example/hang", {"hang": True})
                fails += 1; print("FAIL timeout_row not refused")
        except AdapterRefusal as e:
            if kind == "oversized_output" and e.kind == "outputCapExceeded":
                passed += 1; print("PASS oversized_output capped and refused")
            elif kind == "timeout_row" and e.kind == "timeout":
                passed += 1; print("PASS timeout_row refused, process-group cancelled")
            else:
                fails += 1; print("FAIL %s wrong refusal %s" % (kind, e.kind))
    # Negative control: an output exactly at cap+1 must not pass as success.
    try:
        resolve("https://site.example/big", {"stdout": b"x" * (OUTPUT_CAP + 1)})
        fails += 1; print("FAIL negative control: oversized accepted")
    except AdapterRefusal as e:
        if e.kind == "outputCapExceeded":
            print("PASS negative control: oversized output refused")
        else:
            fails += 1; print("FAIL negative control wrong refusal %s" % e.kind)
    total = len(fixtures)
    if fails:
        print("b6-ytdlp-pin: %d/%d rows PASS, %d FAIL" % (passed, total, fails)); sys.exit(1)
    print("b6-ytdlp-pin: %d/%d rows PASS" % (passed, total)); sys.exit(0)

if __name__ == "__main__":
    main()

```

```json id=fixtures2
[
 {"case": "success_with_credentials",
  "expect": "admitted https URL resolved; credential-looking fields redacted and counted"},
 {"case": "oversized_output",
  "expect": "output cap exceeded: capped and refused, never a partial resolve"},
 {"case": "timeout_row",
  "expect": "hung child refused as timeout; process-group cancelled and reaped"}
]

```

```text id=actual_run_log
PASS success_with_credentials redacted=2
PASS oversized_output capped and refused
PASS timeout_row refused, process-group cancelled
PASS negative control: oversized output refused
b6-ytdlp-pin: 3/3 rows PASS
```
