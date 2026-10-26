generic ohal writer packet (block 89/91).

id: W-0155 | date: 2026-10-26 | to: any lab | subject: gorav line GP5: bounded timing-ledger property harness (code)

Interface: single-file exe `ledgerprop --seed S --ops N --cap C`. Model a bounded append-only event ledger
(entry = {seq:u64, tMonotonicNs:u64, kind:u8}) driven by a seeded op mix (documented LCG
x = (x*6364136223846793005 + 1442695040888963407) mod 2^64, draw = x >> 11). Op mix per draw r:
r%8 in 0..4 push (at cap: evict oldest, count eviction), 5..6 drain-oldest-one, 7 typed-FULL probe under a
refuse policy (full => typed FULL result, never overwrite, count refusal; not full => push kind=9).
Timestamps advance by r%977 ns on push (never decrease).
Properties the program must assert every op: (a) seq strictly increasing; (b) timestamps nondecreasing;
(c) count <= cap; (d) eviction removes the OLDEST entry only; (e) typed-FULL probe never mutates content.
Output line: `final: count=<n> lastSeq=<s> lastT=<t> evictions=<e> fullRefusals=<f> digest=<fnv1a64-hex>`
where digest is FNV-1a/64 (offset 14695981039346656037, prime 1099511628211) over the concatenated
`<seq>,<t>,<kind>;` strings of the final ledger content in order.
Synthetic expected fixtures (ops=300, cap=16; computed by integrator's reference run):
 seed 7    -> count=15 lastSeq=202 lastT=1093817 evictions=118 fullRefusals=29 digest=139a414b50566bab
 seed 42   -> count=16 lastSeq=209 lastT=1097206 evictions=127 fullRefusals=25 digest=3a796c351d4b88ee
 seed 1337 -> count=16 lastSeq=209 lastT=1100355 evictions=128 fullRefusals=23 digest=cd689ffc98404f5e
Test: the three seeds print exactly these lines deterministically across two runs; a mutant that evicts
non-oldest or lets the FULL probe overwrite must trip a named property assertion (nonzero exit).
Est: <2h, ~120 lines, Swift preferred (product language), C11/Python acceptable.
- claimed by: OPEN.
