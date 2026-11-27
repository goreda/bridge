# W-gdb-199eb-27: arch-outbox-admission
Team: in2tinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-27, lane lane/in2tinct/arch-outbox-admission; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Engine/MPVCommand.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 5f8ec03e39cc637ecd13afe89dce138db591b30a
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Ensure a true admission result names a live-scope queued line and false invokes immediate fallback.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
490:     var workQueue: DispatchQueue { get }
491:     func start()
492:     func stop()
493:     func dropExportRun(_ runId: String)
494:     func writeAdmitted(_ payload: String) -> Bool
495:     func noteExportLoad(session: String, opening: UInt64)
496:     func enqueueExportLine(_ payload: String, session: String, opening: UInt64, runId: String?, attempt: UInt64?) -> Bool
497: }
498: extension PersistentEventConnection: PlayerPersistentEventChannel {}
499: #endif
500: #if canImport(AppKit)
501: enum PlayerPreviewOperations {
502:     static func update(socket:String,geometry:String,seekPercent:Double?) {
503:         _=IPCClient.socketRoundtrip(path:socket,payload:PlayerFitProtocol.previewPayload(geometry:geometry,seekPercent:seekPercent),timeout:0.05,sendOnly:true)
504:     }
505: }
506: #endif
507: 
508: // Backend admission seam. Keep this Foundation-only so the exact selection and
509: // rollback path can be exercised without an AppKit or GorAV dependency.
510: enum PlayerEngine: String, CaseIterable {
511:     case mpv, gorav
512:     static let preferenceKey = "gor.player.engine"
513:     static func selected(environment: [String: String], saved: String?) -> PlayerEngine {
514:         if let override = environment["GOR_ENGINE"], let engine = PlayerEngine(rawValue: override) { return engine }
515:         return saved.flatMap(PlayerEngine.init(rawValue:)) ?? .mpv
516:     }
517: }
```

Secret scan: clean.
