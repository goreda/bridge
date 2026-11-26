# W-gdb-199eb-35: pip-source-reopen
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/pip-source-reopen.
Source: archive/gor/Sources/gor/App/AppDelegate.swift, lines 6-33.

## Product change
Keep PiP source replacement from reopening a second process or leaving stale overlay.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Rapid source replacement has one process per intended player and old overlay retired.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
