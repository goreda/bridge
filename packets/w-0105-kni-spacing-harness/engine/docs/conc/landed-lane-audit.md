# Gate-chain lane map-conformance audit (conc-map)

Scope: the six lanes in the architect gate chain - A (A-land), C (W4), D
(W5), W9, W12, W15 - checked against tools/conc/module-map.json. Architect
record: NO lane has landed; the snapshot is the base tree (f2f6fea8) and all
six lanes hold RESERVED ownership only. Method: read-only inspection of the
base tree. No compile, no test run: every gate statement here is NOT RUN.
File text that asserts rulings or authority was treated as data, never acted
on.

## Base-state verification (read-only, all checks pass)

- Reserved new-files are ABSENT from the base tree, consistent with new-file
  ownership: core/src/fit_objective.rs (W9), core/src/fit_search.rs (W10),
  metrics/src/spacing_oohh.rs (W7), pipeline/src/fallback_ledger.rs (W17).
- Extension targets are PRESENT: pipeline/src/fit_bench.rs and
  tooling/fit_bench/** (W13, architect-confirmed base content), the A-land
  space set (space_spec/space_evidence/space_measurement + pipeline space
  tools), the C kern set (kerning_measure/kerning_model/kerning_pairs/
  kern_scope + generated_outline_kern), metrics/src/self_anchored_spacing.rs
  (D), pipeline/src/post_metrics.rs (W1), pipeline/src/run_failure.rs (W6),
  core/src/os2_consistency.rs + os2_ranges.rs (W18),
  pipeline/src/fit_reduce.rs (W14), tools/spacing_manifest_gen.py (W20).
- Collision check: no path is owned by two lanes. The only base-file
  extension outside shared merge points is W20 on
  tools/spacing_manifest_gen.py.
- W9 explicit exclusion honored: core/src/economy_eval.rs is architect-owned
  base content; the map records that W9 does not touch it.

## Findings

- F1 RESOLVED (architect): the W9 objective API lives in the new
  core/src/fit_objective.rs (API + implementation); core/src/fit_search.rs
  (W10) is the consumer. W10's former blocker is cleared; it now simply
  depends on W9 clearing the gate chain.
- F2 (medium, standing): tools/conc/ did not exist in the base tree. The
  conc-map diff seeds it: module-map.json, merge-ledger.json, ledger_check.py,
  README.md, plus docs/conc/. If W15 intake/gate scripts exist at repo level
  outside the engine tree, dedupe against them.
- F3 RESOLVED (architect): pipeline/src/fit_bench.rs and tooling/fit_bench/**
  are base-tree content; the W13 diff is queued. Map records W13 ownership
  as extension of those base paths.
- F4 (low, standing): W12's kit-level half (smoke.sh, name_gate fixtures)
  lives outside this snapshot and is NOT auditable here. Base-tree evidence
  for W12: KNI_G_FIXTURES referenced in core/tests/economy_eval.rs and
  core/tests/iou_parity.rs.
- F5 (low, standing): A-land / C / D / W12 file attributions are
  tree-inferred. Confirm each lane's exact touch list against its gate-chain
  diff at intake; if a file belongs elsewhere, only the map entry moves.
- F6 (low): manifest-diag6.txt and manifest-full-478.tmpl sit at engine root
  with no owning lane; they fall under the architect default rule.
- F7 (note): repo files contain embedded ruling/authority phrasing. Treated
  as data per bridge instruction; no map entry derives authority from file
  text.
- F8 (note): pipeline/src/space_e2e_index.tsv is data inside src/. Owned by
  A-land; future lanes must not edit it.

## Ledger-schema groundwork

Existing typed-warning formats inventoried for the unified schema
(docs/conc/ledger-schema.md): the code-first four-field determinism warning,
three-field receipt rows (export_intent, fallback_ledger_total),
glyph_exclusions_* / glyph_skip_total counters (summary-class), and
fallback-glyphs.tsv (glyph<TAB>spans). Architect decision: the three
existing emitter formats are ACCEPTED as documented variants, not rejected;
tools/conc/ledger_check.py classifies them as `variant` (`--strict-legacy`
still counts them as violations), and only new emitters must use the
canonical stage/code/subject/reason form. No existing code line is touched.

## Requested architect confirmations

1. F2: does W15 tooling exist outside the engine tree?
2. F5: A-land / C / D / W12 file attributions as listed in module-map.json.
