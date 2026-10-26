# Unified typed ledger schema (conc)

One row per line, LF endings, exactly four TAB-separated fields. Blank
lines are tolerated and skipped by the checker:

    stage <TAB> code <TAB> subject <TAB> reason

- `stage`: snake_case pipeline stage identifier (`stage1_fit`, `profiles`,
  `spacing`, `kern`, `export`, `notdef`, `run`). Free-form within
  `^[a-z][a-z0-9_]*$`; new stages need no registry entry.
- `code`: snake_case typed code from the registry below. The registry is the
  controlled vocabulary; a row with an unregistered code fails the gate until
  the registry is updated in the same diff.
- `subject`: what the row is about - a glyph name, a pair, a ring id, a
  policy id, or `run` / `policy` for whole-run rows. Non-empty, no leading
  or trailing whitespace.
- `reason`: non-empty single-line free text. No TAB or LF inside.

## Receipt summary equivalent

Counter rows derived only from the ordered ledger rows, after the existing
`glyph_exclusions_total` pattern:

    <code>_total <TAB> N
    <code>_total <TAB> N <TAB> note

`N` is a non-negative integer. A summary row never carries information that
is not derivable from the ledger rows it summarizes.

## Scope (architect decision)

The gate applies to typed-flag ledger files and receipts only:

- typed-flag ledgers: `fallback-glyphs.tsv`, `*drop-ledger*`, `ring_skip*`,
  and warning-coded ledger files emitted by lanes;
- receipts: `receipt-*.txt` and `run-failure-receipt.txt` (checked for
  their typed rows and key-value variants).

Columnar data tables are OUT OF SCOPE and skipped by the checker:
`kern-ledger.tsv`, `kern-diagnostic.tsv`, `spacing-pair-ledger.tsv`,
`mapping.tsv`, `profile-metadata.tsv`, `spacing.tsv`,
`post_metrics_ledger.tsv`, plus run artifacts (`rounding-ledger.txt`,
`run-provenance.tsv`, `REPORT.txt`, `spacing-hold-reasons.txt`,
`stage1-cache.txt`). Files matching neither list are checked by default, so
a lane's new ledger file is validated without a scope-table update.

## Code registry (initial)

| code | lane | meaning |
|---|---|---|
| `guard_degrade` | G2 | ambiguity guard degraded; typed exclusion emitted |
| `stem_pair_overflow` | G3 | stem-pair measurement overflow / root-cause row |
| `ring_exclusion` | MARQ-DEGEN | ring excluded from fitting, with reason |
| `cadence_unobserved` | W3 (B) | cadence policy fell back to the UnobservedPolicy |
| `fallback_span` | W17 | per-glyph fallback span ledger row (glyph, spans, region) |
| `fallback_export_gate` | W6 | ship gate decision row for the fallback export path |
| `containment_compensation` | containment | post-solve containment pair-frame compensation summary; shifted pairs pushed below zero origin ship as legal GPOS negative XAdvance when measured tangent/clean and cut at the tangent (gap = 0) with a typed `export_adjusted` kern-ledger row on a real collision; only unmeasurable or unverifiable cases are held with the typed reason `containment_compensation_negative_origin` |
| `speck_retained` | stage1 | sub-pixel capture ring retained as its own measured minimal contour; append-only counter of the live stage1 pass |
| `speck_dropped` | stage1 | grid-unrepresentable capture dropped; append-only counter |

## Counter semantics (append-only)

A registered code or kv head is append-only: its meaning never changes in
place. A counter whose meaning changes takes a new name; the old name keeps
its recorded meaning and stays queryable for old receipts.

## Documented variants (accepted)

Architect decision: the three formats already emitted by the tree are
ACCEPTED as documented variants, not rejected. The checker classifies
matching lines as `variant` (reported separately from violations;
`--strict-legacy` still counts them as violations for migration audits).
New emitters and new rows must use the canonical form above; a variant
pattern with an unrecognized key or code does not pass as a variant.

(a) code-first warning: `code <TAB> value <TAB> subject <TAB> reason` -
    the determinism warning form, e.g.
    `encode_nondeterministic<TAB>true<TAB>policy<TAB>ship_first_encode`
    (pipeline/src/determinism_decide.rs). Four TAB fields, code in field
    one, value in field two.
(b) receipt three-field: `key <TAB> value <TAB> text` - the export_intent
    and fallback_ledger_total receipt rows. Carries no stage field.
