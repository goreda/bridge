# W2-5 engine-wide literal inventory (12' list #9)

LATEST WAVE: wave 2, base goreda/kni HEAD `38f506e3cddf98d82ded8f80bb2a7bcac031ba48` (2026-10-18). Wave 1 (base `5bcdd5879aa7cc1d4497a5ccf0a3444c78555925`) is kept below as the historical record.

## Wave 2 (2026-10-18, HEAD 38f506e3): ledger refreshed to HEAD, generator committed

READ-ONLY inventory wave on engine code: no engine source changed. Added files: `tooling/literal_inventory.py` (the generator, previously uncommitted), `tooling/test_literal_inventory.py` (guard tests), refreshed `tooling/literal-inventory-ledger.tsv`, this doc section.

### Generator and parity

`tooling/literal_inventory.py` is a faithful Python port of the canonical scanner `metrics/tests/kern_scope_guard.rs::scan_literals` (comments, strings, char literals, `#[cfg(test)]` items, tuple-index projections, suffix normalization) with per-occurrence line tracking. Parity at HEAD: it reproduces every (file, literal) count in the committed fixture `metrics/tests/fixtures/kern-scope-literals.tsv` (**226 rows, 0 mismatches**). The fixture shrank from wave 1's 268 rows to 226 because the kern-scope code and its fixture moved together between the bases; parity holds at both ends.

Ledger construction at HEAD: count-matched (file, literal) keys carry their wave-1 rows forward with refreshed line numbers (nearest-line monotone alignment); new and count-changed occurrences were typed by reading the code at HEAD, never by blind replacement; stale rows were dropped. 21,101 occurrences carried, 312 typed in wave 2, 21 stale dropped.

### Totals at HEAD 38f506e3

| scope | rows |
|---|---|
| literal occurrences extracted (7 crates) | 21,413 (wave 1: 21,122) |
| trivial (0/1/0.0/1.0), typed `trivial` | 7,248 (wave 1: 7,037) |
| typed non-trivial | 14,165 (wave 1: 14,085) |
| UNCLASSIFIED | 0 |

### Class distribution (non-trivial rows, wave 2)

| class | rows | wave 1 |
|---|---|---|
| test_fixture | 6,626 | 6,626 |
| standard | 4,935 | 4,933 |
| definition | 919 | 892 |
| test_surface | 467 | 467 |
| structural | 325 | 323 |
| convention | 243 | 240 |
| covered:kern-scope-literals | 458 | 449 |
| covered:threshold-inventory | 112 | 112 |
| candidate_font_derived | 63 | 36 |
| candidate_declared | 16 | 7 |

### Wave-2 delta

- Files: `pipeline/src/rounding_reconcile.rs` moved to `core/src/rounding_reconcile.rs` (classes carried per row, move recorded in the row notes); new files `core/src/lattice.rs` (LATTICE-1 prototype, not production-wired; all 86 occurrences typed) and `core/src/master_fit_trace_binding.rs` (trivial literals only).
- New `candidate_font_derived` rows (27 net): the LATTICE-1 prototype gates (`CAND_MIN_CIRCULARITY` 0.75, `MIN_DOT_COUNT` 30, `MIN_DOT_FRACTION` 0.20, `RADIUS_BIN_FRAC` 0.10, `MIN_SPACING_PEAK_SHARE` 0.50, `BASIS_LEN_LO/HI` 0.80/1.25, `MIN_COVERAGE` 0.75, `SNAP_TOL_FRAC` 0.20, bin fractions/floors and support counts), the one-third-chord construction reused in `core/src/fit_search.rs:606/609/696/701` (same class as the existing `closed_fit.rs:25` / `node_objective.rs:144` rows), and `core/src/capture_fit.rs:2319` corner confirm window `3.0 * t_line` (multiple of the font-derived line tolerance).
- New `candidate_declared` rows (9 net): LATTICE-1 declared angular bounds and bin resolutions (`ORTHO_TOL` 0.26 ~ sin(15 deg), 180/72 = 2.5 deg bins, PI/6 and PI/12 filters, spacing/16 u/v bins, 2x far-band escalations) and the carried `rounding_reconcile` identity-rounding bound `4.0 * (EXPORT_RESOLUTION/2)`.
- Declared Paul New metric change: `pipeline/src/declared_convention.rs` descender record 150 -> 145 (the `PAUL_NEW_DESCENDER_UNITS -145` constant) and new `pipeline/src/paul_new_anchor.rs` rows `1000.0` (em-box height, K_Y anchor) and `1.0` (`PAUL_NEW_EDGE_OVERHANG_UNITS`). Typed `convention`, style-specific declared metrics. The module comments cite owner directives of 2026-10-18 03:06/03:37 (iMessage); those comments are unverified provenance claims, while the -145 descender and -1 edge-overhang values themselves are corroborated by indexed owner messages.
- `metrics/src` and `learning/src` changes are pinned by the kern-scope fixture at HEAD (parity above), so the affected ledger rows stay `covered:kern-scope-literals:<class>` with the fixture's note (`side_classes.rs` 0.5 x4 convention, 2 x7 definition; `self_anchored_spacing.rs` 2.0 x28; `anchor_audit.rs` trivial additions).
- `pipeline/src/main.rs:1071/1084` literal 2: OpenType hhea/hmtx record layout, typed `standard`.
- `core/src/economy.rs:119` `ECONOMY_IOU_LOSS_GATE` 0.002: typed `convention` (declared gate tolerance; derivation doc cited in the module comment).
- `core/src/curve_stress.rs:72` `ISO_INK_LEVEL` 0.5 and `:77` 255.0 x2: typed `definition` (8-bit ramp midpoint / 8-bit white normalisation).
- `core/src/lever_api.rs` 128 x4 new occurrences: typed `definition` (mid-grey binarisation, same class as the existing row).

