# W-gdb-199j-1nstinct-43 - readQuitToken traps on out-of-range pid or negative epoch from its JSON file

state: VERIFIED
lab: 1nstinct | product: goreda/instinct @ b60352dabc87fe8519832999b4af639f37d786f8 | scope: `archive/gor/Sources/gor/AppDelegate.swift`

## Goal
A quit-token file whose pid exceeds pid_t or whose epoch is negative must decode to nil, not crash the launching instance.

## Caller scope
CALLER SCOPE: duplicate-instance arbitration at launch, AppDelegate.swift:416 (`Self.restartWaitBudget(token: Self.readQuitToken(), ...)`). Shipping caller in the same file. quitTokenURL is a static let on the same type (AppDelegate.swift:3239-3240); the driver supplies a frozen equivalent pointing at a temp file.

## Extraction
Extracted struct QuitToken and static func readQuitToken verbatim from the pinned file; the static-let quitTokenURL (a brace-less declaration the extractor cannot lift) is supplied by the driver as a top-level frozen path. Compiled standalone.
Comment lines carrying attribution or provenance identifiers elided from the packet source copy: 68 (trigger lines plus their continuation lines; string-aware, code untouched); sha256 below covers the elided copy.

## Verification (Swift 6.0.3, Linux)

- red_Onone: compile_exit=0 semantic_exit=-4 -> PASS
- red_O: compile_exit=0 semantic_exit=-4 -> PASS
- green_Onone: compile_exit=0 semantic_exit=0 -> PASS
- green_O: compile_exit=0 semantic_exit=0 -> PASS

Expected: pinned RED trap semantic_exit=-4, fixed GREEN exit=0.

## Fix
Guard the JSON ints before the narrowing conversions: pid must be in 1...pid_t.max and epoch must be non-negative, otherwise the token is treated as absent (nil). Previously pid_t(2^40) or UInt64(-1) trapped.

## Classification
defensive malformed-input hardening (no live incident observed): the quit-token file is written by the app itself, but a corrupted or hand-edited file crashes the next launch instead of falling back to the default arbitration.

## Not run
- real app relaunch / duplicate-instance arbitration NOT_RUN
- AppKit / UI NOT_RUN

## Reproduce
```
cd W-gdb-199j-1nstinct-43
SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py                  # pinned (source/): expect RED
GOR_SOURCE_ROOT=$PWD/fixed SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py   # fixed: expect GREEN
SWIFTFLAGS=-O SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py                # pinned -O
SWIFTFLAGS=-O GOR_SOURCE_ROOT=$PWD/fixed SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py  # fixed -O
```

## packet-json
```json
{
  "packet_id": "W-gdb-199j-1nstinct-43",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "archive/gor/Sources/gor/AppDelegate.swift",
  "touched_files": [
    "archive/gor/Sources/gor/AppDelegate.swift"
  ],
  "interface": {
    "signatures": [
      "static func readQuitToken() -> QuitToken?"
    ],
    "ownership_lifetime": "value-type QuitToken; file read per call",
    "caller": "AppDelegate.swift:416 launch arbitration",
    "callee": "Foundation JSONSerialization / Data(contentsOf:)"
  },
  "test": {
    "command": "SWIFTC=$SWIFTC python3 run_packet.py (GOR_SOURCE_ROOT selects source/ vs fixed/; SWIFTFLAGS=-O for optimized runs)",
    "fixture_block": "fixtures1.json",
    "config_block": "fixtures2.json",
    "expected": "pinned RED trap semantic_exit=-4, fixed GREEN exit=0"
  },
  "target": {
    "branch": "host",
    "paths": [
      "archive/gor/Sources/gor/AppDelegate.swift"
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
        "semantic_exit": -4,
        "pass": true
      },
      "red_O": {
        "compile_exit": 0,
        "semantic_exit": -4,
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
  "classification": "defensive malformed-input hardening (no live incident observed): the quit-token file is written by the app itself, but a corrupted or hand-edited file crashes the next launch instead of falling back to the default arbitration."
}
```

