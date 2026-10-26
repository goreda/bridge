# CANON-FIX-1: canonical arm wires the landed rounding reconcile (2026-10-18)

Status: MEASURED on the W2-3 measurement set (253-glyph Marq/Alternate
manifest, sha-verified tiles from the same Drive folder W2-3 used).

## Finding being closed (W2-3, measured)

The canonical chain arm (capture_png -> fit_captured -> integer charstring,
K=1) did not run rounding_reconcile. 7 glyphs production ships
(percent, comma, exclamdown, quotesinglbase, quotedblbase, perthousand,
uni2078) refused in the canonical arm with
charstring_refused:UnrepresentableCoordinate; canonical K1 mean scan IoU
0.985097 vs production 0.989811
(docs/engine/execution/20261018-canonical-path-k1/measurements.tsv).

## Why the canonical arm skipped reconcile

Structural, not intentional. The reconcile code landed (slot 23, W2-2) as a
module private to the kni-pipeline binary (`mod rounding_reconcile;` in
pipeline/src/main.rs); the canonical harness lives in
engine/core/examples/canonical_path_run.rs and can only import kni-core.
Nothing importable carried the reconcile stage, so the harness called the
integer container on raw fit output and typed the refusals.

## Change

- Pure move, byte-identical apart from crate paths: pipeline/src/
  rounding_reconcile.rs -> engine/core/src/rounding_reconcile.rs
  (kni_core:: -> crate::); pipeline/src/main.rs imports it back with
  `use kni_core::rounding_reconcile;`. No production-path behavior change.
- Additive in the moved module: quantize_outline + QuantizeReport - the
  same per-scalar export-grid rounding production applies inside
  prepare_generated_with_placement (round half away from zero,
  EXPORT_RESOLUTION), with typed stats (moved, max_abs_delta, non_finite).
  Non-finite coordinates are counted and left in place for the integer
  gate; range checking stays with the charstring gate.
- Canonical arm only: run_arm(reconcile=true) quantizes after fit_captured,
  runs drop_constant_cubics with typed note tokens, and measures
  (segments, fit error, IoU, charstring) the reconciled outline - what the
  arm would ship. The production arm runs the raw chain exactly as W2-3
  measured it (reconcile=false), so the comparison baseline is unchanged.
- New tests: engine/core/tests/canonical_reconcile.rs (5 tests pinning the
  wiring contract, incl. held all-constant rings and the non-finite typed
  remainder).

## Measured after (this tree; measurements-after.tsv, same schema as W2-3)

- Canonical arm container refusals: 7 -> 0. All 253 glyphs reach an integer
  charstring; canonical-k1.otf ships notdef + 253 glyphs (before: 247),
  88993 bytes, sha256 fc2a23608ad1852006f15c5649ba787e818ba2ca9604a01aa8a9e9f80c40711e.
- Reconcile touched exactly the 7 previously-refused glyphs
  (reconcile_quantized moved>0 on percent, comma, exclamdown,
  quotesinglbase, quotedblbase, perthousand, uni2078; 0 coordinates moved
  on the other 246); 0 constant cubics created, 0 held, 0 non-finite.
- Canonical K1 scan IoU mean 0.985087 (before 0.985097; delta -0.00001).
  Per-glyph IoU deltas on the 7 reconciled glyphs: -0.00002 to -0.00079
  (integer-grid quantization at K=1); all remain in 0.982-0.990.
- Canonical fit error sfe mean 0.124864 px^2 (before 0.124240); the small
  increase is the expected quantization noise on the 7 reconciled glyphs.
- Production arm byte-identical to the W2-3 run: production.otf sha256
  661fbf5a90de9cca2c951d2cf44f7afaacde3d1db20d5e592039a6d35303d1d5 (252
  glyphs, its two documented raw-chain refusals percent/perthousand
  unchanged) - independently reproduced on this tree from the same
  sha-verified tiles.
