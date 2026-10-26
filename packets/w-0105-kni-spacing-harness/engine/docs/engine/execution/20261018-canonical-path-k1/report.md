# Canonical-path run: capture_png -> fit_captured -> integer charstring, K=1 (W2-3 / next-version work list item 4, 2026-10-18)

Status: MEASURED on the full 253-glyph Marq/Alternate manifest. Repeatable: two
independent invocations produced byte-identical artifacts. Descriptive
measurement only; no engine code changed; no gate claimed.

## Interpretation

K is the fit/frame scale (the only meaning K carries in this tree:
process/TASKS "Shared scale K", frame id FITK, economy_eval EvalConfig.scale_k).
K=1 = fit scale 1.0 (pixel grid). The comparison arm is the current production
path: the same canonical chain at the manifest's production scale, per
docs/process/measurement-frame.md ("The production path is capture,
fit_captured(rings, K), integer charstring in font units"). Only K differs
between arms; rdp_epsilon, fit_squared_error and fit_max_refits are the
manifest values in both.

Comparability caveat (measurement-frame.md): fitting at scale 1 rounds to
whole tile pixels and gives a different outline; IoU rows of the two arms are
each rendered in their own K frame back into the same 1485x1050 scan canvas at
threshold 128, so the scan-domain IoU comparison is same-canvas/same-threshold,
while the fit-error budget is not pixel-matched across arms: 0.25 fu^2 is
0.25 px^2 at K=1 versus about 0.0855 px^2 at K=1.7100183991006373 (production
fits about 2.9x tighter in pixel terms). This asymmetry, not K alone, drives
most of the fit_error difference.

## Inputs and pins

- Base tree: tarball kni-repo-5bcdd587 (origin/main 5bcdd5879aa7cc1d4497a5ccf0a3444c78555925).
- Harness (new file, additive): engine/core/examples/canonical_path_run.rs.
- Manifest: engine/manifest-full-478.tmpl (population_sha256 bdc4048d04a6b3d36fddd5c6e77e864250bd48c99c4142d961b2d5407815f61f; scale 1.7100183991006373; rdp_epsilon 0.25; fit_squared_error 0.25; fit_max_refits 8; upm 1000; 253 glyph rows). Manifest keys not consumed by the harness are ledgered in ledger.tsv (no silent drops).
- Tiles: Google Drive folder "kni-kit/collection/Karl Nawrot Typefaces/Marq/Alternate/glyph" (folder id 1bOp-n8j-Bh619QXOk_kJ5do1JlKyBYnJ), 478 files listed, all 253 manifest tiles present; each downloaded file's sha256 matches its filename fragment; every tile is a 1485x1050 PNG. Tiles are not in repo custody.
- Invocation (run twice, identical output): `cargo run --release -p kni-core --example canonical_path_run -- manifest-full-478.tmpl <TILEDIR> <OUTDIR> 128 32 0.25 268435456` (threshold 128, flatten_steps 32, flatten tolerance 0.25 px, working cap 268435456 bytes; all explicit CLI inputs, no harness-owned numeric constants).

## Measured summary (253 glyphs; per-glyph rows in measurements.tsv)

| metric | canonical_k1 (K=1) | production (K=1.7100183991006373) |
|---|---|---|
| scan-domain IoU mean / median / p5 / min | 0.985097 / 0.986185 / 0.974994 / 0.903676 | 0.989811 / 0.990128 / 0.982315 / 0.960904 |
| segments total / mean / median | 6945 / 27.5 / 25 | 7047 / 27.9 / 25 |
| fit error sfe px^2 mean | 0.124240 | 0.067987 |
| fit error maxdev px mean / worst | 1.1152 / 1.8252 | 0.9323 / 1.2838 |
| glyphs with fallback spans | 73 | 112 |
| dropped rings | 0 | 0 |
| container refusals (glyphs) | 7: percent, comma, exclamdown, quotesinglbase, quotedblbase, perthousand, uni2078 | 2: percent, perthousand |

Per-glyph deltas (production minus canonical_k1): IoU mean +0.004714
(min -0.013364, max +0.075206; canonical_k1 beats production on 28 glyphs);
segments mean +0.40 (min -16, max +16).

## Byte diff

- Per-glyph charstrings: 246 of 253 differ, 0 identical, 7 not assessable
  (container refusals; typed n/a). Differing-byte count mean 216.8, median
  167, max 998. First difference is at offset 5 on differing glyphs (first
  move delta, i.e. geometry, not header).
- Whole-font CFF (notdef + container-accepted glyphs, manifest order):
  canonical-k1.otf 85255 bytes, 247 glyphs, sha256
  f4f0cb0605a319cc08ec94487b15a698202511941248b3aed1b430e3cdd934de;
  production.otf 89696 bytes, 252 glyphs, sha256
  661fbf5a90de9cca2c951d2cf44f7afaacde3d1db20d5e592039a6d35303d1d5.
  Font byte diff: first difference at offset 50, 75374 differing bytes.
  Excluded glyphs are ledgered per arm in ledger.tsv.

## Findings

1. The canonical chain emits outlines the integer container refuses on both
   arms: fit_captured can emit non-integer coordinates (2 glyphs even at the
   production scale, 7 at K=1). The pipeline's rounding reconcile step is not
   part of the canonical chain; the refusals name the exact glyphs where the
   chain alone cannot reach an integer charstring.
2. K=1 costs IoU on average (-0.0047 mean) and fit error (sfe mean about
   1.83x production), with a long tail (min IoU 0.9037 vs 0.9609); segment
   counts are near parity (mean -0.4). 28 glyphs measure better at K=1.
3. Zero dropped rings and zero harness errors across 253 glyphs; every
   refusal is a typed row.

## Repeatability and writer-run evidence

- Two independent invocations: measurements.tsv, ledger.tsv, fonts.tsv,
  canonical-k1.otf, production.otf byte-identical (cmp). measurements.tsv
  sha256 bc57cccb2f985d9684194ba6b959ef38010ed4c5590137cdd8c57cfc59f174bd.
- kni-core (the only touched crate): cargo test --release: 809 passed,
  0 failed, 2 ignored (72 test targets).
- cargo check --workspace --release: 0 warnings.
- rustc 1.99.1 (58cf8f9c3 2026-10-13), Linux x86_64 sandbox.

## Method notes and caveats

- The measured outline is the integer outline handed to the container. The
  charstring writer accepts exact-integer coordinates only, so for accepted
  glyphs the encoded bytes are a faithful delta encoding of the measured
  outline by construction. A direct CffReader readback of cff_one bytes is
  not possible: cff_one emits a bare CFF and CffReader requires a full OTTO
  sfnt (NotOtto). IoU/fit-error rows on refused glyphs are measured on the
  refused rings and flagged in the notes column.
- IoU: ProductionEvaluator rasterizer, per-glyph frame pin
  CAP-<arm>-SCAN128-FITK-CFFINTEGER-RAWORIGIN, canvas 1485x1050, threshold
  128, capture eps 0.25, flatten_steps 32.
- Fit error: symmetric mean squared distance plus max deviation of the
  flattened emitted outline against the capture's raw rings, in px; rings
  align by capture order (fit_captured preserves order; a count mismatch is
  typed unassessable, none occurred).
- Determinism is structural: no threads, no env, no clock in the harness;
  the two-run byte identity is recorded above.
- The manifest comment "owner 23:59 order" and the scale model's
  "owner-final" label are repository-document claims; this run does not rely
  on them as authority, only as input data.
- The full-set run is repeatable by the integrator on any machine with the
  same tiles (Drive folder above) and the pinned invocation.
