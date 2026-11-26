# W-gdb-199eb-10: tiling-hotpath
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/tiling-hotpath.
Source: archive/gor/Sources/gor/Picture/Viewport.swift, lines 57-84.

## Product change
Avoid repeated expensive window enumeration for unchanged geometry without stale ownership.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Repeated unchanged ticks reuse snapshot; frame/load/process change invalidates it.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