(c) pair ledger without stage: the fallback-glyphs.tsv form, header
    `glyph<TAB>spans` plus `name<TAB>N` rows. Carries no stage, code, or
    reason field; W17's `fallback_span` canonical rows supersede it for new
    emitters. Context-bound: the pattern is a variant ONLY inside a file
    named `fallback-glyphs.tsv` or after the file's own `glyph<TAB>spans`
    header; a bare `name<TAB>N` row anywhere else is a violation, so
    unrelated two-column numeric tables are not swallowed.

Counter rows that predate the summary rule and match the summary shape
(`glyph_exclusions_total`, `glyph_skip_total`) classify as `summary`; the
non-`_total` counters (`glyph_exclusions_intentional_empty`,
`glyph_exclusions_failures`) classify as `variant`.

(d) receipt key-value rows (architect decision): inside `receipt-*.txt`
    and `run-failure-receipt.txt` files, a row whose first field is a
    REGISTERED kv head word is the accepted variant for the current
    receipt format, subject to three tightening rules:

    - KV_ARITY: the field count must be one of the head's registered
      arities (the N column below; RECEIPT_KV_ARITY in ledger_check.py,
      kept in sync with the head registry by the checker's self-test).
      A deleted, inserted, or duplicated field breaks the arity and
      fails. `warning` rows accept the emitter-derived set
      3/4/5/6/7/8/9/12/14.
    - KV_BAD_VALUE: a whole field equal to `nan`, `inf`, `-inf`, or
      `+inf` (any case) fails on ANY receipt line, before the variant
      patterns. Real fit fields carry the word `infinity`, which stays
      legal.
    - KV_BLANK_FIELD: an empty or whitespace-padded field fails. Summary
      and counter notes, when present, must be non-empty.
    - KV_GRAMMAR: for the grammared heads (glyph, glyph_segments,
      scale_status, spacing, kern, vertical) the row must also match the
      per-head field grammar (RECEIPT_KV_GRAMMAR in ledger_check.py): the exact ordered
      field-name sequence and a value type per position (bool, int,
      float, hex16, hash64, codepoint, WxH pixel size, snake_case,
      CamelCase, UPPER-token, or free text). Grammars are derived from
      the emitter literals and verified against real receipts; a shape
      applies only at its registered arity, and heads without a grammar
      keep the registry-only checks. A reordered key, a clobbered field
      name, or a value of the wrong type fails.

    Canonical rows in the same file still classify `ok` because
    registered codes win. A row with an unregistered head fails as
    `UNREGISTERED_KV_HEAD`; the diff that adds a new receipt emitter
    extends the registry (and the arity table) in the same diff.

    Known limitations (mutation-tested, listed for the architect): for
    rows OUTSIDE the five grammared heads, reordering fields inside a
    same-arity kv row, swapping a row's head for another registered head
    of the same arity, and garbage appended to a numeric value stay
    structurally indistinguishable from valid rows; a stage typo in a
    canonical row (the stage vocabulary is open) and arity-preserving
    field deletes on multi-arity heads are also undetectable. The field
    grammar closes the reorder, head-swap, and garbage classes for every
    head it covers: the mutation test treats those as must-catch and
    fails on any escape. Extending the grammar to the remaining heads
    closes the rest; the per-head emitter literal is the only input
    needed. tools/conc/ledger_mutation_test.py pins the boundary: every
    catchable mutation class fails, the rest is reported as known
    escapes.

    The head registry is derived from the receipt emitter source, not
    invented: every head below was extracted from real receipt output and
    verified against the code that writes it. N is the physical
    tab-separated field count of an emitted row, counted from the actual
    emitted row text, never derived from a named-field list. Field-name
    lists per row type follow, with emitter provenance (`<...>` = value
    position):

    | head | N | field-name list | emitter |
    |---|---|---|---|
    | glyph | 24 | glyph, subject, cp, source_pin, source_kind, source_px, scale, route, rings, nodes, final_area, final_missing_extrema, refused | pipeline/src/main.rs |
    | fallback | 4 | fallback, subject, line_spans, count | pipeline/src/main.rs |
    | classification | 14/16/22 | classification, kind, decision_basis, pixel_form_sha256, kind, space_binding, advance_basis(, advance, lsb, rsb, source_sha256), placeholder_cp_count | pipeline/src/main.rs, notdef_proxy.rs |
    | scale_status | 14/30 | scale_status, convention literal (DECLARED_CONVENTION at 30 / CONFIG_CONVENTION at 14), calibrated, convention, k_bits, h_ink_height_px, h_ink_units, em_px (DECIMAL: 473.5 valid, never int-pinned), em_source, basis, cross_frame_reuse, h_source_pin, scale_id, cohort, frame, context_basis (the last four plus scale_id form the 14-field shape) | pipeline/src/scale_wiring.rs, declared_convention.rs |
    | glyph_segments | 18 | glyph_segments, subject, line, cubic, cubic_pct, g1, corner, corner_per_node, chord_len, len_per_node | pipeline/src/main.rs (proposed: docs/conc/receipt-segment-metrics-proposal.md; emitter pending) |
    | spacing | 35 | spacing, complete, excluded_pairs, excluded_self, excluded_below_epsilon, excluded_unmeasurable, numeric_failed_pairs, geometric_hold_pairs, no_accepted_candidate_pairs, fallback_natural_clear_pairs, ... | pipeline/src/main.rs |
    | kern | 15 | kern, ready, overlap_held, rejected, dropped_zero, clamps_refused, solution_complete, fallback_guard_verified | pipeline/src/main.rs |
    | vertical | 15 | vertical, baseline_in, shift, residual, exported_baseline, x_height, cap_height, convention | pipeline/src/main.rs |
    | export_guard | 13 | export_guard, guard_stage, guard_result, approved_base_sha256, guard_policy, context_binding, run_config_sha256 | pipeline/src/main.rs |
    | warning | 3/4/5/6/7/8/9/12/14 | warning, code, excluded_pairs, numeric_failed_pairs, geometric_hold_pairs, no_accepted_candidate_pairs, degrade | pipeline/src/main.rs, ink_containment.rs |
    | post_metrics | 11 | post_metrics, lsb_add, rsb_add, applied, units, scope_origin | pipeline/src/main.rs, post_metrics.rs |
    | kern_drop_total | 11 | kern_drop_total, overlap_hold, clamp_refused, rejected_unbound, dropped_zero, closed | pipeline/src/main.rs |
    | kern_drop | 4 | kern_drop, subject (pair A->B), reason_code, code | pipeline/src/main.rs (kern_drop_ledger; appended into the receipt) |
    | kern_drop | 4 | kern_drop, subject (pair A->B), reason_code, code | pipeline/src/main.rs (kern_drop_ledger; appended into the receipt) |
    | post_pass_applied_unapproved_base | 10 | head, applied, code, lsb_add, rsb_add, reason | pipeline/src/main.rs |
    | png_decode_limits | 9/13 | png_decode_limits, max_input_bytes, max_pixels, max_working_bytes, origin | pipeline/src/main.rs |
    | vertical_height_source | 9 | vertical_height_source, x_height, cap_height, measurements, note | pipeline/src/main.rs |
    | notdef | 7 | notdef, gid, rings, advance | pipeline/src/main.rs |
    | space_advance_source | 3/7 | space_advance_source, status(, cp, advance, note) | pipeline/src/space_evidence.rs |
    | glyph_skip | 6/8 | glyph_skip, subject, cp, reason | pipeline/src/main.rs |
    | otf | 6 | otf, path, bytes, sha256 | pipeline/src/main.rs |
    | name_readback | 5 | name_readback, id, value | pipeline/src/main.rs |
    | notdef_classification | 5 | notdef_classification, stage, advance_basis | pipeline/src/main.rs |
    | assembly_space_glyph | 5 | assembly_space_glyph, emitted, source, note | pipeline/src/main.rs |
    | run_config | 3/5 | run_config, key, value(, unit, note) | pipeline/src/run_config.rs |
    | iou_report | 4 | iou_report, status, reason | pipeline/src/main.rs |
    | partial_output | 4/5/6 | partial_output, flag, reason(, degrade, detail) | pipeline/src/main.rs |
    | space_status | 4/6 | space_status, status, solver_space_glyph_emitted | pipeline/src/main.rs |
    | xavgcharwidth | 4 | xavgcharwidth, value, derived_after_hmtx | pipeline/src/main.rs, post_metrics.rs |
    | hard_fail_unresolved / sub_grid_floor / straight_sweep_converted | 3 | head, count, note | pipeline/src/main.rs |
    | sub_pixel_speck_retained | 10 | sub_pixel_speck_retained, count, area_px2_min, area_px2_max, area_px2_mean, note | pipeline/src/main.rs |
    | postscript_name_sanitized | 3 | head, declared, sanitized | pipeline/src/main.rs |
    | glyph_skip_total | 2/3 | glyph_skip_total, count, note | pipeline/src/fit_reduce.rs |
    | notdef_state | 2/8/10 | notdef_state, status(, evidence_sha256, witnesses, claim) | pipeline/src/bound_detector_validator.rs |
    | two-field rows (manifest_pin, guard_stage, guard_result, approved_base_sha256, context_binding, run_config_sha256, postpass, requested_lsb/rsb, effective_lsb/rsb, scope, final_font_sha256, final_overlap_rechecked, final_overlap_status, guard_policy, post_pass_policy, gap_monotonicity, gap_min_pair_delta, physical_overlap_postpass, baseline_overlap_note, rounding_ledger_basis) | 2 | head, value | pipeline/src/main.rs, post_metrics.rs |

    Conditional-path heads (registered from the emitter source by the
    drift test; absent from successful-run receipts by construction -
    degrade/partial, cache-replay, population-floor, proxy-notdef, and
    per-glyph capture paths):

    | head | N | field-name list | emitter |
    |---|---|---|---|
    | capture | 9 | capture, subject, frame_band_measured_px, cells | pipeline/src/main.rs |
    | guide | 24 | guide, subject, reference_font_sha, reference_pin, E0, E1 | pipeline/src/main.rs |
    | outline_fit | 12 | outline_fit, subject, rings, nodes, final_area, fallback_line_spans, frame | pipeline/src/main.rs |
    | tolerance | 24 | tolerance, subject, provenance, label, norm, rdp_eps_px, rdp_eps_scaled, fit_variance_px2, scale, se_fu2, crossings, step_fraction, input_sha | pipeline/src/main.rs |
    | excluded | 7 | excluded, subject, failure, cp, reason | pipeline/src/main.rs |
    | glyph_exclusions_total / glyph_exclusions_intentional_empty / glyph_exclusions_failures | 2/3 | head, count(, note) | pipeline/src/fit_reduce.rs |
    | fallback_ledger_total | 3 | fallback_ledger_total, count, note | pipeline/src/main.rs |
    | placeholder_extraction | 5 | placeholder_extraction, candidate_count, failure_exclusions | pipeline/src/main.rs |
    | placeholder_class | 9 | placeholder_class, pixel_form_sha256, kind, slot_count, decision_basis | pipeline/src/main.rs |
    | placeholder_class_found | 9 | placeholder_class_found, pixel_form_sha256, kind, slot_count, decision_basis | pipeline/src/main.rs |
    | placeholder_class_none | 3 | placeholder_class_none, decision_basis | pipeline/src/main.rs |
    | placeholder_skip | 10 | placeholder_skip, subject, cp, kind, pixel_form_sha256, stage | pipeline/src/main.rs |
    | placeholder_form | 10 | placeholder_form, subject, cp, kind, pixel_form_sha256, stage | pipeline/src/main.rs |
    | sub_pixel_speck_retained_replay_unavailable | 3 | sub_pixel_speck_retained_replay_unavailable, decision_basis | pipeline/src/main.rs |
    | sub_grid_floor_replay_unavailable | 3 | sub_grid_floor_replay_unavailable, decision_basis | pipeline/src/main.rs |
    | sub_grid_floor (cache row) | 3 | sub_grid_floor, stage1_total (stage1-cache row; out of checker scope, registered for drift tracking) | pipeline/src/main.rs |
    | placeholder_decision | 10 | placeholder_decision, found, pixel_form_sha256, kind, slot_count, slots (stage1-cache row; cache files are out of checker scope, registered for drift tracking) | pipeline/src/main.rs |
    | speck_retained | 5 | speck_retained, count, areas (stage1-cache row; out of checker scope, registered for drift tracking) | pipeline/src/main.rs |
    | notdef_proxy | 41 | notdef_proxy, classification, decision_basis, hash_basis, policy, candidate_count, rule, selected_cp, source_sha256, style, frame, units_per_px, ink_model, generated_glyph_ref, generated_glyph_sha256, generated_sha_basis, source_snapshot_sha256, advance_basis, lsb, rsb, advance | pipeline/src/notdef_proxy.rs |
    | notdef_proxy_final_gid0 | 9 | notdef_proxy_final_gid0, outline_sha256, basis, classification, decision_basis | pipeline/src/notdef_proxy.rs |
    | notdef_decode_limits | 15 | notdef_decode_limits, max_input_bytes, max_pixels, max_working_bytes, origin, budget_scope, png_crc, parity | pipeline/src/bound_detector_validator.rs |
    | notdef_evidence_ignored | 2 | notdef_evidence_ignored, code | pipeline/src/main.rs |
    | notdef_ink_exceeds_advance | 6 | notdef_ink_exceeds_advance, flag, ink_width, advance | pipeline/src/main.rs |
    | diagnostic_partial_kern | 3 | diagnostic_partial_kern, flag, note | pipeline/src/main.rs |
    | diagnostic_partial_space | 3 | diagnostic_partial_space, flag, note | pipeline/src/space_evidence.rs |
    | ink_containment | 16 | ink_containment, subject, lsb_before, lsb_after, rsb_before, rsb_after, advance_before, advance_after, tier | pipeline/src/ink_containment.rs (floor module: gains trailing tier, single literal T2) |
    | ink_containment_skipped | 6 | ink_containment_skipped, subject, reason, tier | pipeline/src/ink_containment.rs (trailing tier for uniformity; floor v2 lands it tiered) |
    | ink_containment_floor | 9 | ink_containment_floor, font_median_pair_target_over_2, tier, floor_lsb_n, floor_rsb_n | pipeline/src/ink_containment.rs (pair_target key dropped; None prints the literal `unavailable`; trailing tier T2; legacy pool base sizes trail for the legacy median path) |
    | containment_compensation | 7 | containment_compensation, pairs_shifted, pairs_untouched, negative_origin_pairs | pipeline/src/ink_containment.rs |
    | containment | 4 | containment, code, subject, reason | pipeline/src/ink_containment.rs (typed stage row; stage = containment; codes: ink_containment_floor_fallback, ink_containment_floor_zero, ink_containment_floor_note) |
    | iou_config | 13 | iou_config, ink_threshold, flatten_steps, max_input_bytes, max_pixels, settings_origin, limits_origin | pipeline/src/main.rs |
    | iou_translation_proof | 4 | iou_translation_proof, status, cause | pipeline/src/main.rs |
    | kern_omitted | 6 | kern_omitted, flag, reason, note | pipeline/src/main.rs |
    | population_floor | 2/12 | population_floor, flag(, code, population, excluded, fallback_ledger_events, degrade) | pipeline/src/population_floor.rs, main.rs |
    | population_floor_glyphs | 4 | population_floor_glyphs, count, advance | pipeline/src/population_floor.rs |
    | run_mode | 8 | run_mode, mode, solve_spacing, population_sha256, glyphs | pipeline/src/main.rs |
    | scope_selection | 19 | scope_selection, policy, unicode, eligible, actual, intersection, ineligible, letters_without_nonzero_kern, kern_participants_sha256, allow_set_sha256 | pipeline/src/kern_scope.rs |
    | space_evidence | 4/5/7/9/16/20 | space_evidence, kind (decode or wiring), input_sha256, kind, max_input_bytes, max_pixels, max_working_bytes, origin, png_adapter | pipeline/src/space_evidence.rs |
    | space_evidence_ignored | 4 | space_evidence_ignored, code, space_status | pipeline/src/main.rs |
    | stage1_cache | 4 | stage1_cache, path, reused_glyphs | pipeline/src/main.rs |
    | run_failure_receipt | 3 | run_failure_receipt, version, N | pipeline/src/run_failure.rs |
    | code | 2 | code, refusal code | pipeline/src/run_failure.rs |
    | detail | 2 | detail, single-line text | pipeline/src/run_failure.rs |

    `kern_drop` reason codes are a closed vocabulary derived from the kern structure,
    never free text: `overlap_hold`, `clamp_refused`, `rejected_unbound`,
    `dropped_zero`. The per-code line counts must close exactly against the
    `kern` receipt counters, else a typed refusal (emitter invariant).

    The floor module (ink containment, tier T2) pins typed stage rows,
    stage = containment, shape (head, code, subject, reason). The strings
    below are the emitter format literals. Legend: `{glyph}`, `{floor}`,
    `{LEFT}`, `{RIGHT}` and `{}` are format holes; a `{}` under an _over_2
    key prints the value or the literal `unavailable`; the tier hole always
    prints the single literal T2.

        containment	ink_containment_floor_fallback	{glyph}	floor={floor}; source=font_median_pair_target_over_2; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}; pair target unavailable or glyph has no ready pair
        containment	ink_containment_floor_zero	run	floor=0.0; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}; no ready pairs; containment only, declared, nothing invented
        containment	ink_containment_floor_note	pair_target_unusable	pair={LEFT}+{RIGHT}; value rejected (non-finite or negative); fallback path taken; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}
        containment	ink_containment_floor_note	font_median_pair_target_unusable	run; value rejected (non-finite or negative); fallback path taken; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}
        containment	ink_containment_floor_note	zero_floor_no_fallback	glyph={glyph}; floor=0.0; pair_target_over_2={}; font_median_pair_target_over_2={}; typed target path produced floor=0.0; tier={}

    The same module changes existing rows: `warning` `ink_containment_adjusted`
    replaces floor_lsb/floor_rsb with floor_font_median_over_2 (printed as
    the value or the literal `unavailable`) and inserts `tier` `T2` between
    population and policy; `ink_containment_floor` is
    font_median_pair_target_over_2 + tier, with the legacy pool base sizes
    floor_lsb_n/floor_rsb_n trailing; `ink_containment` gains the
    trailing tier; `ink_containment_skipped` lands tiered.
    pair_target_unusable is per-pair, font_median_pair_target_unusable is
    run-level, and both are emitted even when no glyph is adjusted.
    zero_floor_no_fallback is emitted only when a Some(pair_target) path
    produces floor=0.0; the pair_target=None path uses the legacy median
    sidebearing floor and never emits zero_floor_no_fallback.

    Pair identity is deduplicated before incident-target aggregation, so a
    self-pair contributes one target to its glyph. A glyph's incident pairs
    are the ready pairs with left OR right equal to the glyph id; the
    per-glyph floor is the median of its usable incident pair_targets / 2.
    A glyph with no usable pair target and no pair_target=None incident
    falls back to font_median_pair_target / 2 with the typed fallback row.
    An empty pair set with a usable font median takes that fallback without
    the floor_zero row; the floor_zero row is reserved for an empty pair set
    with no usable font median. Carrier: the per-pair target rides
    `PairPosition.pub pair_target: Option<f64>` and the run median rides
    `SpacingSolution.font_median_pair_target: Option<f64>`; FloorEvidence
    carries only the font median.

    I1b reason whitelist (the type-token comparison is a test-level
    classification, not a registry literal): (a) an unshifted pair stays
    byte identical - no arithmetic touches it, no row. (b) Any shifted pair
    maps to the whitelist token `containment_compensation_negative_origin`,
    a typed constant that exists only in the compensation-combined tree.
    (c) A solver wall_gap disagree maps to the type token `collision`, and
    collision at exact solver placement maps to `collision` - same type
    accepted. Both (c) branches are prose pair notes in the
    source, not registry literals; the `collision` token is the test-level
    grouping, no literal is invented for it.

    `kern_drop` reason codes are a closed vocabulary derived from the kern structure,
    never free text: `overlap_hold`, `clamp_refused`, `rejected_unbound`,
    `dropped_zero`. The per-code line counts must close exactly against the
    `kern` receipt counters, else a typed refusal (emitter invariant).
    `speck_dropped`: no such row exists in the tree; per the emitter note,
    only a grid-unrepresentable capture counts as dropped and it surfaces in
    existing drop accounting, not in a speck-specific row.

    Team 7 floor module (ink containment, tier T2) pins typed stage rows,
    stage = containment, shape (head, code, subject, reason). The strings
    below are the emitter format literals from floor v3 (sha256
    6b9249c1355225a997ba8b09d0147d23e7e7006b6ffb8fd832b5264a8e504afe),
    with which this entry co-lands, not standalone. Legend: `{glyph}`,
    `{floor}`, `{LEFT}`, `{RIGHT}` and `{}` are format holes; a `{}` under
    an _over_2 key prints the value or the chief-confirmed literal
    `unavailable` (never a silent omit; v3 names it NONE_TOKEN); the tier
    hole always prints the single literal T2. Chief-approved:

        containment	ink_containment_floor_fallback	{glyph}	floor={floor}; source=font_median_pair_target_over_2; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}; pair target unavailable or glyph has no ready pair
        containment	ink_containment_floor_zero	run	floor=0.0; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}; no ready pairs; containment only, declared, nothing invented
        containment	ink_containment_floor_note	pair_target_unusable	pair={LEFT}+{RIGHT}; value rejected (non-finite or negative); fallback path taken; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}
        containment	ink_containment_floor_note	font_median_pair_target_unusable	run; value rejected (non-finite or negative); fallback path taken; pair_target_over_2={}; font_median_pair_target_over_2={}; tier={}
        containment	ink_containment_floor_note	zero_floor_no_fallback	glyph={glyph}; floor=0.0; pair_target_over_2={}; font_median_pair_target_over_2={}; pair target and font median both unavailable; tier={}

    (The pair={LEFT}+{RIGHT} context on pair_target_unusable was added
    in v3; the pair is named deterministically in stored pair order.)

    The same module changes existing rows: `warning` `ink_containment_adjusted`
    replaces floor_lsb/floor_rsb with floor_font_median_over_2 (Option
    printed as the value or the literal `unavailable`; v3 drops the
    pair_target key) and inserts `tier` `T2` between population and
    policy (not trailing); `ink_containment_floor` is now
    font_median_pair_target_over_2 + tier only (v3 drops the pair_target
    key; 5 fields); `ink_containment` gains the trailing tier;
    `ink_containment_skipped` lands tiered. pair_target_unusable is
    per-pair (the context names the rejected pair),
    font_median_pair_target_unusable is run-level (context `run`), both
    always output on the rejected input with the affected _over_2 field
    carrying the value `unavailable`; zero_floor_no_fallback is emitted
    per glyph that lands on 0.0 without the run-level no-ready condition.
    Aggregation (chief ruling 2026-10-17): a glyph's incident pairs are
    the ready pairs with left OR right equal to the glyph id; the
    per-glyph floor is the median of its usable incident pair_targets / 2
    (odd count: the middle value; even: the mean of the two middles - the
    same median definition as the font median); a glyph with no usable
    pair target falls back to font_median_pair_target / 2 with the typed
    fallback row; with no font median the glyph lands on floor=0.0 with
    the zero_floor_no_fallback row. Carrier: the per-pair target rides
    `PairPosition.pub pair_target: Option<f64>` and the run median rides
    `SpacingSolution.font_median_pair_target: Option<f64>` (both solver
    fills, solver-lane W14 patch, SPEC-AHEAD-OF-EMITTER - v3 references
    both but they are not in the combined source; FloorEvidence carries
    only the font median). The combined 62b4c1f8+s1v3 source still emits
    the pre-change shape, so this registry entry precedes the emitter.

    I1b reason whitelist (chief ruling 2026-10-17; the type-token
    comparison is a test-level classification, not a registry literal):
    (a) an UNSHIFTED pair stays byte identical - no arithmetic touches it,
    no row. (b) ANY shifted pair maps to the whitelist token
    `containment_compensation_negative_origin` - a typed const
    (metrics/src/generated_outline_kern.rs:250) that exists only in the
    S1v3-combined tree (W13/S1 code, not origin/main); the kern stage holds
    the pair and ships it kernless, never clamped. (c) a solver wall_gap
    disagree maps to the type token `collision`, and collision at exact
    solver placement maps to `collision` - same type ACCEPTED. Provenance:
    both (c) branches are prose pair notes in the source
    (metrics/src/generated_outline_kern.rs:919 collision, :925 wall_gap
    disagree), NOT registry literals; the `collision` token is the
    ruling's test-level grouping, no literal is invented for it.

    The last three heads appear only in `run-failure-receipt.txt`
    (always-output refusal record, no-overwrite rule). `code` and `detail`
    are generic words; variant (d) binds them to receipt files, so they
    pass only inside receipt context.

    The registry is bound to the emitter source by
    `tools/conc/receipt_head_drift.py`: it extracts candidate row heads
    from the Rust emitters and fails when an emitted head is unregistered,
    when a registered head is no longer emitted, or when a non-receipt
    exception entry goes stale. A diff that adds a receipt emitter extends
    the registry in the same diff; otherwise the drift test fails intake.

## Gate usage

Every lane gate runs:

    python3 tools/conc/ledger_check.py <ledger/receipt files...>

Exit 1 on any violation; `--json` for machine consumption;
`--allow-unregistered` only for local iteration, never at intake;
`--strict-legacy` (alias `--strict-variants`) counts variant lines as
violations. `--self-test` runs the checker's embedded conformance suite.
