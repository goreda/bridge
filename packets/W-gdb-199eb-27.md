# W-gdb-199eb-27: arch-outbox-admission
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/arch-outbox-admission.
Source: archive/gor/Sources/gor/Engine/MPVCommand.swift, lines 490-517.

## Product change
Ensure a true admission result names a live-scope queued line and false invokes immediate fallback.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Disconnected/full/generation-purge interleavings cannot manufacture a valid ACK expectation.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
