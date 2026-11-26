# W-gdb-199eb-06: tiling-self-membership
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/tiling-self-membership.
Source: archive/gor/Sources/gor/App/AppDelegate.swift, lines 4329-4356.

## Product change
Include this player in layout computation when peer discovery excludes its PID.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
1..4 independent players receive distinct frames; missing own PID must reproduce baseline failure.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
