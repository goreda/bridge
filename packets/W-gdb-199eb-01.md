# W-gdb-199eb-01: crop-receipt-timeout
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/crop-receipt-timeout.
Source: archive/gor/Sources/gor/Player/PPController.swift, lines 1-28.

## Product change
Prevent an absent final receipt from resending the same crop four times; preserve source/window token fences.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Replay final sent then missing receipt and assert one bounded retry, stale tokens rejected.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
