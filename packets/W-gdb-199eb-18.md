# W-gdb-199eb-18: lane-e-construction
Team: 1nstinct. State: WAIT_STATION_REPIN. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-18, lane lane/1nstinct/lane-e-construction; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Picture/ExportRunConstruction.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 878aad20e06222e4649d04c6ae7f938d9b736885
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Apply 68db5274 and 3c8a65bc contracts after verifying these objects and current interfaces.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Existing export target is being consolidated by the single station writer. Wait for its verified destination@SHA, then repin this same packet. No parallel satellite edit.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
4: // Engine: gorav
5: import Foundation
6: 
7: /// Why no runner was built. Every case means nothing was created, admitted or written. There is no default feed and no default backend.
8: public enum ExportRunUnavailable: Error, Equatable, CustomStringConvertible {
9:     case noPlan                              // the preflight gave no job, or no typed capture to bind it to
10:     case noEncodeBackend                     // no backend was supplied (the linked provider is not connected)
11:     case backendUnavailable(String)          // a backend exists and says it cannot run; its own reason
12:     case noFrameFeed                         // no producer: never a made-up feed
13:     case startFence(ExportRefusal)           // the playing source is not proven to be the planned file
14:     case feedRunMismatch                     // the feed names no run, or a different producer run than the capture the plan is bound to
15:     case feedSourceMismatch                  // the feed was opened on a different file than the one planned
16:     case recheck(ExportRefusal)              // disk, source or output names changed since the plan preview
17:     case captureNotBound(String)             // the capture does not prove the job: other path, raster or look, unverified producer run, or a receipt for another load
18:     case heldRoute(String)                   // container, copied-stream or colour/pixel format outside the qualified technical set (ExportOpenGuard)
19:     case muxPlan(String)                     // the job's stream layout has no mux expectation (for example more than one video stream)
20: 
21:     public var description: String {
22:         switch self {
23:         case .noPlan: return "no export plan to run"
24:         case .noEncodeBackend: return "no encoder backend is connected"
25:         case .backendUnavailable(let r): return "encoder backend unavailable: \(r)"
26:         case .noFrameFeed: return "no frame producer is connected"
27:         case .startFence(let r): return "start refused: \(r)"
28:         case .feedRunMismatch: return "the frame producer does not deliver under the run the capture is bound to"
29:         case .feedSourceMismatch: return "the frame producer was opened on a different source file than the plan"
30:         case .recheck(let r): return "start refused after recheck: \(r)"
31:         case .captureNotBound(let m): return "capture does not match the planned job: \(m)"
```

Secret scan: clean.
