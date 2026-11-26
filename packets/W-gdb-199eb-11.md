# W-gdb-199eb-11: wt-waiter-precedence
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/wt-waiter-precedence.
Source: archive/gor/Resources/vendor/wt_server/wt_server.mjs, lines 2669-2696.

## Product change
Give analysis a bounded missing-piece lane without stealing a waiting playback cursor.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
2669: function _playbackWaiterPiece(ring) {
2670:   if (!ring) return null;
2671:   return ring.waitedPieces.filter(p => _liveWaiterOwner(ring, p, true)).sort((a, b) => a - b)[0] ?? null;
2672: }
2673: function _refreshWaiterPriority(ring) {
2674:   // An old source ring may finish its callbacks after the global source swaps.
2675:   if (!ring || ring !== getRing()) return;
2676:   const index = _playbackWaiterPiece(ring);
2677:   if (index == null) {
2678:     _waiterBoost = null;
2679:     _setStreamingPriority('waiter', 1, 0, 2);
2680:     return;
2681:   }
2682:   const entry = (ring._waiters.get(index) || []).find(e => _validWaiterEntry(ring, index, e, true));
2683:   _boostWaiterPiece(index, entry);
2684: }
2685: function _boostWaiterPiece(index, entry = null) {
2686:   if (_torrentGone || _shuttingDown || !torrent || torrent.destroyed) return;
2687:   const ring = getRing();
2688:   if (!_validWaiterEntry(ring, index, entry, true)) return;
2689:   index = _playbackWaiterPiece(ring);
2690:   if (index == null) {
2691:     _waiterBoost = null;
2692:     _setStreamingPriority('waiter', 1, 0, 2);
2693:     return;
2694:   }
2695:   const to = Math.min(index + 1, totalFileLast);
2696:   if (_waiterBoost && _waiterBoost.from === index && _waiterBoost.to === to &&
```

## Mandatory test
Actual functions: playback wins, one analysis piece, abort/old-ring cleanup, no unrelated selection mutation.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
