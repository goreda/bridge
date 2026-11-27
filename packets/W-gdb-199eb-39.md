# W-gdb-199eb-39: crop-size-evidence
Team: in2tinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-39, lane lane/in2tinct/crop-size-evidence; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Session/CropFitEvidenceEncoder.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: b19c7a34a487521fa858a87380b264088c5bbdf6
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Include source size/detected crop/fit target/refusal per player without unbounded logging.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
6: 
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
```

Secret scan: clean.
