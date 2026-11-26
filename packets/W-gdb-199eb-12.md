# W-gdb-199eb-12: wt-stale-analysis
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/wt-stale-analysis.
Source: archive/gor/Resources/vendor/wt_server/wt_server.mjs, lines 2651-2678.

## Product change
Reject old-source/token/cursor analysis waiters after seek or source replacement.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Stale ring, token, signal, moved cursor and destroyed response cannot own priority.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
