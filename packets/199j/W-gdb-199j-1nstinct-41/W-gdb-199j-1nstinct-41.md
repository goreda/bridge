# W-gdb-199j-1nstinct-41 - nativeArchiveEntryURL double-percent-encodes the archive container path

state: VERIFIED
lab: 1nstinct | product: goreda/instinct @ b60352dabc87fe8519832999b4af639f37d786f8 | scope: `archive/gor/Sources/gor/GorUI/MenuActions.swift`

## Goal
Percent-encoded characters in the archive.org container name (e.g. my%20item.zip) must reach mpv's libarchive entry URL encoded exactly once.

## Caller scope
CALLER SCOPE: archive load route, MenuActions.swift:1363 (`let loadURL = isArchive ? Self.nativeArchiveEntryURL(finalURL) ?? finalURL : finalURL`). Shipping caller in the same file.

## Extraction
Extracted the single static function nativeArchiveEntryURL (pure String -> String?, Foundation-only) from the pinned file; compiled standalone with the test driver.
Attribution comment lines elided from the packet source copy: 14; sha256 below covers the elided copy.

## Verification (Swift 6.0.3, Linux)

- red_Onone: compile_exit=0 semantic_exit=1 -> PASS
- red_O: compile_exit=0 semantic_exit=1 -> PASS
- green_Onone: compile_exit=0 semantic_exit=0 -> PASS
- green_O: compile_exit=0 semantic_exit=0 -> PASS

Expected: pinned RED exit=1 (double-encoded container), fixed GREEN exit=0.

## Fix
Decode each container path segment (removingPercentEncoding) before the single re-encode pass, so an already-encoded container name round-trips exactly once. Member parts were already decoded; only the container side was re-encoded a second time.

## Classification
correctness defect found by code inspection (no live incident observed): container names containing percent-escapes double-encode (%20 -> %2520) and the libarchive entry URL names a container that does not exist; playback falls back to the redirect URL the route exists to avoid.

## Not run
- archive.org network access NOT_RUN (pure URL mapping only)
- mpv / libarchive playback NOT_RUN
- AppKit / UI NOT_RUN

## Reproduce
```
cd W-gdb-199j-1nstinct-41
SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py                  # pinned (source/): expect RED
GOR_SOURCE_ROOT=$PWD/fixed SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py   # fixed: expect GREEN
SWIFTFLAGS=-O SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py                # pinned -O
SWIFTFLAGS=-O GOR_SOURCE_ROOT=$PWD/fixed SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py  # fixed -O
```

## packet-json
```json
{
  "packet_id": "W-gdb-199j-1nstinct-41",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "archive/gor/Sources/gor/GorUI/MenuActions.swift",
  "touched_files": [
    "archive/gor/Sources/gor/GorUI/MenuActions.swift"
  ],
  "interface": {
    "signatures": [
      "static func nativeArchiveEntryURL(_ value: String) -> String?"
    ],
    "ownership_lifetime": "value-type String in/out; no retained state",
    "caller": "MenuActions.swift:1363 archive load route",
    "callee": "Foundation URLComponents / addingPercentEncoding"
  },
  "test": {
    "command": "SWIFTC=$SWIFTC python3 run_packet.py (GOR_SOURCE_ROOT selects source/ vs fixed/; SWIFTFLAGS=-O for optimized runs)",
    "fixture_block": "fixtures1.json",
    "config_block": "fixtures2.json",
    "expected": "pinned RED exit=1 (double-encoded container), fixed GREEN exit=0"
  },
  "target": {
    "branch": "host",
    "paths": [
      "archive/gor/Sources/gor/GorUI/MenuActions.swift"
    ],
    "return_form": "unified diff + fixed full copy"
  },
  "run_proof": {
    "version": 1,
    "kind": "swiftc two-variant compile+run",
    "inline_files": [
      "run_packet.py",
      "fixtures1.json",
      "fixtures2.json"
    ],
    "log_block": "actual_run_log.txt",
    "verification": {
      "red_Onone": {
        "compile_exit": 0,
        "semantic_exit": 1,
        "pass": true
      },
      "red_O": {
        "compile_exit": 0,
        "semantic_exit": 1,
        "pass": true
      },
      "green_Onone": {
        "compile_exit": 0,
        "semantic_exit": 0,
        "pass": true
      },
      "green_O": {
        "compile_exit": 0,
        "semantic_exit": 0,
        "pass": true
      }
    }
  },
  "state": "VERIFIED",
  "classification": "correctness defect found by code inspection (no live incident observed): container names containing percent-escapes double-encode (%20 -> %2520) and the libarchive entry URL names a container that does not exist; playback falls back to the redirect URL the route exists to avoid."
}
```

