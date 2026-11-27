# W-gdb-199eb-33: pip-owner-lifetime
Team: in2tinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-33, lane lane/in2tinct/pip-owner-lifetime; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Player/PPController.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: f060b9205a034ed43cc0cd632a16c57761358473
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Keep PiP control/close identity stable when focus changes between multiple players.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
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

Secret scan: clean.
