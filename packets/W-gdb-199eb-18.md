# W-gdb-199eb-18: lane-e-construction
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/lane-e-construction.
Source: archive/gor/Sources/gor/Picture/ExportRunConstruction.swift, lines 4-31.

## Product change
Apply 68db5274 and 3c8a65bc contracts after verifying these objects and current interfaces.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Source-bound construction test must fail before applied behavior and retain original run owner identity.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
