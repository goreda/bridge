# Depth-feel baseline vs span gain (owner 17:07: "depth feel and realism not good enough, improve it")

Measured on the real metric depth maps (exact atan disparity, no
rendering; `tools/depth_analysis/depth_feel_report.py`, pinned by
`Tests/DepthAnalysis/test_depth_feel.py`). Baseline = the CURRENT
default comfort policy (`shot_comfort`: effective baseline derived from
the shot median only). Span = the F3 policy (`ShotComfortSpan`,
41b34019; mirror `comfort.shot_comfort_span`): the gain comes from the
shot's own p5/p95 disparity quantiles, largest value inside the same
comfort budgets (crossed <= +2.0 deg, uncrossed >= -1.0 deg).

| shot | z_c m | base scale | span gain | span base deg | span new deg | meas p5-95 base | meas p5-95 span | crossed max | uncrossed min | near-clamped |
|---|---|---|---|---|---|---|---|---|---|---|
| CG golden 48f 640x360 | 1.14 | 0.31 | 0.93 | 0.84 | 2.46 | 0.84 | 2.46 | +2.00 | -0.50 | 0.049 |
| live 207f 720p (fps=3) | 2.58 | 0.72 | 0.82 | 2.25 | 2.58 | 2.25 | 2.58 | +2.00 | -0.80 | 0.049 |

## What this says

- The baseline policy under-delivers exactly on the content the owner
  is watching: CG at 0.31x IPD renders a 0.84 deg disparity span - a
  third of the comfortable budget. The span policy triples the
  effective baseline (gain 0.93 vs 0.31) and the span to 2.46 deg while
  staying inside both budgets BY CONSTRUCTION (crossed max +2.00,
  uncrossed -0.50).
- The live shot was already near budget (0.72x, 2.25 deg); span
  normalises it to 2.58 deg. Depth feel becomes SCALE-INVARIANT across
  shots (~2.5 deg) instead of content-lucky (0.84 vs 2.25).
- Cost: 4.9% of pixels sit on the near clamp (flattened to the clamp
  plane), same order as the s25 baseline measurement (3.3%). The clamp
  is what keeps crossed at +2.00 exactly.

## Concrete changes (landed / to wire)

1. F1 s3d_fill (realism: disocclusion bands) - reference landed
   cf862d58 (blend <=16 px, far-column vertical average above, integer-
   exact round-half-up; staged-step metric: vstep 81.8 -> 27.7). E-G
   mirrors in s3d_fill + text pins.
2. F3 span gain (depth feel) - pure fn 41b34019, comfort.py mirror +
   near_clamp_m landed (cf862d58 + this change). E-G wires into the
   comfort path + render key; A-D updates test_render_key_matrix when
   the key shape lands. Wiring note: z_near for the render clamp =
   near_clamp(z_c, ipd*gain) = `shot_comfort_span_values[...]["near_clamp_m"]`;
   strengthFactor should multiply the GAIN (and stay budget-clamped),
   not re-derive the baseline.
3. Disparity scaling: span gain IS the scaling lever - up to 3x on flat
   shots, budget-clamped everywhere; no unbudgeted scaling proposed
   (comfort contract holds).
