# Geometric-class synthetic ground-truth fixtures

Files: gen.py (fixtures + truth), truth.tsv (truth table), ref_roles.py (reference derivation, written fresh for this
set; no engine/legacy code copied), harness.py (recovery and false-rate harness), results.tsv (output), fixtures/*.json.
Run: `python3 gen.py && REPS=200 python3 harness.py [module]` (numpy only). Result in results.tsv; seeds are derived
from md5(fixture|sigma|rounded|rep), so a run is reproducible.

## Fixtures (19)
rect, ellipse_ext, ellipse_noext, line_seam, arch_split, s_curve, round_rect, and wedge_001..wedge_170 (corner ladder: one
corner of known exterior turn 1,2,3,5,8,12,20,30,45,90,135,170 degrees). Outline model: closed contours, nodes + segments
(line or cubic). Guides in the fixtures (baseline 0, x-height 500, cap 700, +-10 overshoot) are declared test values.

## truth.tsv columns: fixture, contour, kind, index, value, detail
kinds: node_geometric_class (corner | extremum | seam; detail turn_deg), interior_extremum (segment index, t; detail axis),
inflection (segment, t), flat_edge (horizontal straight segment, y; detail guide class or none).
Geometric class definitions used for truth and derivation (these are measurements, not semantic roles; every derived node carries status "proposed" and source "measured"): corner = tangent turn above tolerance; extremum = smooth node with an
axis-aligned tangent and at least one adjacent curved segment; seam = any other smooth node (G1 or collinear, not an extremum).
Interior extremum = axis extremum strictly inside a segment (a missing extremum node). Noise applied to every node and
control point (Gaussian sigma in font units: 0, 0.5, 1, 2, 4), with or without rounding to integers (CFF integer coordinates).

## Thresholds
All geometry thresholds come from a noise record {sigma, origin: measured|declared, derivation}, not from the fixtures:
sigma_eff = sqrt(sigma^2 + Q^2), Q = 1/sqrt(12) (declared: integer quantisation). Corner: turn > 3 * atan(sqrt2 * sigma_eff *
sqrt(1/L_in^2 + 1/L_out^2)) (L = handle or chord length). Interior extremum: farther than 3 * (sigma_eff + sqrt(2 R sigma_eff))
from both end nodes (R = radius of curvature there; extremum position moves by about sqrt(2 R sigma) for a perpendicular error).
Straight within noise: max deviation from chord < 3 sigma_eff. Closure: gap <= 3 * sqrt2 * sigma_eff.
CONVENTION constants (not measured): the 3 multiplier; "within about 1 degree of an axis" window in measure_noise.
Measured noise = RMS endpoint mismatch of axis-aligned straight lines / sqrt2; if there are none, sigma is declared as 0 + quantisation floor.

## Plugging in another geometric-class derivation
Module exposing derive(outline, noise=None) -> {"noise":..., "contours":[{"nodes":[{"node","geometric_class","status","source","turn_deg"}],
"interior_extrema":[{"seg","axis","t"}], "inflections":[{"seg","t"}], "flat":[{"seg","axis","pos"}]}]},
measure_noise(outline), closure_ok(gap, noise). Then `python3 harness.py yourmodule`. Truth is never read by derive.

## Status
Results in results.tsv and summary.md come from the reference derivation in ref_roles.py (REPS=200, numpy 2.2.6). Fixtures and truth.tsv regenerate byte-identically from gen.py, and results.tsv regenerates identically under the same numpy version.