### Guard state at HEAD 38f506e3

- `cargo test -p kni-metrics --tests` in the repo layout: all suites green, including `kern_scope_guard` (fixture matches code) and `kern_constants_guard`. Note: `kern_constants_guard.rs` resolves engine paths two levels above `CARGO_MANIFEST_DIR` (repo layout `<root>/engine/metrics`); in a repacked subtree export it fails on path resolution, an export-layout artifact, not a code regression.
- `tooling/check_bare_thresholds.py`: **6,839 violations** at HEAD (wave-1 base: 6,833; +6). Still dominated by the `core/src/capture.rs` BOMB zlib test vectors and PNG region; the engine-wide ledger types all of these occurrences (test_fixture / standard). Pre-existing red, unchanged in character.
- `tooling/test_literal_inventory.py`: 7 tests (scanner self-check against the Rust scanner's expected counts, kern-scope parity, ledger vocabulary/meaning invariants, ledger-vs-HEAD freshness). Run: `python3 -m unittest tooling.test_literal_inventory`.

### FORMAL approach (owner order 2026-10-18 16:09)

The owner ordered one general rule set: no language-specific, glyph-specific or style-specific settings or code. This wave is the audit lane, so no code was removed or generalized here; the ledger already types the style-specific literals as style-specific declared metrics (`paul_new_anchor.rs`, `paul_new_metrics_policy.rs`, `declared_convention.rs` Paul New records) so the architecture owner can find every one of them from this ledger. Wave-2 delta literals are language-agnostic and glyph-agnostic; no per-language code appeared. Removal/generalization of the style-specific constants is cross-item work and must be coordinated through the architect.

## Wave 1 (base 5bcdd587): original read-only inventory

READ-ONLY inventory wave: no code changed. Base: origin/main `5bcdd5879aa7cc1d4497a5ccf0a3444c78555925`.

Companion ledger: `tooling/literal-inventory-ledger.tsv` (one row per literal occurrence: crate, file, line, literal, class, meaning/proposal). Every extracted literal is typed; there are no UNCLASSIFIED rows and nothing was dropped silently.

## Method and extraction parity

Literals were extracted with a faithful port of the repo's canonical scanner `metrics/tests/kern_scope_guard.rs::scan_literals` (skips comments, strings, char literals, `#[cfg(test)]` items, tuple-index projections; normalizes suffixes). Parity check: the port reproduces every (file, literal) count in the committed fixture `metrics/tests/fixtures/kern-scope-literals.tsv` (268 rows) with **0 mismatches**, so the engine-wide extraction runs on the same acceptance basis as the existing kern-scope guard.

Trivial literals are the kern-guard TRIVIAL set {0, 1, 0.0, 1.0}: they are typed `trivial` (identity/zero element) rather than exempted silently.

## Totals

| scope | rows |
|---|---|
| literal occurrences extracted (7 crates) | 21,122 |
| trivial (0/1/0.0/1.0), typed `trivial` | 7,037 |
| typed non-trivial | 14,085 |
| UNCLASSIFIED | 0 |

Crates scanned: core, metrics, learning, pipeline (workspace) plus master, geometry-prototypes, guide-binding (non-workspace).

## Class definitions

- `standard` - value fixed by an external spec (OpenType/sfnt, Unicode, PNG/zlib, FNV-1a, PostScript). No engine policy to derive; the justification is the spec.
- `definition` - the literal is the definition of the operation (halving, midpoint/median, squared distance, 2*PI wrap, 8-bit white). Nothing to derive.
- `structural` - arity/index/grammar of data structures and receipt vocabulary (field counts, bbox indices, span-record shapes). Not a threshold.
- `convention` - DECLARED_CONVENTION: declared resource budget, cadence, placeholder, or slack multiplier; justification recorded per row.
- `test_fixture` / `test_surface` - test-only values (expected vectors, fixture data) and test-harness surfaces.
- `covered:threshold-inventory` - already pinned by `tooling/threshold-inventory.tsv` + `tooling/check_bare_thresholds.py`.
- `covered:kern-scope-literals:<cls>` - already pinned by the kern-scope fixture (268 rows) under its own class.
- `candidate_font_derived` - the remaining policy literals: each carries a concrete font-derived replacement proposal.
- `candidate_declared` - policy literal whose correct treatment is a DECLARED_CONVENTION record, not a derivation.

## Class distribution (non-trivial rows)

| class | rows |
|---|---|
| test_fixture | 6,626 |
| standard | 4,933 |
| definition | 892 |
| test_surface | 467 |
| structural | 323 |
| convention | 240 |
| covered:kern-scope-literals (definition/allowlist-fips/format/convention/derived/open) | 449 |
| covered:threshold-inventory | 112 |
| candidate_font_derived | 36 |
| candidate_declared | 7 |

## Pre-existing guard state on base 5bcdd587

`tooling/check_bare_thresholds.py` on the base reports **6,833 violations**: 6,752 are the BOMB zlib test vectors at `core/src/capture.rs:668-671` and 81 in the capture.rs PNG region (lines 153-338). This red predates this wave; the new engine-wide ledger types all of these occurrences (test_fixture / standard). No code was changed, so the guard state is unchanged by this wave.

## Per-module replacement proposals (candidates)

The 43 candidate rows with their proposals (full text in the ledger):

### core/core

| file:line | literal | class | proposal |
|---|---|---|---|
| `core/src/capture_fit.rs:2676` | `0.25` | candidate_declared | curvature-ratio equalization exponent 1/4 (fourth-root damping of the handle move): heuristic with inline rationale comments; proposal: DECLARED_CONVENTION with derivation, or derive the damping from measured curvature-gap distributions |
| `core/src/capture_fit.rs:2734` | `0.02` | candidate_declared | bowed-straight-edge sagitta ratio 2% of chord (inline doc); proposal: DECLARED_CONVENTION with derivation, or derive from the style straightness evidence |
| `core/src/capture_fit.rs:4232` | `6.0` | candidate_declared | straight-sweep conversion: a cubic >= 6 px long with both control sagittae <= 1 px emits a Line (STRAIGHT_SWEEP counters); proposal: DECLARED_CONVENTION with derivation, or derive the length multiple from t_line |
| `core/src/closed_fit.rs:25` | `2` | candidate_font_derived | line-approximation handle length chord/3 (one-third-chord heuristic, same rule as node_objective fallback); proposal: DECLARED_CONVENTION with provenance or style-derived handle ratios |
| `core/src/closed_fit.rs:25` | `3` | candidate_font_derived | line-approximation handle length chord/3 (one-third-chord heuristic, same rule as node_objective fallback); proposal: DECLARED_CONVENTION with provenance or style-derived handle ratios |
| `core/src/master_fit_context.rs:66` | `0.1` | candidate_declared | end-tangent estimator lookahead fraction 0.1 of the segment (min 1 sample; inline doc); proposal: DECLARED_CONVENTION with derivation, or derive from segment sample density |
| `core/src/node_objective.rs:144` | `3.0` | candidate_font_derived | fallback handle length = chord/3 when the least-squares solve degenerates: the common one-third-chord convention; proposal: DECLARED_CONVENTION with provenance (one-third rule) or derive from adjacent measured handle ratios of the style |
| `core/src/node_objective.rs:144` | `3.0` | candidate_font_derived | fallback handle length = chord/3 when the least-squares solve degenerates: the common one-third-chord convention; proposal: DECLARED_CONVENTION with provenance (one-third rule) or derive from adjacent measured handle ratios of the style |
| `core/src/reference_transfer.rs:53` | `0.0871557427476582` | candidate_font_derived | TransferConfig defaults: smooth_sin = sin(5 deg) (inline rationale), max_node_dist = 0.1 and max_ring_cost = 0.25 in normalised units; proposal: declare as DECLARED_CONVENTION with provenance, or derive match radii from ring scale (normalised area / centroid spread of the style) |
| `core/src/reference_transfer.rs:53` | `0.1` | candidate_font_derived | TransferConfig defaults: smooth_sin = sin(5 deg) (inline rationale), max_node_dist = 0.1 and max_ring_cost = 0.25 in normalised units; proposal: declare as DECLARED_CONVENTION with provenance, or derive match radii from ring scale (normalised area / centroid spread of the style) |
| `core/src/reference_transfer.rs:53` | `0.25` | candidate_font_derived | TransferConfig defaults: smooth_sin = sin(5 deg) (inline rationale), max_node_dist = 0.1 and max_ring_cost = 0.25 in normalised units; proposal: declare as DECLARED_CONVENTION with provenance, or derive match radii from ring scale (normalised area / centroid spread of the style) |

### master/master

| file:line | literal | class | proposal |
|---|---|---|---|
| `master/src/model.rs:77` | `0.25` | candidate_font_derived | contour close-gap tolerance 0.25 fu before an explicit closing Line is emitted; proposal: derive from the integer rounding quantum of the output grid, or DECLARED_CONVENTION with derivation |

### pipeline/pipeline

| file:line | literal | class | proposal |
|---|---|---|---|
| `pipeline/src/main.rs:429` | `0.25` | candidate_font_derived | manifest CLI defaults (rdp 0.25 px, fit_se 0.25, refits 8, flat_tol 0.5, row_step 10.0, max_rows 1000, sample_res 10.0, max_pair_evaluations 1M, max_pairs 10k, min_shared_rows 1): same set as run_config legacy_defaults_input; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/main.rs:430` | `0.25` | candidate_font_derived | manifest CLI defaults (rdp 0.25 px, fit_se 0.25, refits 8, flat_tol 0.5, row_step 10.0, max_rows 1000, sample_res 10.0, max_pair_evaluations 1M, max_pairs 10k, min_shared_rows 1): same set as run_config legacy_defaults_input; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/main.rs:431` | `8` | candidate_font_derived | manifest CLI defaults (rdp 0.25 px, fit_se 0.25, refits 8, flat_tol 0.5, row_step 10.0, max_rows 1000, sample_res 10.0, max_pair_evaluations 1M, max_pairs 10k, min_shared_rows 1): same set as run_config legacy_defaults_input; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/main.rs:433` | `0.5` | candidate_font_derived | manifest CLI defaults (rdp 0.25 px, fit_se 0.25, refits 8, flat_tol 0.5, row_step 10.0, max_rows 1000, sample_res 10.0, max_pair_evaluations 1M, max_pairs 10k, min_shared_rows 1): same set as run_config legacy_defaults_input; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/main.rs:434` | `10.0` | candidate_font_derived | manifest CLI defaults (rdp 0.25 px, fit_se 0.25, refits 8, flat_tol 0.5, row_step 10.0, max_rows 1000, sample_res 10.0, max_pair_evaluations 1M, max_pairs 10k, min_shared_rows 1): same set as run_config legacy_defaults_input; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/main.rs:435` | `1000` | candidate_font_derived | manifest CLI defaults (rdp 0.25 px, fit_se 0.25, refits 8, flat_tol 0.5, row_step 10.0, max_rows 1000, sample_res 10.0, max_pair_evaluations 1M, max_pairs 10k, min_shared_rows 1): same set as run_config legacy_defaults_input; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/main.rs:436` | `10.0` | candidate_font_derived | manifest CLI defaults (rdp 0.25 px, fit_se 0.25, refits 8, flat_tol 0.5, row_step 10.0, max_rows 1000, sample_res 10.0, max_pair_evaluations 1M, max_pairs 10k, min_shared_rows 1): same set as run_config legacy_defaults_input; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/main.rs:437` | `1000000` | candidate_font_derived | manifest CLI budgets (max_pair_evaluations 1M, max_pairs 10k): declared resource caps; proposal: keep as DECLARED_CONVENTION resource budget, not a font threshold |
| `pipeline/src/main.rs:440` | `10000` | candidate_font_derived | manifest CLI budgets (max_pair_evaluations 1M, max_pairs 10k): declared resource caps; proposal: keep as DECLARED_CONVENTION resource budget, not a font threshold |
| `pipeline/src/main.rs:844` | `100` | candidate_font_derived | post underline position/thickness placeholders at UPM-1000 fractions; proposal: derive from units_per_em (-0.1*upm, 0.05*upm) |
| `pipeline/src/main.rs:844` | `4` | candidate_font_derived | post underline position/thickness placeholders at UPM-1000 fractions; proposal: derive from units_per_em (-0.1*upm, 0.05*upm) |
| `pipeline/src/main.rs:844` | `50` | candidate_font_derived | post underline position/thickness placeholders at UPM-1000 fractions; proposal: derive from units_per_em (-0.1*upm, 0.05*upm) |
| `pipeline/src/main.rs:1620` | `100` | candidate_font_derived | post underline position/thickness placeholders at UPM-1000 fractions; proposal: derive from units_per_em (-0.1*upm, 0.05*upm) |
| `pipeline/src/main.rs:1620` | `4` | candidate_font_derived | post underline position/thickness placeholders at UPM-1000 fractions; proposal: derive from units_per_em (-0.1*upm, 0.05*upm) |
| `pipeline/src/main.rs:1620` | `50` | candidate_font_derived | post underline position/thickness placeholders at UPM-1000 fractions; proposal: derive from units_per_em (-0.1*upm, 0.05*upm) |
| `pipeline/src/rounding_reconcile.rs:114` | `2.0` | candidate_declared | identity-rounding bound = 4.0 * (EXPORT_RESOLUTION/2): multiplier 4 over the half export quantum; proposal: DECLARED_CONVENTION with derivation (why 4 half-quanta), or derive from the export grid directly |
| `pipeline/src/rounding_reconcile.rs:114` | `4.0` | candidate_declared | identity-rounding bound = 4.0 * (EXPORT_RESOLUTION/2): multiplier 4 over the half export quantum; proposal: DECLARED_CONVENTION with derivation (why 4 half-quanta), or derive from the export grid directly |
| `pipeline/src/run_config.rs:100` | `2.4377` | candidate_declared | default_units_per_px = 2.4377: a declared fallback default with no recorded derivation; proposal: bind to the OwnerDeclaredScaleSet declared scale (K) instead of a free float; until then DECLARED_CONVENTION with provenance note required |
| `pipeline/src/run_config.rs:163` | `0.25` | candidate_font_derived | legacy manifest defaults: rdp_epsilon 0.25 px, fit_squared_error 0.25, fit_max_refits 8, flatten_tolerance 0.5, scan_row_step 10.0, scan_max_rows 1000, sample_resolution 10.0, max_pairs 10k, max_pair_evaluations 1M; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; refit and pair budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/run_config.rs:163` | `0.25` | candidate_font_derived | legacy manifest defaults: rdp_epsilon 0.25 px, fit_squared_error 0.25, fit_max_refits 8, flatten_tolerance 0.5, scan_row_step 10.0, scan_max_rows 1000, sample_resolution 10.0, max_pairs 10k, max_pair_evaluations 1M; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; refit and pair budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/run_config.rs:163` | `8` | candidate_font_derived | legacy manifest defaults: rdp_epsilon 0.25 px, fit_squared_error 0.25, fit_max_refits 8, flatten_tolerance 0.5, scan_row_step 10.0, scan_max_rows 1000, sample_resolution 10.0, max_pairs 10k, max_pair_evaluations 1M; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; refit and pair budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/run_config.rs:164` | `0.5` | candidate_font_derived | legacy manifest defaults: rdp_epsilon 0.25 px, fit_squared_error 0.25, fit_max_refits 8, flatten_tolerance 0.5, scan_row_step 10.0, scan_max_rows 1000, sample_resolution 10.0, max_pairs 10k, max_pair_evaluations 1M; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; refit and pair budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/run_config.rs:164` | `10.0` | candidate_font_derived | legacy manifest defaults: rdp_epsilon 0.25 px, fit_squared_error 0.25, fit_max_refits 8, flatten_tolerance 0.5, scan_row_step 10.0, scan_max_rows 1000, sample_resolution 10.0, max_pairs 10k, max_pair_evaluations 1M; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; refit and pair budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/run_config.rs:164` | `10.0` | candidate_font_derived | legacy manifest defaults: rdp_epsilon 0.25 px, fit_squared_error 0.25, fit_max_refits 8, flatten_tolerance 0.5, scan_row_step 10.0, scan_max_rows 1000, sample_resolution 10.0, max_pairs 10k, max_pair_evaluations 1M; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; refit and pair budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/run_config.rs:164` | `1000` | candidate_font_derived | legacy manifest defaults: rdp_epsilon 0.25 px, fit_squared_error 0.25, fit_max_refits 8, flatten_tolerance 0.5, scan_row_step 10.0, scan_max_rows 1000, sample_resolution 10.0, max_pairs 10k, max_pair_evaluations 1M; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; refit and pair budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/run_config.rs:165` | `10000` | candidate_font_derived | legacy manifest defaults: rdp_epsilon 0.25 px, fit_squared_error 0.25, fit_max_refits 8, flatten_tolerance 0.5, scan_row_step 10.0, scan_max_rows 1000, sample_resolution 10.0, max_pairs 10k, max_pair_evaluations 1M; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; refit and pair budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/run_config.rs:165` | `1000000` | candidate_font_derived | legacy manifest defaults: rdp_epsilon 0.25 px, fit_squared_error 0.25, fit_max_refits 8, flatten_tolerance 0.5, scan_row_step 10.0, scan_max_rows 1000, sample_resolution 10.0, max_pairs 10k, max_pair_evaluations 1M; proposals: px-domain tolerances derive from the declared scale K (units_per_px); row pitch / sample resolution derive from measured stem/row structure; refit and pair budgets are declared resource caps (DECLARED_CONVENTION) |
| `pipeline/src/spacing_oohh.rs:46` | `0.8` | candidate_font_derived | OO/HH spacing class policy: cover 0.8, flat 0.9, min 4 class pairs, max move 50% of target; proposals: derive cover/flat fractions and min class support from measured pair-class evidence of the font, or declare as DECLARED_CONVENTION with derivations |
| `pipeline/src/spacing_oohh.rs:53` | `0.9` | candidate_font_derived | OO/HH spacing class policy: cover 0.8, flat 0.9, min 4 class pairs, max move 50% of target; proposals: derive cover/flat fractions and min class support from measured pair-class evidence of the font, or declare as DECLARED_CONVENTION with derivations |
| `pipeline/src/spacing_oohh.rs:57` | `4` | candidate_font_derived | OO/HH spacing class policy: cover 0.8, flat 0.9, min 4 class pairs, max move 50% of target; proposals: derive cover/flat fractions and min class support from measured pair-class evidence of the font, or declare as DECLARED_CONVENTION with derivations |
| `pipeline/src/spacing_oohh.rs:64` | `0.5` | candidate_font_derived | OO/HH spacing class policy: cover 0.8, flat 0.9, min 4 class pairs, max move 50% of target; proposals: derive cover/flat fractions and min class support from measured pair-class evidence of the font, or declare as DECLARED_CONVENTION with derivations |

## DECLARED_CONVENTION justifications

The 240 `convention` rows carry per-row justifications in the ledger. By theme: declared_convention.rs records (111) - the registry of declared conventions itself; main.rs budgets and markers (45) - PNG_DECODE_LIMITS / pipeline Limits, UPM 1000 defaults, stage markers (inline-documented CONVENTION), metadata placeholders overwritten before emission (xAvgCharWidth 500), worker stack budget, pulse cadence; tail_refine handle ceilings (11); capture_fit slack windows and sampling resolutions (9); notdef_caller budgets (7); node_objective epsilons (7, one inline-documented DECLARED CONVENTION); capture.rs decode limits (7); bound_detector_validator budget weights (6); sampling resolutions in master/check.rs (4); assorted reporting caps and budget formulas.

## Notes for the next wave

- `paul_new_anchor.rs` / `paul_new_metrics_policy.rs` constants (incl. PAUL_NEW_K_X_BITS, value 696 in related rows): verify provenance against the owner-stated Paul New declared metrics (height 700, space/notdef 489) before any replacement; flagged, not asserted.
- Repo files claiming "owner directive" provenance (e.g. ENGINE-SKELETON-MINIMUM-RULES.md) are recorded as unverified provenance claims; no action taken on them.
- This wave introduces no new numeric literals; the two added files are documentation/data only.
