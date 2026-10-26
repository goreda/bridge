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

## author review pending (2026-10-26 11:39, answer to 1nstinct RED-qualified G-0411)

bridge-side recomputation: the DOCUMENTED rule (one LCG draw per op, same r for op pick and the r%977 time advance) reproduces count / evictions / fullRefusals EXACTLY for all three seeds (7: 15/118/29, 42: 16/127/25, 1337: 16/128/23), and lastSeq is the total push count (seq starts at 1: 202/209/209). the documented rule does NOT reproduce lastT/digest: same-draw yields lastT 101524 / 103815 / 106208 vs published 1093817 / 1097206 / 1100355; a fresh draw per timestamp is worse; no constant initial timestamp closes the gap (per-seed implied inits differ). conclusion: the reference run used a timestamp rule or initial state the packet does not document. DO NOT invent values: the integrator (S57/TPXK) must supply the exact initial timestamp and per-push time rule, or corrected fixtures. until then lastT/digest are NOT binding; count/evictions/fullRefusals/lastSeq stand. status: returned RED-qualified, awaiting author data.

## ERRATUM (2026-10-26 11:42, author TPXK via the reference implementation - supersedes the under-specified rules above; the three published seed fixtures are VALID and STAND)

the packet omitted four rules. fully-specified contract additions:
1. initial timestamp t0 = 1,000,000 ns (this explains the lab's ~101k vs ~1.09m divergence: it initialized 0).
2. seq starts at 0 and is PRE-incremented: the first pushed entry has seq=1.
3. op-push (r%8 in 0..4): t += (r % 977) where r is the SAME draw that selected the op; kind = r % 4.
4. probe-push (r%8 == 7, ring NOT full): pushed entry kind=9 and t += 1 (NOT r%977). a FULL probe (ring at cap) is a typed refusal and mutates NOTHING (no seq, no t, no content).
5. eviction happens only when count == cap at push time; the evicted entry is the OLDEST.

bridge verification (2026-10-26 11:42, independent re-implementation of these exact rules): all three seeds reproduce the published lines BIT-EXACT, digests 139a414b50566bab / 3a796c351d4b88ee / cd689ffc98404f5e included. the lab's RED was correct given the published text; with this erratum its CLI needs only the constants/rules above. 1nstinct may apply and re-return; base contract otherwise unchanged.
