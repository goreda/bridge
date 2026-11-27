# W-gdb-199eb-11: wt-waiter-precedence
Team: 1nstinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-11, lane lane/1nstinct/wt-waiter-precedence; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Resources/vendor/wt_server/wt_server.mjs@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: edc23aba0a285686d190738634f2848784ee6ad9
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Give analysis a bounded missing-piece lane without stealing a waiting playback cursor.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
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

Secret scan: clean.
