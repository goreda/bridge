# W-gdb-199j-1nstinct-42 - blinkShouldRun ignores its vrEnabled parameter

state: VERIFIED
lab: 1nstinct | product: goreda/instinct @ b60352dabc87fe8519832999b4af639f37d786f8 | scope: `archive/gor/Sources/gor/gor/PPController_Features.swift`

## Goal
The blink camera leg must only acquire frames while blink logging is on in VR; the declared vrEnabled input must participate in the decision.

## Caller scope
CALLER SCOPE: updateCaptureConsumers, PPController_Features.swift:1249-1252 passes vrEnabled: vrModeEnabled. Shipping caller in the same file.

## Extraction
Extracted enum CaptureConsumerRules (headShouldRun + blinkShouldRun, pure Bool functions) from the pinned file; compiled standalone with the test driver.
Attribution comment lines elided from the packet source copy: 6; sha256 below covers the elided copy.

## Verification (Swift 6.0.3, Linux)

- red_Onone: compile_exit=0 semantic_exit=1 -> PASS
- red_O: compile_exit=0 semantic_exit=1 -> PASS
- green_Onone: compile_exit=0 semantic_exit=0 -> PASS
- green_O: compile_exit=0 semantic_exit=0 -> PASS

Expected: pinned RED exit=1 (vrEnabled ignored), fixed GREEN exit=0.

## Fix
Conjoin vrEnabled into the blink decision. The doc comment states the intent (frames whenever blink is on in VR) and the caller passes vrModeEnabled, but the parameter was dropped from the body, so the blink camera consumer started with VR off whenever blink logging and a loaded video coincided.

## Classification
correctness defect found by code inspection (no live incident observed): the ignored parameter starts the blink camera consumer outside VR.

## Not run
- camera hardware / frame delivery NOT_RUN
- AppKit / UI NOT_RUN

## Reproduce
```
cd W-gdb-199j-1nstinct-42
SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py                  # pinned (source/): expect RED
GOR_SOURCE_ROOT=$PWD/fixed SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py   # fixed: expect GREEN
SWIFTFLAGS=-O SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py                # pinned -O
SWIFTFLAGS=-O GOR_SOURCE_ROOT=$PWD/fixed SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py  # fixed -O
```

## packet-json
```json
{
  "packet_id": "W-gdb-199j-1nstinct-42",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "archive/gor/Sources/gor/gor/PPController_Features.swift",
  "touched_files": [
    "archive/gor/Sources/gor/gor/PPController_Features.swift"
  ],
  "interface": {
    "signatures": [
      "static func blinkShouldRun(blinkOn: Bool, vrEnabled: Bool, loadedVideoActive: Bool, cameraAllowed: Bool) -> Bool"
    ],
    "ownership_lifetime": "pure function; no state",
    "caller": "PPController_Features.swift:1249 updateCaptureConsumers",
    "callee": "none"
  },
  "test": {
    "command": "SWIFTC=$SWIFTC python3 run_packet.py (GOR_SOURCE_ROOT selects source/ vs fixed/; SWIFTFLAGS=-O for optimized runs)",
    "fixture_block": "fixtures1.json",
    "config_block": "fixtures2.json",
    "expected": "pinned RED exit=1 (vrEnabled ignored), fixed GREEN exit=0"
  },
  "target": {
    "branch": "host",
    "paths": [
      "archive/gor/Sources/gor/gor/PPController_Features.swift"
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
  "classification": "correctness defect found by code inspection (no live incident observed): the ignored parameter starts the blink camera consumer outside VR."
}
```

## extracted swift (fixed)
```swift
enum CaptureConsumerRules {
    /// Both consumers use loaded-video authority; paused video must still respond to head motion.
    static func headShouldRun(headTrackingEnabled: Bool, playbackActive: Bool) -> Bool {
        headTrackingEnabled && playbackActive
    }
    /// Blink leg: needs frames whenever blink is on in VR with a file loaded - pause must NOT
    /// stop it (loadedVideoActive, not playbackActive), or the pause toggle could never resume.
    static func blinkShouldRun(blinkOn: Bool, vrEnabled: Bool, loadedVideoActive: Bool, cameraAllowed: Bool) -> Bool {
        blinkOn && vrEnabled && loadedVideoActive && cameraAllowed
    }
}

if CaptureConsumerRules.blinkShouldRun(blinkOn: true, vrEnabled: false, loadedVideoActive: true, cameraAllowed: true) { print("RED: blink camera leg starts while VR is off"); exit(1) }
if !CaptureConsumerRules.blinkShouldRun(blinkOn: true, vrEnabled: true, loadedVideoActive: true, cameraAllowed: true) { print("FAIL: blink on in VR with loaded video must run"); exit(1) }
if CaptureConsumerRules.blinkShouldRun(blinkOn: false, vrEnabled: true, loadedVideoActive: true, cameraAllowed: true) { print("FAIL: blink off must not run"); exit(1) }
if CaptureConsumerRules.blinkShouldRun(blinkOn: true, vrEnabled: true, loadedVideoActive: false, cameraAllowed: true) { print("FAIL: no loaded video must not run"); exit(1) }
if !CaptureConsumerRules.headShouldRun(headTrackingEnabled: true, playbackActive: true) { print("FAIL head leg"); exit(1) }
print("OK")
exit(0)

```

## fix diff
```diff
--- /tmp/packets_199j/W-gdb-199j-1nstinct-42/source/archive/gor/Sources/gor/gor/PPController_Features.swift	2026-11-18 05:13:47.824838680 +0300
+++ /tmp/packets_199j/W-gdb-199j-1nstinct-42/fixed/archive/gor/Sources/gor/gor/PPController_Features.swift	2026-11-18 05:13:47.824838680 +0300
@@ -543,7 +543,7 @@
     /// Blink leg: needs frames whenever blink is on in VR with a file loaded - pause must NOT
     /// stop it (loadedVideoActive, not playbackActive), or the pause toggle could never resume.
     static func blinkShouldRun(blinkOn: Bool, vrEnabled: Bool, loadedVideoActive: Bool, cameraAllowed: Bool) -> Bool {
-        blinkOn && loadedVideoActive && cameraAllowed
+        blinkOn && vrEnabled && loadedVideoActive && cameraAllowed
     }
 }
 

```

## runner
```python
(run_packet.py, sha256 9b3cc46779c6770cc30ebde955c8b7c9e7990b5fadafe22c6cd590657caaa544)
```

## fixtures
```json
fixtures1.json sha256 adfbb06181ec0fbbeaead3dc8aeb5539ac83a5825cdc605ad4e5f79f3c07b391
fixtures2.json sha256 ccba99f8c6c2ab6aea45154a5bf030775b6cbda64fe2172aca75a6651d614c1a
```

## run log
```text
== source -Onone ==
compile_exit=0
RED: blink camera leg starts while VR is off
semantic_exit=1

== source -O ==
compile_exit=0
RED: blink camera leg starts while VR is off
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
