# W-gdb-199eb-06: tiling-self-membership
Team: 1nstinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-06, lane lane/1nstinct/tiling-self-membership; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/App/AppDelegate.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: c5178dc12fdea2630a7636907a2ce9c38f7cb37e
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Include this player in layout computation when peer discovery excludes its PID.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
4329:             Self.tiling.unfinished = "own launch date unavailable; placement refused (no stable order)"
4330:             print("[tile] REFUSED own-launch-date-unavailable")
4331:             return
4332:         }
4333:         let seen = snap.peers + [me]
4334:         let key = seen.map { [Int($0.pid), Int($0.screenID), Int(($0.size?.width ?? 0) / 2), Int(($0.size?.height ?? 0) / 2)] }
4335:         if let p = Self.tiling.pending, p == key { Self.tiling.pending = nil; Self.tiling.passes = 0 }
4336:         else {
4337:             Self.tiling.pending = key; Self.tiling.passes += 1
4338:             if Self.tiling.passes <= 6 { scheduleRetile(why) } else {
4339:                 Self.tiling.pending = nil; Self.tiling.passes = 0
4340:                 Self.tiling.unfinished = "peer observations did not stabilise in 6 passes, placement unfinished"
4341:                 NSLog("[tile] UNFINISHED: %@", Self.tiling.unfinished ?? "")
4342:             }
4343:             return
4344:         }
4345:         // The natural must still belong to the active identity NOW (not only when it was admitted): a purge, reconnect or
4346:         // new opening between admission and this retile makes it stale; do not place with it, the next admission retriggers.
4347:         if Self.tiling.naturalFromPublished && !publishedNaturalIsCurrent() { return }
4348:         let before = win.frame
4349:         let natural = Self.tiling.natural ?? GorFitSize(w: before.width, h: before.height)
4350:         if Self.tiling.natural == nil { Self.tiling.natural = natural }
4351:         let peers = seen.map { GorTilePeer(pid: $0.pid, launchOrder: $0.launch, screenID: $0.screenID,
4352:                                            size: $0.size.map { GorFitSize(w: $0.width, h: $0.height) }) }
4353:         // Kernel space per screen: x/y relative to that screen's usable area, y down. Converted back below.
4354:         guard let k = GorPlayerTiling.frame(for: getpid(), natural: natural, peers: peers, avail: { id in
4355:             guard let s = PlayerPeerObservation.screen(withID: id) else { return nil }
4356:             let u = self.tilingUsable(s)
```

Secret scan: clean.
