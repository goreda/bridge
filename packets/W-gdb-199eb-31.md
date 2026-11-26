# W-gdb-199eb-31: pip-action-target
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/pip-action-target.
Source: archive/gor/Sources/gor/App/AppDelegate.swift, lines 29-56.

## Product change
Find PiP menu actions that accept but do nothing and wire them to the actual player instance.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Invoke each real PiP action against two controllers; named target changes only its state.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