## extracted swift (fixed)
```swift
enum A41Host {
    static func nativeArchiveEntryURL(_ value: String) -> String? {
        guard let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              parts.host?.lowercased() == "archive.org", parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        let segments = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.count >= 5, segments[0].isEmpty, segments[1] == "download", !segments[2].isEmpty else { return nil }
        var containerIndex: Int?
        for i in 3..<segments.count {
            let name = segments[i].removingPercentEncoding?.lowercased() ?? ""
            if name.hasSuffix(".zip") || name.hasSuffix(".rar") { containerIndex = i; break }
        }
        guard let idx = containerIndex, idx + 1 < segments.count else { return nil }
        let memberParts = segments[(idx + 1)...].map { $0.removingPercentEncoding ?? "" }
        guard memberParts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("|") && !$0.contains("\\")
                  && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) }) else { return nil }
        // %2F inside one segment decodes to "/": re-check every resulting component.
        guard memberParts.joined(separator: "/").split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        let container = "https://archive.org" + segments[0...idx].map { $0.removingPercentEncoding ?? $0 }.joined(separator: "/")
        var keep = CharacterSet.alphanumerics; keep.insert(charactersIn: ":/._-~")
        guard let escaped = container.addingPercentEncoding(withAllowedCharacters: keep) else { return nil }
        return "archive://" + escaped + "|/" + memberParts.joined(separator: "/")
    }
}


let expected = "archive://https://archive.org/download/id/my%20item.zip|/member file.mp4"
let got = A41Host.nativeArchiveEntryURL("https://archive.org/download/id/my%20item.zip/member%20file.mp4")
if got != expected { print("MISMATCH expected=\(expected) got=\(String(describing: got))"); exit(1) }
if A41Host.nativeArchiveEntryURL("https://example.com/download/id/a.zip/b.mp4") != nil { print("FAIL non-archive host accepted"); exit(1) }
if A41Host.nativeArchiveEntryURL("https://archive.org/download/id/a.zip/../evil.mp4") != nil { print("FAIL traversal accepted"); exit(1) }
print("OK")
exit(0)

```

## fix diff
```diff
--- /tmp/packets_199j/W-gdb-199j-1nstinct-41/source/archive/gor/Sources/gor/GorUI/MenuActions.swift	2026-11-18 05:13:45.684823618 +0300
+++ /tmp/packets_199j/W-gdb-199j-1nstinct-41/fixed/archive/gor/Sources/gor/GorUI/MenuActions.swift	2026-11-18 05:13:45.684823618 +0300
@@ -1394,7 +1394,7 @@
         // %2F inside one segment decodes to "/": re-check every resulting component.
         guard memberParts.joined(separator: "/").split(separator: "/", omittingEmptySubsequences: false)
                 .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
-        let container = "https://archive.org" + segments[0...idx].joined(separator: "/")
+        let container = "https://archive.org" + segments[0...idx].map { $0.removingPercentEncoding ?? $0 }.joined(separator: "/")
         var keep = CharacterSet.alphanumerics; keep.insert(charactersIn: ":/._-~")
         guard let escaped = container.addingPercentEncoding(withAllowedCharacters: keep) else { return nil }
         return "archive://" + escaped + "|/" + memberParts.joined(separator: "/")

```

## runner
```python
(run_packet.py, sha256 27896b88d2625b2e5f678326b4ab92021764cb8a7c5a95754025bd01b591a9e3)
```

## fixtures
```json
fixtures1.json sha256 0ffb35fd46034559a134af5f086d6d7604ed82c51b46a126953395dbd5694fb1
fixtures2.json sha256 f146bdcb5f25605715adf59f13ccbc8b81f034ec69d1946ffc4dad7b5a16030a
```

## run log
```text
== source -Onone ==
compile_exit=0
MISMATCH expected=archive://https://archive.org/download/id/my%20item.zip|/member file.mp4 got=Optional("archive://https://archive.org/download/id/my%2520item.zip|/member file.mp4")
semantic_exit=1

== source -O ==
compile_exit=0
MISMATCH expected=archive://https://archive.org/download/id/my%20item.zip|/member file.mp4 got=Optional("archive://https://archive.org/download/id/my%2520item.zip|/member file.mp4")
semantic_exit=1

== fixed -Onone ==
compile_exit=0
OK
semantic_exit=0

== fixed -O ==
compile_exit=0
OK
semantic_exit=0
```

Publication: NONQUALIFIED, four of ten refill. Baseline copy removes attribution comments only, production statement equality checked against exact b603. Runner also placed under own canonical test path with source-root discovery adjusted only; fresh independent replay pending. Runner process exit0 does NOT prove semanticGREEN: inspect compile_exit AND semantic_exit lines. Defensive hardening/no live incident; native/fullhost NOT_RUN. Earliest verified claim with2h without-progress lease.
