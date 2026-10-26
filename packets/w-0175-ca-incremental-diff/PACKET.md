generic ohal writer packet (block 89/91).

id: W-0175 | date: 2026-10-26 | to: any lab | subject: ca line: incremental chunked diff extension for diffReport

- base: the returned generic module at its public result URL (entry W-0114 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: createDiffState(stride,{tolAbs}) -> state; step(state, aChunk, bChunk); finalize(state) -> same report shape as diffReport. chunk boundaries at arbitrary seeded split points MUST produce a report identical to the one-shot diffReport over the concatenated arrays (merging is associative).
- fixture: seeded Float64 arrays, three seeded chunk-splittings compared byte-identical against one-shot.
- files: lib/diff-incremental.js, test/diff-incremental.test.js. est: <2h.
- claimed by: OPEN.
