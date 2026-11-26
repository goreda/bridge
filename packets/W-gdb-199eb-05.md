# W-gdb-199eb-05: crop-landing
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/crop-landing.
Source: archive/gor/Sources/gor/Session/CropFitEvidenceEncoder.swift, lines 7-34.

## Product change
Distinguish command acceptance from actual window landing in bounded evidence.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
7: /// Pure event encoder. Owner injects UTC/monotonic clocks and sends the returned
8: /// data to its existing bounded per-player DiagSessionSink, never a new file.
9: /// One instance per player/load. This object deliberately does no I/O.
10: struct CropFitEvidenceEncoder {
11:     enum Stage: String {
12:         case requested, readRequested, readCompleted, consensus, fitGated
13:         case fitTarget, dispatched, commandACK, landing
14:     }
15:     struct Identity {
16:         let player: String, window: Int, load: UInt64, scan: UInt64
17:     }
18:     struct Event {
19:         let stage: Stage
20:         let utcMilliseconds: Int64, monotonicSeconds: Double
21:         /// Fixed numeric schema only. No source URLs, names, command bodies or stderr.
22:         var numbers: [String: Double] = [:]
23:         var reason: String = "none"
24:     }
25:     private static let allowedNumbers: Set<String> = [
26:         "request_bytes", "actual_bytes", "deadline_s", "elapsed_s", "samples",
27:         "supporters", "x", "y", "w", "h", "source_aspect", "target_aspect",
28:         "observed_aspect", "tolerance", "ack", "gate", "observed", "matched",
29:         "target_x", "target_y", "target_w", "target_h", "observed_x", "observed_y", "observed_w", "observed_h"
30:     ]
31:     private(set) var emitted = 0
32:     private(set) var bytes = 0
33:     static let maxRows = 2048
34:     static let maxBytes = 1048576
```

## Mandatory test
ACK-only cannot satisfy landing; observed frame/aspect matches can; enforce row/byte caps.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
