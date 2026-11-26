# W-gdb-199eb-25: transfer-source-switch
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/transfer-source-switch.
Source: archive/gor/Sources/gor/Player/ExportRunComposition.swift, lines 43-70.

## Product change
Reject stale transfer evidence if a new file opens between preflight and Start.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
43:     /// - resetTiming: the wire timing legs for the reset line.
44:     /// - makeFeed: builds the frame feed AFTER the source exists, so its run context can read the
45:     ///   source's live run token; makeRGBA64 checks it against the prepared binding at construction
46:     ///   (the product ordering is prepare-first, construct-after).
47:     public static func bindRun(box: ExportRunLeaseBox, wire: ExportWireObserver, inner: PhotonExportPixelSource,
48:                                ownerQueue: DispatchQueue, capture: ExportLookCapture,
49:                                contract: PhotonExportReadbackContract, timeBase: ExportTimeBase,
50:                                enqueueLine: @escaping (_ line: String, _ session: String, _ opening: UInt64, _ runId: String?, _ attempt: UInt64?) -> Bool,
51:                                dropRun: @escaping (String) -> Void,
52:                                resetTiming: @escaping () -> (ptsUs: Int64, originUs: Int64),
53:                                frameChannel: ExportFrameWireChannel? = nil,
54:                                result: ExportPreflightResult, adapter: ExportSnapshotAdapter,
55:                                backend: ExportRGBA64Backend?, makeFeed: (ExportLeasePixelSource) -> ExportRGBA64FrameFeed?,
56:                                fileSystem: ExportFileSystem, admission: ExportAdmission,
57:                                requireVideoEndProof: Bool,
58:                                copyProof: ((ExportPartialFile) -> String?)?, copyProofInterrupt: (() -> Void)?) -> Result<BoundRun, Refusal> {
59:         let emitter = ExportWireEmitter(enqueue: { line in
60:             let owner = wire.currentOwner()
61:             return enqueueLine(line, owner?.session ?? "", owner?.opening ?? 0, capture.loadReceipt.runId, nil)
62:         })
63:         let source = ExportLeasePixelSource(box: box, wire: wire, inner: inner, ownerQueue: ownerQueue, capture: capture,
64:                                             queuedRunPurge: dropRun,
65:                                             frameChannel: frameChannel,
66:                                             emitReset: { epoch in
67:                                                 let t = resetTiming()
68:                                                 try emitter.reset(epoch: epoch, ptsUs: t.ptsUs, originUs: t.originUs)
69:                                             })
70:         let prepared: (producer: PhotonExportProducer, binding: ExportPreparedRun)
```

## Mandatory test
Interleave open/preflight/open/start with distinct tokens; never encode stale content.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
