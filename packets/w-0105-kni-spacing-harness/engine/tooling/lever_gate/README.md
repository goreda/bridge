# lever_gate (W5): single gate runner for holdout protocol v3

Revision 2. Author reported. Run here with Python 3.10 and numpy 2.2.6, stdlib unittest, no fontTools needed. Not independently re-run.

Rule: lever authors CALL this runner, they do not change it. The gate does not compute IoU, nodes, C2, C7 or TDP. It reads measurements emitted by the frozen hash-pinned evaluator on decoded integer CFF (`object: decoded_integer_cff`) and does paired statistics, co-gates and hard gates. Every missing or unverifiable input fails closed.

Run:
`python3 gate.py --manifest fold.json --base base_meas.json --run L1=l1.json --run L2=l2.json --composed L2,L1=l21.json --derive-log L1=read_log.json --reserve-log reserve.json --phase design|final --out result.json`
Exit 0 only if every mode decides PORT. Tests: `python3 -m unittest discover -s tests`.

## Mapping to the protocol
- Section 1, fold unit: `manifest.py` validates fold manifest (font, family, style, source vector|image, path label, file sha256), design family, optional reserve family. The design family is never counted as held-out.
- Section 2, derive-read-sha: `derive_guard.ReadRecorder` records sha256 of every file opened in its context (builtins.open, io.open, pathlib.Path.open). `check_no_heldout_reads` is a hard gate. Reads by C extensions, mmap or subprocesses are not seen; derive code must then read through `ReadRecorder.read_bytes`. A lever that declares `derives_nothing` is reported as such; otherwise a read log is mandatory.
- Section 3, abstain: primary comparison only on the intersection scored by base and lever, abstain counts reported per family.
- Section 4, statistic: improvement oriented by the preregistered direction, per-family median as the family value, percentile bootstrap over families when at least `min_families_for_interval` families (preregistered, no default), else sign count over every fold with no interval. Seed, level, resample count preregistered; optional `interval_precision` makes a two-seed stability check a gate. Primary rule: interval lower bound above zero; sign rule: every fold beats base.
- 4a.1 algorithmic levers: preregistered `unit: shape` dedupes by translation-invariant `shape_key` (`stats.shape_key` helper), effective shape count per family reported.
- 4a.2 reserve: the reserve family is out of scope in `design` phase. In `final` phase the reserve log must contain exactly one look (`record_look` refuses a second). 4a.3: `settings_tried` is echoed. 4a.4/4a.5: status ladder (below). 4a.6 co-gates, all required: nodes at equal fidelity (items within the preregistered `equal_fidelity_epsilon` of the primary metric; no such item means no evidence and fails), C2 = 0 on every lever item, C7 and every TDP component separately (no total component allowed, direction preregistered), non-target items byte-identical or listed. 4a.7 pre-registration fields are required in the manifest. 4a.8 size split reported when `family_sizes` and `size_split_glyphs` are given. 4a.9 independence: `run_by != author`.
- Pins: base and lever measurement files must carry the preregistered `frozen_evaluator_pin` (name and sha256), the preregistered frame, the manifest path label. Different path labels are never pooled. The gate compares pin strings; it does not hash the evaluator binary itself, the pin receipt belongs in the measurement file.
- Composition modes: `run_modes` tests each lever alone on the raw fit (`mode: alone_raw`) and the sequential composition (`mode: composed`, `order`). Each decides on its own measurements; additivity is only reported, never assumed.
- Receipts: sha256 of manifest, base, every run file, reserve log and result file. Result is labelled `author_reported` unless independent.

## Status ladder
`candidate` when the lever is PORT but any of these holds: single font (internal fold), fewer than 3 non-design families, reserve not looked at in this run, not independently run. `adopted` only with none of them. `NO_PORT` if any hard gate, the primary rule or any co-gate fails ("no gain above the interval: no port").

