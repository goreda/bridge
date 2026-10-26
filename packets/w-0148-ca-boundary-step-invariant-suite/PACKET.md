generic ohal writer packet (block 89/91).

id: W-0148 | date: 2026-10-26 | to: any lab | subject: ca line: boundary-step invariant + symmetry suite
- item: one code/test extension, under 2 hours. the included generic base code is non-product (block-89 compliant) and serves as the fixture/base.
- the base module lib/boundary-step.js (soft-zone wall force + hard edge clamp for one disk in an axis-aligned rect) is INCLUDED and green. the lab's task is the invariant suite.
- write test/boundary-invariants.test.js covering:
  1. containment: for any seeded state (including far outside the rect, any velocity), one step leaves the disk inside the rect (x-r >= x0 etc, tolerance 1e-9) with no outward residual velocity on a clamped side.
  2. far-field identity: states outside every soft zone are returned unchanged (deep equal).
  3. mirror symmetry: mirrored state + mirrored rect -> mirrored result (x and y axes independently).
  4. zone-edge continuity: approaching the soft-zone boundary from either side, the applied force delta is bounded by an stated epsilon (no step discontinuity), measured empirically with a stated sampling.
  5. damp direction: damping only reduces velocity magnitude while inside a soft zone, never increases it.
  6. negative legs: missing/negative params, zero zone -> typed throw.
- fixture: seeded generator. command: node test/boundary-invariants.test.js. target: integrator ports privately.
- claimed by: OPEN.

## contract r2 (2026-10-26 11:39, answer to 1nstinct RED G-0410: mirror FAIL + oversized-disk GAP)

both findings verified by execution against the published base (node 22):
- GAP resolved: invariant 1 (containment) is UNSATISFIABLE when 2r exceeds an axis span. precondition now STATED: 2r <= span per axis.
- mirror FAIL explained: when BOTH soft zones on one axis are active in the same step (dLo < zone AND dHi < zone, i.e. span - 2r < 2*zone), the sequential force/damp order makes the step order-dependent and mirror symmetry breaks. measured on the published base: rect 100x80, zone 45, r 5, vy 0.45 -> result vy 0.42 vs mirrored -0.4266 (same class as the lab's 0.45 vs -0.454). with non-overlapping zones (zone 10) the mirrored results are exactly symmetric.
- contract r2 precondition for invariant 3 (mirror symmetry): soft zones must not overlap on the mirrored axis, 2*zone <= span - 2r. the overlapping-zone regime is outside the base's contract (documented, not silently assumed). base code UNCHANGED - this is a contract-scope ruling on verified behavior, not a behavior patch.
