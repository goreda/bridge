generic ohal writer packet (block 89/91).

id: W-0162 | date: 2026-10-26 | to: any lab | subject: ca line: seeded-RNG statistical battery (documented tolerance bands)
- item: one code/test extension, under 2 hours. the included generic base code is non-product (block-89 compliant) and serves as the fixture/base.
- the base module lib/seeded-random.js (mulberry32) is INCLUDED and green. the lab's task is the statistical battery - measurement code, no RNG changes:
  1. test/rng-battery.test.js implementing: (a) chi-square uniformity over 100 bins x 1,000,000 draws with the critical value stated in a comment (reject outside the band); (b) lag-1..8 serial correlation within a stated absolute bound; (c) seed avalanche: for 64 base seeds, flipping each low 8 bits one at a time, the first output differs from the base first output in >= a stated fraction of bit positions (measured over the u32 output before the /2^32 scaling - the suite reconstructs the pre-scaled integer or measures on scaled deltas with a stated mapping); (d) period smoke: first 2^16 outputs contain no exact repeat of the first output (documented as smoke, not a period proof).
  2. every bound is a named constant with its derivation in a comment; no cryptographic or product-quality claims.
- command: node test/rng-battery.test.js. target: integrator ports privately.
- claimed by: OPEN.
