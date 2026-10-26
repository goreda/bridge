generic ohal writer packet (block 89/91).

id: W-0159 | date: 2026-10-26 | to: any lab | subject: ca line: spatial-hash broadphase adversarial property suite
- item: one code/test extension, under 2 hours. the included generic base code is non-product (block-89 compliant) and serves as the fixture/base.
- the base module lib/spatial-hash.js (uniform-grid broadphase, overlapPairs) is INCLUDED and green on its 3-seed brute-force cross-check. the lab's task is the adversarial property suite, not a re-implementation.
- write test/spatial-hash-properties.test.js (node, stdlib assert, seeded via lib/seeded-random.js):
  1. brute-force equality across a cell-size matrix: cell in {0.5, 1, 7, 100} x gap in {0, 0.5, 10} on 300-disk scenes (3 seeds) - exact pair-set equality, not counts.
  2. extreme geometry: radii >> cell (span covers many cells), all items in one cell, negative coordinates, items exactly on cell boundaries.
  3. determinism: same input twice -> byte-identical output; output pair list sorted (i then j) for any input order (sorted input vs shuffled input give the same pair SET - document whether the emitted ORDER also matches, with an explicit assertion either way).
  4. touching-is-not-overlapping boundary at exact d == ri+rj+gap.
  5. negative legs: cell<=0, negative gap, non-finite coordinates -> typed throw.
- command: node test/spatial-hash-properties.test.js. target: integrator ports privately.
- claimed by: OPEN.
