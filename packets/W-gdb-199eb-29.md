# W-gdb-199eb-29: arch-source-cancel
Team: in2tinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-29, lane lane/in2tinct/arch-source-cancel; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Engine/CropProbeTransport.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 910471b301b2542ed3f9704a5d748f4a9d3bdfd9
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Keep read cancellation within its source/scan owner and isolate subprocess failure from UI queues.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
29: final class CropProbeTransport {
30:     private let capability: CropProbeCapability
31:     init(capability: CropProbeCapability) { self.capability = capability }
32:     /// Loaded-file duration in seconds; nil until the file reports one.
33:     func fileDuration(timeout: TimeInterval = 0.8) -> Double? { capability.fileDuration(timeout) }
34:     /// Seek-in-progress flag; nil while the reply carries no bool.
35:     func isSeeking(timeout: TimeInterval = 0.15) -> Bool? { capability.isSeeking(timeout) }
36:     /// Pause flag; nil while the reply carries no bool.
37:     func isPaused() -> Bool? { capability.isPaused() }
38:     /// Currently loaded path; nil while the reply carries no string.
39:     func currentPath() -> String? { capability.currentPath() }
40:     /// Playhead position in seconds; nil while the reply carries no number.
41:     func timePosition() -> Double? { capability.timePosition() }
42:     /// Screenshot format mpv is configured to write; "png" when unread.
43:     func screenshotFormat() -> String { capability.screenshotFormat() }
44:     /// Absolute seek; the caller's poll loop confirms completion.
45:     func seekAbsolute(seconds: Int) { capability.seekAbsolute(seconds) }
46:     /// Prepares the screenshot command without sending it; nil only when the
47:     /// backend refuses to build it. The prepared token is opaque here: this
48:     /// type can hold it and hand it back, never read or shape it. Callers
49:     /// that log before sending hold this, log, then sendPrepared.
50:     func screenshotCommand(to path: String) -> CropProbePreparedCommand? { capability.prepareScreenshot(path) }
51:     /// Hands a prepared command back to the backend and discards the reply:
52:     /// the screenshot file is the evidence of capture, not the socket result.
53:     func sendPrepared(_ command: CropProbePreparedCommand) { capability.sendPrepared(command) }
54:     /// Build + send in the old fire-and-forget order; the result is the
55:     /// build-and-hand-off signal the header describes, nothing more.
56:     @discardableResult
```

Secret scan: clean.
