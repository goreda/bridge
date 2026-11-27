# W-gdb-199eb-12: wt-stale-analysis
Team: 1nstinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-12, lane lane/1nstinct/wt-stale-analysis; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Resources/vendor/wt_server/wt_server.mjs@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: edc23aba0a285686d190738634f2848784ee6ad9
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Reject old-source/token/cursor analysis waiters after seek or source replacement.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
2651: }
2652: // One shared waiter priority must not become last-analysis-reader-wins.
2653: // Only an actually waiting, live playback cursor is eligible. Probe and
2654: // analysis ownership remains intact, but neither may displace that cursor.
2655: function _validWaiterEntry(ring, piece, entry, playbackOnly = false) {
2656:   if (!entry || !(ring?._waiters?.get(piece) || []).includes(entry)) return false;
2657:   const owner = activePumps.get(entry.pumpId);
2658:   return !!owner && entry.signal === owner.abortController?.signal &&
2659:     entry.playbackToken === owner.playbackToken && owner.playbackToken === _activePlaybackToken &&
2660:     !entry.signal?.aborted && !owner.response?.destroyed && !owner.response?.writableEnded &&
2661:     owner.cursorPiece === piece && (!playbackOnly || (!owner.isAnalysis && !owner.isProbe));
2662: }
2663: function _liveWaiterOwner(ring, piece, playbackOnly = false) {
2664:   for (const entry of ring?._waiters?.get(piece) || []) {
2665:     if (_validWaiterEntry(ring, piece, entry, playbackOnly)) return activePumps.get(entry.pumpId);
2666:   }
2667:   return null;
2668: }
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
```

Secret scan: clean.
