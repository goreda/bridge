# W-gdb-199eb-08: crop-fit-source-first
Team: 1nstinct. State: APPLIED_SOURCE_RECONCILE. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-08, lane lane/1nstinct/crop-fit-source-first; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Player/PPController.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: f060b9205a034ed43cc0cd632a16c57761358473
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Preserve source crop first, then final window fit on layout-ready or bounded deadline.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Route application already recorded at 6c0502fb9c7a141ec09c8fcd52a83ce2de929d31. Do not repeat this work; reconcile any remaining gap under this ID.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
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

Secret scan: clean.