## extracted swift (fixed)
```swift
let quitTokenURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gor-quit-token-test.json")
enum A43Host {
    struct QuitToken: Equatable {
        let pid: pid_t
        let epoch: UInt64
        let wall: TimeInterval
    }
    static func readQuitToken() -> QuitToken? {
        guard let data = try? Data(contentsOf: quitTokenURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = obj["pid"] as? Int,
              let epoch = (obj["epoch"] as? Int) ?? (obj["epoch"] as? NSNumber)?.intValue,
              let wall = (obj["wall"] as? Double) ?? (obj["wall"] as? NSNumber)?.doubleValue else { return nil }
        guard pid > 0, pid <= Int(pid_t.max), epoch >= 0 else { return nil }
        return QuitToken(pid: pid_t(pid), epoch: UInt64(epoch), wall: wall)
    }
}


func writeToken(_ s: String) { try! s.write(to: quitTokenURL, atomically: true, encoding: .utf8) }
writeToken("{\"pid\": 4301, \"epoch\": 7, \"wall\": 123.5}")
guard let t = A43Host.readQuitToken(), t.pid == 4301, t.epoch == 7, t.wall == 123.5 else { print("FAIL valid round-trip"); exit(1) }
writeToken("{\"pid\": 1099511627776, \"epoch\": 7, \"wall\": 123.5}")
if A43Host.readQuitToken() != nil { print("FAIL hostile pid accepted"); exit(1) }
writeToken("{\"pid\": 4301, \"epoch\": -1, \"wall\": 123.5}")
if A43Host.readQuitToken() != nil { print("FAIL negative epoch accepted"); exit(1) }
print("OK")
exit(0)

```

## fix diff
```diff
--- /tmp/packets_199j/W-gdb-199j-1nstinct-43/source/archive/gor/Sources/gor/AppDelegate.swift	2026-11-18 05:24:30.691585692 +0300
+++ /tmp/packets_199j/W-gdb-199j-1nstinct-43/fixed/archive/gor/Sources/gor/AppDelegate.swift	2026-11-18 05:24:30.691585692 +0300
@@ -3251,6 +3251,7 @@
               let pid = obj["pid"] as? Int,
               let epoch = (obj["epoch"] as? Int) ?? (obj["epoch"] as? NSNumber)?.intValue,
               let wall = (obj["wall"] as? Double) ?? (obj["wall"] as? NSNumber)?.doubleValue else { return nil }
+        guard pid > 0, pid <= Int(pid_t.max), epoch >= 0 else { return nil }
         return QuitToken(pid: pid_t(pid), epoch: UInt64(epoch), wall: wall)
     }
     static func consumeQuitToken() { try? FileManager.default.removeItem(at: quitTokenURL) }

```

## runner
```python
(run_packet.py, sha256 4da02c1fe58f18ee2449ad0e0ff8c93d54b8875ef5bf2ce22513558301420d07)
```

## fixtures
```json
fixtures1.json sha256 65c51074c930376e3da534d3d60ebceff9a7667edfcebefcdab5b6c3d28c558f
fixtures2.json sha256 a54351f5640cb3a80b23e578c29bf26d840109224c01736fadefbebec059ee53
```

## run log
```text
== source -Onone ==
compile_exit=0
semantic_exit=-4

== source -O ==
compile_exit=0
semantic_exit=-4

== fixed -Onone ==
compile_exit=0
OK
semantic_exit=0

== fixed -O ==
compile_exit=0
OK
semantic_exit=0
```

Privacy revision 0526: whole comment runs removed. Non-comment statements string-aware compared equal to previously independently replayed adapted versions. Previous Linux proof binds OLD source hashes; new writer re-verification is separately attributed, Ops did not rerun Swift binaries for this comment-only revision. NONQUALIFIED; all prior boundary failures and native/full-host exclusions remain. Canonical runner discovery adaptation remains not executed.
