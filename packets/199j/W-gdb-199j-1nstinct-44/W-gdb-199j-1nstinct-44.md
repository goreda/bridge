# W-gdb-199j-1nstinct-44 - MusicController.send passes embedded newlines into the mus2 line protocol

state: VERIFIED
lab: 1nstinct | product: goreda/instinct @ b60352dabc87fe8519832999b4af639f37d786f8 | scope: `archive/gor/Sources/gor/GorUI/MusicController.swift`

## Goal
One command string must always become exactly one protocol line; CR/LF inside a search query, playlist name, path or URL must never split into extra commands.

## Caller scope
CALLER SCOPE: every command builder routes through send, e.g. search at MusicController.swift:201 (called from MusicPanel.swift:698), play_local at MusicController.swift:236 (prev/next local track URLs), pl_new at MusicController.swift:263 (user-typed playlist names). Shipping callers in the same file and MusicPanel.swift.

## Extraction
Extracted func send and func sendRaw verbatim as free functions; the two referenced instance members (isRunning, stdinPipe) are supplied by the driver as top-level bindings backed by a real Pipe, so the bytes written can be read back. Compiled standalone.
Comment lines carrying attribution or provenance identifiers elided from the packet source copy: 2 (trigger lines plus their continuation lines; string-aware, code untouched); sha256 below covers the elided copy.

## Verification (Swift 6.0.3, Linux)

- red_Onone: compile_exit=0 semantic_exit=1 -> PASS
- red_O: compile_exit=0 semantic_exit=1 -> PASS
- green_Onone: compile_exit=0 semantic_exit=0 -> PASS
- green_O: compile_exit=0 semantic_exit=0 -> PASS

Expected: pinned RED exit=1 (4 lines from 2 commands), fixed GREEN exit=0.

## Fix
Replace CR and LF with spaces at the single choke point (send), so all ~20 command builders are covered. Previously a newline inside a search query, playlist name or local file path produced additional protocol lines that mus2.py executed as commands.

## Classification
defensive malformed-input hardening (no live incident observed): inputs are the user's own search text, playlist names and file paths, all of which can carry newlines via paste or unusual file names.

## Not run
- mus2.py subprocess NOT_RUN (pipe bytes asserted at the Swift boundary)
- AppKit / UI NOT_RUN

## Reproduce
```
cd W-gdb-199j-1nstinct-44
SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py                  # pinned (source/): expect RED
GOR_SOURCE_ROOT=$PWD/fixed SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py   # fixed: expect GREEN
SWIFTFLAGS=-O SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py                # pinned -O
SWIFTFLAGS=-O GOR_SOURCE_ROOT=$PWD/fixed SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py  # fixed -O
```

## packet-json
```json
{
  "packet_id": "W-gdb-199j-1nstinct-44",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "archive/gor/Sources/gor/GorUI/MusicController.swift",
  "touched_files": [
    "archive/gor/Sources/gor/GorUI/MusicController.swift"
  ],
  "interface": {
    "signatures": [
      "func send(_ command: String)",
      "func sendRaw(_ cmd: String)"
    ],
    "ownership_lifetime": "writes into the long-lived stdinPipe; no retained state",
    "caller": "MusicController.swift:201/:236/:263, MusicPanel.swift:698",
    "callee": "Pipe/FileHandle (mus2.py stdin)"
  },
  "test": {
    "command": "SWIFTC=$SWIFTC python3 run_packet.py (GOR_SOURCE_ROOT selects source/ vs fixed/; SWIFTFLAGS=-O for optimized runs)",
    "fixture_block": "fixtures1.json",
    "config_block": "fixtures2.json",
    "expected": "pinned RED exit=1 (4 lines from 2 commands), fixed GREEN exit=0"
  },
  "target": {
    "branch": "host",
    "paths": [
      "archive/gor/Sources/gor/GorUI/MusicController.swift"
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
  "classification": "defensive malformed-input hardening (no live incident observed): inputs are the user's own search text, playlist names and file paths, all of which can carry newlines via paste or unusual file names."
}
```

## extracted swift (fixed)
```swift
var isRunning = true
var stdinPipe: Pipe? = Pipe()
    func send(_ command: String) {
        let line = command.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        guard isRunning, let data = (line + "\n").data(using: .utf8) else { return }
        stdinPipe?.fileHandleForWriting.write(data)
    }
    func sendRaw(_ cmd: String) { send(cmd) }

send("search hello\nplay 5")
send("pl_new my\r\nlist")
let data = stdinPipe!.fileHandleForReading.availableData
let text = String(data: data, encoding: .utf8) ?? ""
let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
if lines.count != 2 { print("RED: \(lines.count) command lines written: \(text.debugDescription)"); exit(1) }
if lines[0] != "search hello play 5" || lines[1] != "pl_new my  list" { print("FAIL content: \(text.debugDescription)"); exit(1) }
sendRaw("quit")
let d2 = stdinPipe!.fileHandleForReading.availableData
if String(data: d2, encoding: .utf8) != "quit\n" { print("FAIL sendRaw passthrough"); exit(1) }
print("OK")
exit(0)

```

## fix diff
```diff
--- /tmp/packets_199j/W-gdb-199j-1nstinct-44/source/archive/gor/Sources/gor/GorUI/MusicController.swift	2026-11-18 05:24:32.515598778 +0300
+++ /tmp/packets_199j/W-gdb-199j-1nstinct-44/fixed/archive/gor/Sources/gor/GorUI/MusicController.swift	2026-11-18 05:24:32.515598778 +0300
@@ -305,7 +305,8 @@
     // MARK: - Private
 
     func send(_ command: String) {
-        guard isRunning, let data = (command + "\n").data(using: .utf8) else { return }
+        let line = command.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
+        guard isRunning, let data = (line + "\n").data(using: .utf8) else { return }
         stdinPipe?.fileHandleForWriting.write(data)
     }
 

```

## runner
```python
(run_packet.py, sha256 ca9e42e2244572f93ab2441b2c0dadaf1f667158aeee8f8cc07a002601c08620)
```

## fixtures
```json
fixtures1.json sha256 c7cd40e62ec72c6ce364f030429764a90f7b394a927ce71f6a0b4218c9401df4
fixtures2.json sha256 97ec54d2c73b0aff8496761e1e596e8d73ab7c21b0ed6308fad9fe03cb9913f0
```

## run log
```text
== source -Onone ==
compile_exit=0
RED: 3 command lines written: "search hello\nplay 5\npl_new my\r\nlist\n"
semantic_exit=1

== source -O ==
compile_exit=0
RED: 3 command lines written: "search hello\nplay 5\npl_new my\r\nlist\n"
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

Privacy revision 0526: whole comment runs removed. Non-comment statements string-aware compared equal to previously independently replayed adapted versions. Previous Linux proof binds OLD source hashes; new writer re-verification is separately attributed, Ops did not rerun Swift binaries for this comment-only revision. NONQUALIFIED; all prior boundary failures and native/full-host exclusions remain. Canonical runner discovery adaptation remains not executed.
