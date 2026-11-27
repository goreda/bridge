# W-gdb-199eb-31: pip-action-target
Team: in2tinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-31, lane lane/in2tinct/pip-action-target; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/App/AppDelegate.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: c5178dc12fdea2630a7636907a2ce9c38f7cb37e
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Find PiP menu actions that accept but do nothing and wire them to the actual player instance.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
29:         self.path = path
30:         var st = stat()
31:         eligible = lstat(path, &st) != 0 && errno == ENOENT
32:     }
33:     func observe() {
34:         guard eligible else { return } // never claim a path that predates this launch
35:         var st = stat()
36:         guard lstat(path, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK), st.st_uid == getuid() else { return }
37:         lock.lock(); defer { lock.unlock() }
38:         if identity == nil { identity = (st.st_dev, st.st_ino) }
39:     }
40:     func childExited() {
41:         lock.lock(); defer { lock.unlock() }
42:         guard let owned = identity else { return }
43:         var st = stat()
44:         guard lstat(path, &st) == 0, st.st_dev == owned.0, st.st_ino == owned.1,
45:               (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK), st.st_uid == getuid() else { return }
46:         _ = unlink(path)
47:         identity = nil
48:     }
49: }
50: 
51: // ================================================================
52: //  DraggableOverlayWindow - drag destination window
53: // ================================================================
54: final class DraggableOverlayWindow: NSWindow {
55:     override var canBecomeKey: Bool { !NoActivate.active }
56:     override var canBecomeMain: Bool { !NoActivate.active }
```

Secret scan: clean.
