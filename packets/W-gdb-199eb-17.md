# W-gdb-199eb-17: lane-e-lifecycle
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/lane-e-lifecycle.
Source: archive/gor/Sources/gor/Player/ExportRunLease.swift, lines 5-32.

## Product change
Finish and cancel every export lease exactly once, preserving the active run until its writes settle.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
5: import Foundation
6: 
7: /// A separately OPENED path observation (our own open+fstat of the path after the player loaded it). It is NOT the descriptor mpv holds and is never
8: /// documented as such: a replace between mpv's open and ours is not excluded. The identity the run is bound to is the accepted (session, opening, path).
9: public struct ExportPathObservation: Equatable {
10:     public var identity: ExportFileIdentity
11:     public init(identity: ExportFileIdentity) { self.identity = identity }
12: }
13: 
14: /// What the player has open and which producer run it was last observed under. An OBSERVATION snapshot, not a commit-owning lease.
15: /// - pathObservation: nil = unknown (kept open, never filled from a stat of a name).
16: /// - exportEpoch: the highest valid export epoch observed for this load and run; nil = none observed, never 0.
17: public struct PlayerCaptureSnapshot: Equatable {
18:     public var path: String
19:     public var generation: Int
20:     public var pathObservation: ExportPathObservation?
21:     public var accepted: ExportAcceptedIdentity
22:     public var runId: String?
23:     public var exportEpoch: Int64?
24:     public var lookPinSha256: String?
25:     public init(path: String, generation: Int, pathObservation: ExportPathObservation?, accepted: ExportAcceptedIdentity, runId: String?, exportEpoch: Int64?, lookPinSha256: String?) {
26:         self.path = path; self.generation = generation; self.pathObservation = pathObservation
27:         self.accepted = accepted; self.runId = runId; self.exportEpoch = exportEpoch; self.lookPinSha256 = lookPinSha256
28:     }
29:     /// The preflight/observation context. nil when run id or look pin is missing or invalid. The epoch may be nil and is carried as-is.
30:     public var runContext: ExportProducerRunContext? {
31:         guard let r = runId, ExportRunValidation.validRunId(r), let pin = lookPinSha256, ExportRunValidation.validPin(pin) else { return nil }
32:         if let e = exportEpoch, !ExportRunValidation.validEpoch(e) { return nil }
```

## Mandatory test
Cancel/EOF/error at every stage and assert one terminal and no retained frame callback.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
