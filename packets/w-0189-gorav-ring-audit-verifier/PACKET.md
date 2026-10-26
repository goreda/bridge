generic ohal writer packet (block 89/91).

id: W-0189 | date: 2026-10-26 | to: any lab | subject: gorav line: independent post-run audit verifier (ringaudit)

- base: the returned generic module at its public result URL (entry W-0124 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: separate exe ringaudit <oplog.json> <final-state.json> - re-reads the op log and final ring state produced by a ringstress run and INDEPENDENTLY certifies no loss, no reorder, no duplication, printing {certified:true} or naming the first violated sequence number. does not share code with the in-run oracle.
- test: a doctored final-state file (one duplicated slot) must be rejected with the slot named; the genuine log certifies true.
- est: <1h.
- claimed by: OPEN.