## Measurement file schema
`{evaluator_pin:{name,sha256}, frame, object:"decoded_integer_cff", path_label, mode, author, run_by, derives_nothing?, order?, items:[{item_id, shape_key?, target, abstain?, <primary metric>, nodes, c2, c7, tdp:{component:value}, output_sha256}]}`
Manifest: `{items:[{item_id,font_id,family_id,style_id,source,path_label,file_sha256,path?}], design_family, reserve_family?, family_sizes?, preregistration:{primary_metric,direction,abstain_rule,interval_method,interval_level,resamples,seed,equal_fidelity_epsilon,frozen_evaluator_pin,frame,cogate_metrics:{nodes,c2,c7,tdp_components,directions},min_families_for_interval,unit,settings_tried,interval_precision?,size_split_glyphs?}}`

## Revision 2
- C2/C7 columns: `cogate_metrics.c2` and `.c7` are lists of evaluator column names (C2_missing_extrema, C2_stationary_inflections, C7_zero, C7_duplicate). The evaluator output header is the measurement file's `columns`. Fail closed (RED): header missing or different between base and lever, a manifest name absent from the header, or a header C2_*/C7_* column the manifest does not gate. C1/C3/C4 header columns are listed as `nd_columns_not_gated`, never gated.
- Equal fidelity window: each lever item may carry `equal_fidelity_epsilon` (evaluator emitted, style pixel scale); the manifest scalar is a fallback only; none of the two is a hard failure. The result prints min/max epsilon and item/fallback counts per style/family. It is a window for "is the node comparison meaningful", not a gain threshold.
- Convention: `min_families_for_interval` 10 and level 0.95 are echoed under `conventions` and deviations are flagged; below the family count the method is labelled `sign count only` with no interval.
- Precision: per item `pixel_iou_step` (evaluator emitted, one pixel of IoU for that style); the strictest (minimum) step is used. Resamples double from `resamples` to `max_resamples` until two seeds agree on both endpoints within the precision; if not converged the interval does not pass. Co-gate intervals reuse the primary's final resample count. Manifest `interval_precision` is a fallback only. `max_resamples` is a required preregistration field.

## Open
- TDP component names remain a preregistration input (`tdp_components`, optional); their values sit under the item key `tdp`.
- `max_resamples` has no derived value; the lever author preregisters it.
- Fixtures here are synthetic. No real lever has been gated.

## r3 additions
- Budgets per glyph, three, each decided separately: `current` (base node count), `plus10` (CONVENTION, preregistered `budget_plus_fraction`, `budget_rounding`), `potrace` (the glyph's own potrace node count from the base row). Lever rows carry `budget` and `budget_nodes`; the gate recomputes each cap and fails on mismatch. Within-budget is a co-gate. Top-level PORT needs every budget to PORT; `budget_decisions` lists each. Tables are ordered by item_id and carry no best/most-economical label.
- Equal-node: `equal_node_gate` is preregistered. Lever rows carry `curve` [[nodes, iou],...] (the evaluator's IoU-vs-node curve); the point at the base node count is compared. Missing point = no evidence. Curves are published per glyph in the result.
- Monotonicity: IoU vs added nodes; non-monotone items are listed. The best-prefix rule is forbidden (manifest RED if `best_prefix_rule` is set); equal-node uses the exact curve point only.
- Potrace budget source: manifest field `potrace_budget_source` {sha256, parser_pin, frame} is mandatory; base and lever must carry the same `node_count_parser_pin` and base the same `potrace_budget_source_sha256`; frame must equal the preregistered frame.
- C2 definition pinned: manifest `c2_definition_sha256` must equal f93db05d48c1125574aa7fdf76d4b660506135a6d17e68f3ee056e959c238535 (hub c2_exact.py); measurements carry the same value.
- Compositions: `--composed` is repeatable; each order (L7,L2,L1 and L2,L7,L1) is its own mode. Additivity is reported per budget, never assumed.
