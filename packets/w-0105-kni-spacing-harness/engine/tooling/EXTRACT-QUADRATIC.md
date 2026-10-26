# extract_quadratic.py — TrueType quadratic-contour extractor

Standalone; Python 3.9+, fontTools 4.65.0 (pinned).

## Contract
Per font, one JSONL file: one JSON object per glyph, glyph order (gid
ascending), keys sorted, separators `,`/`:`.
- `glyph` (string), `gid` (int), `advance` (int, hmtx after wght=400
  instantiation for variable fonts), `contours` (array of contours; each
  contour is an array of `[x, y, on]`, `on` = 1 on-curve / 0 off-curve).
- Raw glyf point stream: consecutive off-curve points kept as-is; implied
  on-curve midpoints NOT materialized (consumer applies the TT midpoint
  rule). No cubic conversion. Composites decomposed with transforms applied
  (recursion limit 32). Variable fonts instantiated at wght=400 first.
- `upm` is returned to the caller (per-font manifest, not in rows).

## Explicit per-glyph refusals (typed, counted, never silent)
A glyph that cannot be extracted faithfully is emitted with empty
`contours` and a `refused` object:
- `all_off_curve_contour` — contour with no on-curve point (fontTools emits
  `qCurveTo(..., None)` with no preceding `moveTo`).
- `anchor_matched_component` — composite component positioned by
  anchor-point matching, detected via the decompiled `firstPt`/`secondPt`
  attributes (fontTools strips the raw flag bits on load). The
  `anchor_points` pairs are recorded. Real anchor resolution is a separate,
  tested follow-up version.
- `cubic_segment`, `composite_recursion_depth`.
The run summary prints `refused=<total>` and `refused_by_reason={...}`.

## Tests
`python3 -m unittest -v test_extract_quadratic.py` — 3 synthetic tests:
all-off-curve contour refusal, anchor-matched component refusal, and a
positive control (normal xy-offset composite extracts with translated
points).

## Known limits
- Anchor-point detection inspects the components of the glyph being
  extracted. A composite whose component glyph is itself anchor-matched is
  not covered by a test.
- Real anchor resolution is not implemented; such glyphs are refused.
- The tests use synthetic fonts only. Extracted outlines and font-derived
  data are not stored in this repository.
