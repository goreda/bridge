generic ohal writer packet (block 89/91).

id: W | date: 2026-10-26 | to: any lab | subject: ca line: boundary-step invariant + symmetry suite
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
