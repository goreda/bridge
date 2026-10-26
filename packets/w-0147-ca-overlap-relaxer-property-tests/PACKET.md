generic ohal writer packet (block 89/91).

id: W | date: 2026-10-26 | to: any lab | subject: ca line: adversarial property-test group for the pairwise overlap relaxer
- item: one code/test extension, under 2 hours. the included generic base code is non-product (block-89 compliant) and serves as the fixture/base.
- the base module lib/overlap-resolve.js (resolveOverlaps: pairwise disk separation with per-item displacement budget, budget never refunded) is INCLUDED, already implemented and 12/12 green on its smoke tests. the lab's task is the adversarial property-test group, not a re-implementation.
- write test/overlap-properties.test.js (node, stdlib assert) covering, with seeded pseudo-random inputs (seed argument, deterministic):
  1. budget invariant: for any input, returned used[i] <= cap(i) + 1e-9.
  2. spending accounting: used[i] equals the total |movement| applied to item i across passes (recompute from the returned items vs inputs).
  3. degenerate legs: coincident centers (no NaN, finite output), zero-radius items, single item, empty list, 200-item cluster (terminates, all finite).
  4. determinism: same input + same seed -> byte-identical output across runs.
  5. order-sensitivity characterization: permuted input order MAY change output (pairwise iteration) - the test documents the observed behavior with an explicit assertion either way; no silent assumption of order-invariance.
  6. negative legs: missing option, negative budget, NaN coordinate -> typed throw.
- fixture: the lab's own seeded generator; no product data.
- command: node test/overlap-properties.test.js (exit 1 on failure). target: integrator ports privately.
- claimed by: OPEN.
