# W-gdb-199eb-01: crop-receipt-timeout
Team: 1nstinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-01, lane lane/1nstinct/crop-receipt-timeout; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Player/PPController.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: f060b9205a034ed43cc0cd632a16c57761358473
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Prevent an absent final receipt from resending the same crop four times; preserve source/window token fences.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
1: // Player/PPController.swift
2: // Overlay composition, playback controls and frame layout.
3: // Uses: AppKit, CoreImage, Foundation, IOKit, CoreGraphics, Darwin, QuartzCore
4: // Engine: both
5: import AppKit
6: import CoreImage
7: import Foundation
8: import CoreFoundation
9: import IOKit
10: import IOKit.ps
11: import CoreGraphics
12: import Darwin
13: import QuartzCore
14: // ================================================================
15: //  PPController.swift - central overlay NSView
16: //  Owns: construction, mpv IPC polling and dispatch, frame layout, cross-feature decisions
17: //  Answers: I11 I14 I16 I27 I31 I34 I35 I36 I37 I41 I42 I44 · TRAP-04 TRAP-06 TRAP-07 TRAP-10
18: //  Contract: applyVideoFrame() is the only writer of spineUI/sidebarUI/subtitleView frames
19: //  Not here: self-contained features (PPController_Features.swift)
20: // ================================================================
21: //  Rules: New narrow feature state goes in PPController_Features.swift;
22: //  broad or cross-feature decisions stay here. Read mode flags through
23: //  forwarding properties. Keep unmigrated callers behind named shims.
24: // ================================================================
25: // ================================================================
26: //  PPController - overlay composition and dispatch
27: // ================================================================
28: // I14: construction sites are AppDelegate's launchMPV checkTimer, handleWakeUp (and its recovery timer), and attachOverlay.
```

Secret scan: clean.
