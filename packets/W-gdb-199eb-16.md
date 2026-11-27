# W-gdb-199eb-16: lane-e-binding
Team: 1nstinct. State: WAIT_STATION_REPIN. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-16, lane lane/1nstinct/lane-e-binding; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Player/ExportRunComposition.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: c261a9392e5f9a5cadb863902cc3a1d06124c68e
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Integrate real Lane E skeleton and bind source/runner to the same retained lease.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Existing export target is being consolidated by the single station writer. Wait for its verified destination@SHA, then repin this same packet. No parallel satellite edit.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
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

Secret scan: clean.
