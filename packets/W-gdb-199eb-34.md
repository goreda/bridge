# W-gdb-199eb-34: pip-fullscreen-fit
Team: in2tinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-34, lane lane/in2tinct/pip-fullscreen-fit; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Picture/Viewport.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: e53a0509941427f64db391a5967675260b048a0d
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Restore frame fit when leaving PiP/fullscreen without using another player window frame.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
57:     /// Resolution class anchor: long side 1280 (720p class) = the floor.
58:     static let baselineLongSide = 1280.0
59: 
60:     /// Resolution-sensitive proposed opening size (the "scale" half).
61:     static func proposedOpenSize(videoW: Double, videoH: Double,
62:                                  screenW: Double,
63:                                  floorFraction: Double = openBaselineFraction) -> GorFitSize {
64:         guard videoW > 0, videoH > 0, screenW > 0, floorFraction > 0 else {
65:             return GorFitSize(w: 0, h: 0)
66:         }
67:         let longSide = max(videoW, videoH)
68:         let floorTarget = screenW * floorFraction
69:         let scaledTarget = floorTarget * (longSide / baselineLongSide).squareRoot()
70:         let longTarget = max(floorTarget, scaledTarget).rounded(.down)
71:         // F2 (review): extreme aspect ratios must never propose a zero side;
72:         // clamp both derived sides to >= 1 (a zero proposal silently degraded
73:         // to no geometry at all).
74:         if videoW >= videoH {
75:             return GorFitSize(w: max(1, longTarget), h: max(1, (longTarget * videoH / videoW).rounded(.down)))
76:         } else {
77:             return GorFitSize(w: max(1, (longTarget * videoW / videoH).rounded(.down)), h: max(1, longTarget))
78:         }
79:     }
80: 
81:     /// The shrink-and-center rule (the "shrunk" half; literal 170c formula):
82:     ///   scale   = min(1, avail.w / v.w, avail.h / v.h)   (shrink only)
83:     ///   content = v * scale, rounded down
84:     ///   window  = content centered inside avail
```

Secret scan: clean.
