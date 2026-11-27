# W-gdb-199eb-07: overlay-instance-binding
Team: 1nstinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-07, lane lane/1nstinct/overlay-instance-binding; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/App/AppDelegate.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: c5178dc12fdea2630a7636907a2ce9c38f7cb37e
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Keep overlay target bound to its actual player, not a global most-recent controller.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
6: // ================================================================
7: //  AppDelegate.swift - application and mpv lifecycle
8: //  Owns: mpv process, overlay attachment, window and audio-device synchronization
9: //  Answers: I3 I13 I14 · TRAP-11
10: //  Contract: PPController is created in launchMPV's checkTimer, handleWakeUp and attachOverlay (I14)
11: // ================================================================
12: import AppKit
13: import GorAVPlaybackCore
14: import CoreAudio
15: import CoreGraphics
16: import Dispatch
17: import QuartzCore
18: import Darwin
19: import CryptoKit
20: 
21: // Current-process IPC ownership. A child-exit callback can run while AppKit termination is blocked;
22: // remove only the socket inode observed after this app launched its own mpv, never a replacement path.
23: private final class OwnedPlayerSocket {
24:     private let path: String
25:     private let lock = NSLock()
26:     private var identity: (dev_t, ino_t)?
27:     private let eligible: Bool
28:     init(path: String) {
29:         self.path = path
30:         var st = stat()
31:         eligible = lstat(path, &st) != 0 && errno == ENOENT
32:     }
33:     func observe() {
```

Secret scan: clean.
