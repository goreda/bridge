# W-gdb-199eb-33: pip-owner-lifetime
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/pip-owner-lifetime.
Source: archive/gor/Sources/gor/Player/PPController.swift, lines 27-54.

## Product change
Keep PiP control/close identity stable when focus changes between multiple players.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
27: // ================================================================
28: // I14: construction sites are AppDelegate's launchMPV checkTimer, handleWakeUp (and its recovery timer), and attachOverlay.
29: final class PPController: NSView {
30: 
31:     func pausePlayback() {playbackOperations.pause()}
32:     func enableLivePhoton() {playbackOperations.photonLive()}
33: 
34:     // MARK: - State
35:     static let shadowRadius:  CGFloat = 2.2
36:     static let shadowOpacity: Float   = 0.5
37:     static var globalShadow: NSShadow {
38:         let s = NSShadow()
39:         s.shadowColor      = NSColor.black.withAlphaComponent(0.5)
40:         s.shadowBlurRadius = PPController.shadowRadius
41:         s.shadowOffset     = .zero
42:         return s
43:     }
44: 
45:     // ── UI state ────────────────────────────────────────────────────────
46:     let spineUI      = SpineUI(frame: .zero)
47:     let sidebarUI    = SidebarUI(frame: .zero)
48:     let subtitleView = SubtitleView(frame: .zero)
49: 
50:     // ── IPC state ───────────────────────────────────────────────────────
51:     let ipcPath: String
52:     let ipcClient: IPCClient
53:     // Typed channel, not the concrete handle: the backend-owner factory extension in
54:     // Engine/MPVCommand.swift composes it; construction stays on the owner path at attach.
```

## Mandatory test
Open A/B, toggle A PiP then focus B and close A; no command to B and no orphan A.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
