# W-gdb-199eb-17: lane-e-lifecycle
Team: 1nstinct. State: WAIT_STATION_REPIN. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-17, lane lane/1nstinct/lane-e-lifecycle; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Player/ExportRunLease.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 723eef00041a1fdd6f402561a65755467e840d65
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Finish and cancel every export lease exactly once, preserving the active run until its writes settle.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Existing export target is being consolidated by the single station writer. Wait for its verified destination@SHA, then repin this same packet. No parallel satellite edit.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
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

Secret scan: clean.
