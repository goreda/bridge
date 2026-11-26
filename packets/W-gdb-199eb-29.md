# W-gdb-199eb-29: arch-source-cancel
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/arch-source-cancel.
Source: archive/gor/Sources/gor/Engine/CropProbeTransport.swift, lines 29-56.

## Product change
Keep read cancellation within its source/scan owner and isolate subprocess failure from UI queues.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Old cancellation cannot abort a newer source; bounded timeout and child reaping verified.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
