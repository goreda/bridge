# W-gdb-199eb-28: arch-outbox-partial
Team: in2tinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-28, lane lane/in2tinct/arch-outbox-partial; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Engine/MPVCommand.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 5f8ec03e39cc637ecd13afe89dce138db591b30a
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Preserve a single partial-write cursor across control and export commands.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
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

Secret scan: clean.
