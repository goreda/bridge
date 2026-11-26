# W-gdb-199eb-08: crop-fit-source-first
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/crop-fit-source-first.
Source: archive/gor/Sources/gor/Player/PPController.swift, lines 1098-1125.

## Product change
Preserve source crop first, then final window fit on layout-ready or bounded deadline.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
1098:         guard openingFitArmedOpen != nil, !currentFilePath.isEmpty,
1099:               videoW > 0, videoH > 0 else { return }
1100:         openingFitArmedOpen = nil
1101:         defer {
1102:             if let aspect=deferredWindowRefitAspect {refitWindowForCrop(aspect:aspect)}
1103:             reconcileCropPropertyWindow()
1104:         }
1105:         // gor-fit.lua already sized this window before the first frame (baseline opens only). A second geometry
1106:         // here would be the visible resize after show. Music-exit restores (non-baseline fraction) keep the old path.
1107:         if Self.gorFitScriptActive && openingFitPendingFraction == GorVideoFit.openBaselineFraction { return }
1108:         // D7 (corrected in v6): mpv's OWN fullscreen state, IPC-observed on
1109:         // AppDelegate. The overlay window is borderless
1110:         // (DraggableOverlayWindow, .fullScreenAuxiliary) and can NEVER carry
1111:         // .fullScreen - reading window?.styleMask here made the guard a
1112:         // compile-time no-op in v3-v5.
1113:         guard (NSApp.delegate as? AppDelegate)?.playerFullscreenState != true,
1114:               let geom = GorOpeningFit.openingGeometry(
1115:                   videoW: videoW, videoH: videoH,
1116:                   screen: window?.screen ?? NSScreen.main,
1117:                   floorFraction: openingFitPendingFraction) else { return }
1118:         ipcCommand(MPVCommand.make(["set_property", "geometry", geom]))
1119:         if openingFitPendingFraction != GorVideoFit.openBaselineFraction {
1120:             openingFitNonBaselineApplied = true
1121:         }
1122:     }
1123:     private var lastShownMPVOSD:  String = ""
1124:     private(set) var visiblePictureBounds:CGRect = .zero
1125:     // Overlay chrome uses the cropped film frame. Keeping the rect PPController-owned
```

## Mandatory test
Replay source apply, missing layout, 500ms boundary, final landing without intermediate source crops.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
