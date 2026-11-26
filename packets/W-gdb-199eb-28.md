# W-gdb-199eb-28: arch-outbox-partial
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/arch-outbox-partial.
Source: archive/gor/Sources/gor/Engine/MPVCommand.swift, lines 1104-1131.

## Product change
Preserve a single partial-write cursor across control and export commands.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
1104:         exportFlushScheduled = true
1105:         queue.async { [weak self] in
1106:             guard let self else { return }
1107:             self.exportFlushScheduled = false
1108:             self.flushExportOutbox()
1109:         }
1110:     }
1111:     /// lines die typed ("load-changed") — a stale queued request never runs on a new load. This is the ONLY scope authority.
1112:     func noteExportLoad(session: String, opening: UInt64) {
1113:         OwnerQueue.sync(queue) { self.exportOutboxCore.noteLoad(session: session, opening: opening) }
1114:     }
1115:     /// Owner queue only, its own turn: delivers deferred admission terminals, then writes queued lines FIFO over the live NONBLOCKING socket under the
1116:     /// core's per-turn budget. EAGAIN mid-line is terminal at the core (typed, naming the offset; the socket latches dead; nothing is replayed): the
1117:     /// onDead hook tears the connection down. A budgeted yield re-schedules the next turn instead of occupying the owner.
1118:     private func flushExportOutbox() {
1119:         guard isConnected, fd >= 0 else { return }
1120:         exportOutboxCore.drain()
1121:         if exportOutboxCore.pendingCount > 0 { scheduleExportFlush() }
1122:     }
1123:     func write(_ payload: String) {
1124:         queue.async { [weak self] in
1125:             guard let self, self.isConnected, self.fd >= 0 else {
1126:                 // A control line that arrives while disconnected never entered the wire: never silent.
1127:                 self?.ordinaryWriteDrops &+= 1
1128:                 if let s = self, s.ordinaryWriteDrops == 1 || s.ordinaryWriteDrops % 64 == 0 {
1129:                     NSLog("[ipc] ordinary write dropped (disconnected), total=\(s.ordinaryWriteDrops)")
1130:                 }
1131:                 return
```

## Mandatory test
Partial socket writes, EAGAIN and ordinary/control burst cannot interleave JSON lines.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
