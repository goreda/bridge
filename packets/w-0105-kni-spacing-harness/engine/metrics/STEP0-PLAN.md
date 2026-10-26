# kni-metrics step 0 plan: baseline + collision validator

Scope: step 0 of the implementation order (baseline_htls +
collision validator = the pipeline skeleton exercised end-to-end on a
published formula). Acceptance gates: the secondary gates, plus the
MWF measurable success criterion clarified below.

## What this drop contains

Crate kni-metrics at engine/metrics, sibling of engine/core (package layout
decision of the kni-line architecture; the crate is dependency-free std-only
Rust at this step).

Real code:
- plane: input-plane abstraction. Pair geometry APIs accept BOTH planes from
  day one: InkScan is the minimal geometry
  surface (per-scanline ink spans); RasterGlyph implements it over capture
  renders today, a contour backend implements it when the engine emits
  trusted outlines.
- params: master parameters in plane units, published HTLS defaults
  (area 400, depth 15 percent, over 0, freq 5).
- evidence: derivation tiers (direct-source / class-derived / engine-derived
  / designer-override), rule status (proposed / validated), principle ledger
  record, spacing receipt.
- baseline_htls: full published method (margin scan, depth clamp, 45-degree
  closure, deslant, white-polygon quadrature, sidebearing conversion).
- collision: raster-conservative overlap validator behind a plane-agnostic
  CollisionValidator trait; the exact outline validator (collision
  module) plugs into the same trait later.

Documented stubs (module role, source grounding, tier, in-code):
distance_field (1), side_walls (2), side_classes (3), stress + air (4),
mechanisms + positions (5), export_gpos (6), variation (8), tracking (9).

## baseline_htls: provenance and adaptations

Clean-room reimplementation of the published HT Letterspacer method
(huertatipografica/HTLetterspacer, htls/engine.py). Upstream code is
GPL-3.0; it was consulted for formula semantics only, no code was copied.
The published pipeline: scan horizontal margins at freq steps over the
glyph bounds; filter to the reference window (reference glyph bounds plus
overshoot; default reference = the glyph itself); deslant at the italic
angle about half x-height; clamp margins to depth = x_height *
paramDepth/100 from the zone extremes; close transitions at 45 degrees;
close the polygon at the extreme line; white-polygon area by shoelace;
sidebearing = (amplitude * white_area / x_height - polygon_area) /
amplitude, with white_area = paramArea * (upm/1000)^2 * 100; integer result
= ceil(sb - distance between zone and full extremes).

Raster-plane adaptations, declared:
- The margin scan reads per-row ink spans from the capture mask instead of
  vector scanline intersections. The outermost ink pixel per row IS the
  outermost intersection; no information is lost at capture resolution.
- All quantities are plane units (capture px). The formula is scale
  covariant: scaling every input by s scales sidebearings by s (tested).
- Category factors (published rule system) arrive with side_classes
  (step 3); until then area_factor defaults to 1.0.
- The module is a heuristic proxy by design: it exercises the pipeline
  skeleton with a published formula. It does not claim the MWF gate.

## collision validator

Today the gate is raster-conservative: two placed ink masks must not share
cells. It is a necessary-condition check at capture resolution, not a
sub-pixel collision-free proof (known limitation: an 'o'-derived contact floor is
NOT a collision-free proof; blur/SDF remains an open alternative for
diagonals). When the engine emits trusted outlines, the exact outline
validator implements the same trait and the raster check stays as the fast
pre-filter.

## Step 0 exit gates (as applicable to step 0)

- Collision-free under the raster validator on the synthetic test set.
- Unit/scale invariance: implemented and tested (scale_invariance test).
- Determinism: same input, identical output, including receipts (tested).
- Published-formula parity spot-checks against documented upstream behavior:
  flat side gets the nominal value (tested), indented side gets a tighter
  value than flat (tested), depth clamp active on open counters (next).

## Step 0 progress log

DONE (this drop):
- Pair placement driver (place_pair): spaces both glyphs, places the second
  at origin + advance + kern (natural width advance), runs the raster
  collision gate, returns placements + verdict for the pair receipt.
- Synthetic test set at unit level (design subset): HH/OO/HO/OH pair
  clears, AV/VA diagonal pair clears, T+A clears, negative-kern collision
  detection, round-tighter-than-flat, depth clamp on an open counter
  (shallow vs deep), italic deslant recovering upright spacing at 12
  degrees. 15 tests, all green.
- Deslant sign corrected for the raster plane (y down): deslant ADDS
  (y - mline)*t with mline = baseline_y - x_height/2; the InkScan contract
  is y-down, a contour backend flips at the plane boundary. baseline_y
  added to MasterParams (used only when italic_angle_deg != 0).

REMAINING:
1. e/r/f silhouettes and an HVH italic pair in the test set (current set
   covers the gate logic; letterform-shaped coverage widens it).
2. Integration seam: kni-metrics stays dependency-free until step 5 needs
   engine capture types; the dependency direction is decided then.
3. Kit renders join when the harness lane opens for the metrics engine.

## MWF acceptance criterion: clarification of the proposal

The MWF primary gate proposal reads: the solved dx* must reproduce the
measured displacement on tier-(a) pairs within tolerance (PROPOSED:
|dx* - measured| <= 1 capture px for >= 95% of the band; final threshold
set by the project maintainers from measurement noise). Clarified:

1. THE BAND. 353 directly rendered pairs x 8 styles = 2824 pair instances,
   each carrying a MEASURED displacement from the source font (tier
   direct-source). The band set and its measurement receipts are the ground
   truth artifact; the gate never runs on a subset chosen after the fact.
2. WHAT IS COMPARED. dx* is the engine-solved mutual pair displacement
   (PairOriginDistance), expressed in the band render's capture pixels at
   the moment of comparison. Comparisons in font units are forbidden: the
   measured side is a raster quantity, so the solved side is converted to
   capture pixels, not the reverse.
3. WHAT "1 CAPTURE PX" MEANS. The tolerance lives in the capture's own
   pixel grid. In font units it equals 1/s, where s = capture px per font
   unit of the band renders; s is reported alongside every gate result.
4. WHO SETS THE FINAL THRESHOLD, AND HOW. The project maintainers fix the final number
   from the measurement noise floor: re-render and re-measure a sample of
   the band, take the p95 of |repeat - first| as the noise floor, and set
   threshold = max(1 px, noise floor p95). Until that noise study runs,
   1 capture px is the working value, not the ratified one.
5. PASS RULE. >= 95% of the 2824 instances within tolerance; every failure
   is listed with its residual, uncertainty and active mechanism IDs
   (evidence gate). A mechanism that cannot reproduce the font on pairs the
   font itself showed has no authority on pairs it did not.
6. CLASS-PROPAGATED PAIRS. They stay within their class's measured max_dev
   spread, reported per class, not pooled.
7. APPLICABILITY. This gate binds from step 5 (mechanisms + positions)
   onward. Step 0 is a published heuristic proxy and does not claim the
   MWF gate; its exit gates are the secondary gates listed above.
