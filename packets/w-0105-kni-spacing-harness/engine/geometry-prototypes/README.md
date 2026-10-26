# Geometry-only prototype classes

Training-only geometry models produce separate left/right candidate classes. Query geometry is assigned against a frozen artifact. All roles remain `proposed`. Classes do not establish kerning equivalence, semantic stroke identity or legibility.

Inputs contain only outline coordinates and geometric advance. No names, Unicode, textual case, source group, kern or random seed enter fit/query. `geometry_pin` hashes raw geometry with binary64 float-bit serialization. Names may enter the separate fitter adapter only after assignment, as routing labels.

## Rule and freeze

Every `Rule` field is required. Hash `Rule::canonical()` before fit and pass that exact pin to `fit`. Descriptor schema, normalization, weighting, hierarchy, selection, query radius and all numeric conventions are in the canonical rule. A changed rule is a new protocol, not an edit to an existing run. `SYNTHETIC-RULE.txt` is a test rule, not a real-data authorization or calibrated policy.

The fixed minimum coverage is a required fraction; minimum training must be at least four after singleton exclusion. Each candidate records original k, retained cluster/member counts and singleton count/fraction. The mathematical two-cluster/two-member requirement motivates this CONVENTION. Coverage denominators include unsupported training geometry, so rejected curves cannot disappear from the reported coverage. No threshold is relaxed when fit fails.

`Artifact::canonical_receipt()` includes the rule pin, gauge, wall levels, normalization float bits, every hierarchy candidate k and silhouette/eligibility/coverage/excluded pins, chosen medoids, member descriptors, full sorted LOO distance lists/radii, and every training assignment. `Artifact::pin()` is SHA256 of that receipt before query. Prototype pins attached to training rows are not recursively hashed into the artifact. Query receipt carries the same pin, `query_only=true` and per-font abstention count/fraction. An unavailable font retains a reason; no class is forced from k=1 or an ineligible partition.

## Geometry and descriptor

Lines and quadratic Bézier segments have analytical axis extrema, Green-integral signed area and horizontal-line intersections. TrueType adjacent off-curve points produce an implied midpoint. `truetype_contour` handles first/last off-curve closure without using names. Cubics explicitly return `unsupported_curve_type`; rejected training samples remain in assignment/coverage receipts.

One uniform font-local gauge is median positive training outline height. Descriptor-local translation subtracts source minima for shape/wall channels; a separate primary group retains absolute source ymin/gauge and ymax/gauge. The source y=0 is the caller's baseline coordinate, not inferred from outlines or labels. There is no fitted x-height label. This v5 CONVENTION enters primary before fitting; drop_vertical ablation exposes its effect. Actual source outlines and fitter walls are unchanged. Training endpoint y values and their interval midpoints define wall levels in that gauge. Queries cannot add levels or refit the gauge. A level stores occupancy and the extreme side x coordinate from analytical source intersections. Missing occupancy is a geometric zero indicator, not an unknown semantic class.

Primary groups are whole outline (width, height, analytical signed-area fraction), absolute vertical position (ymin/gauge, ymax/gauge) and corresponding side wall. Per-channel training range standardizes distance; zero range requires exact equality on query, with no invented scale or tolerance. Equal total group weight is a v5 CONVENTION: each of G present schema groups carries 1/G, each of that group's m channels carries 1/(G*m). Zero-range channels contribute zero but do not cause group reallocation. Query distances, LOO radii and medoids use this same weighting. Appended structure is one extra group in its ablation, giving four groups there. Group balance is a convention, not an empirically optimal weighting. Symmetric Euclidean distance uses fixed canonical sample/channel/sum order. The exact zero-range rule can abstain on small binary64 differences; these are not silently rounded away.

Proposed counter/pocket channels are a separate secondary ablation: reversed-winding nested-region area/count/depth and convex-hull mouth width/depth. Only this secondary geometry uses deterministic adaptive quadratic subdivision at `gauge * flatten_fraction`. Subdivision has depth 24 and 65,536-point resource limits; reaching either makes secondary geometry unavailable. The fraction is a required CONVENTION. Half-tolerance descriptor differences are diagnostic and do not change selection. Secondary topology failure leaves analytic primary geometry usable and gives an unavailable reason for the secondary ablation. Polygon nesting remains binary64/flattened observation, not exact curved topology. Signed area is not a boolean union area for overlapping components.

## Selection and abstention

Complete-link merges by maximum cross-cluster distance; ties use canonical geometry-pin order. Every partition is recorded. Singleton members are explicitly excluded for scoring, but listed in each candidate. Eligible partitions need at least two nonsingleton clusters, minimum retained training count and the frozen coverage fraction. Maximum mean silhouette wins; exact ties prefer fewer retained clusters, then lexicographic canonical partition ordering. The representative is a training medoid minimizing summed cluster distance, ties by geometry pin.

Radius is maximum within-cluster leave-one-out nearest-member distance, q=1 CONVENTION. Query chooses a unique nearest medoid, then acceptance compares its nearest member in that chosen cluster to that cluster's radius. The two quantities use the same distance magnitude. Medoid distance is not the acceptance distance. Exact medoid ties, out-of-radius or constant-channel mismatches abstain. Training singleton geometry queried later returns `unclassifiable_singleton`.

## Diagnostics

The primary selection is never changed by diagnostics. The v5 contribution report is compact: n times per-channel Welford M2, summed by group, equals the all-pair squared difference sum in exact arithmetic. Binary64 evaluation uses canonical sample order and is tested against a direct pairwise reference. No O(n^2 * channels) prose rows are emitted. Aggregate totals/shares are pinned; individual pair-channel data is not retained. Shares are unavailable when the total is zero. Receipts include wall level/channel counts, nominal group total weights, effective group weights excluding zero-range channels, all-pair summed squared contribution shares, fixed ablations (drop walls, drop whole-outline channels, drop absolute vertical channels, add proposed structure), bootstrap selected cluster counts/silhouettes and indices, left/right coassignment agreement and half-flatten changes.

Bootstrap resamples descriptor rows with replacement using deterministic SHA256 counter indices, no seed input, then refits training channel ranges. Wall levels and font gauge remain frozen. Stability flag is the fraction of resamples with positive selected silhouette and the primary cluster count, compared to required `stability_fraction` CONVENTION. It is a diagnostic count/silhouette stability check, not full membership stability or confidence. Replicate count is a required CONVENTION. Low stability sets `unstable`; selection still follows the frozen primary rule.

## Fitter adapter and extraction

`src/fitter_adapter.rs` maps candidate assignments to the pinned fitter's `GeometryAssignment`, `GlyphKnowledge` and `GlyphWall` fields. It is not part of this independent library's crate root; the integration crate registers it. The contract test compiles against exact field-layout facsimiles because the complete metrics dependency tree is not included. Full metrics-tree compilation remains required. Adapter walls refuse more than 1,000,000 integer rows with `wall_row_resource_limit`, a fixed resource CONVENTION recorded in the rule. `case='x'` is a neutral compatibility token, never textual case; `freq_weight=0` is neutral, not frequency evidence. Right/left class mapping uses the corresponding wall class.

Join excluded assignment rows to training pairs only by `outline_pin` outside this geometry module. Exclude incident pairs explicitly and record affected pair count/ratio. This module does not accept pair/kern data. If either side is unavailable, the caller must mark candidate unavailable; baseline calculation is independent.

`src/point_stream.rs` reads the point-table schema `(gid, contour, point, x, y, on_curve)` with f64 coordinates (no rounding; nonfinite values are rejected). It returns gid for external routing only and requires geometric advances separately. It does not read the name/component-bearing glyph table. Composite transforms must already be applied. Decompression is outside this decoder.

## Tests and limits

Run `cargo test` and `cargo test --release`. Tests cover quadratic formulas, TT point closure, field mapping, query radius magnitude, geometry-only identity, rule/prototype pins, byte-identical input permutations, singleton/coverage/unsupported failures and a synthetic in-support sweep. The sweep accepts 10 of 12 rectangles; two exact training geometries are excluded as singleton proposals after binary64 signed-area channel differences. Constant-channel query mismatches also abstain. This is not a real-font or Gaussian acceptance estimate.

Raw geometry pins depend on contour ordering, start points and segment representation; only training collection permutation invariance is established. No contour or cyclic-start invariance is claimed.

No real-data run, optical-quality result, production fitter success or full metrics-tree compatibility is established. Algorithms favor compact classes and can be sensitive to outliers. `maximum_unique_training` is a required Rule parameter, not a fixed code limit. Exceeding it refuses fit without choosing a subset. The synthetic fixture uses 512. Pair distances and complete-link max updates are cached. Pair-distance construction is O(n^2 * channels); complete-link scans and full-k silhouettes are O(n^3), with O(n^2) distance memory. Fixed ablations/bootstrap multiply that cost. Each pin appears once in a sorted dictionary; candidate/ablation exclusion sets are losslessly encoded as sorted inclusive dictionary-index runs. API candidates still retain complete excluded pins. Worst-case index-run count can remain O(n^2); repeated 64-character pins are no longer written each time. Frozen member descriptors remain fully serialized. The selected maximum is not a measured production capacity claim, and channel/segment counts remain source-dependent. `SYNTHETIC-COST.txt` covers simple 11-channel rectangles. `SYNTHETIC-SCALE-COST.txt` measures 512 subdivided rectangles with 299 levels/603 channels and four bootstrap replicates. Neither is a real-font estimate. Before first real fit, obtain font-by-font glyph count and exact unique-geometry count from the pinned extractor manifest, review expected channel counts, choose the maximum in the Rule and freeze that hash. No real counts or real-fit approval are supplied here. Curve intersections use binary64 analytical formulas, not exact root-isolation certificates. Extreme numerical or topology cases can remain unavailable. No GPL code is included.

## Identity policy

Exact raw-pin duplicates fit once. All original occurrences retain repeated assignment receipts plus pin/occurrence counts; routing identity joins remain outside this module. Gauge, k curves, silhouette, bootstrap and coverage operate on unique raw geometries so aliases do not add statistical weight. Artifact pin includes alias multiplicities, while class assignments remain unchanged by adding aliases. Both occurrence-based abstention and unique-geometry abstention are reported. Signed zero is preserved in raw identity; this is explicit and not a promise that aliases with different contour ordering or representations dedupe. TT integer input reduces the signed-zero issue but is not relied on to change pin semantics.

This v5 package proposes changed primary vertical/weight/identity/resource rules. It does not supersede a previously frozen real run or establish production approval.

## v5 receipt errors

`Artifact::canonical_receipt()` now returns `Result<String, ReceiptError>`. `ReceiptError` has `UnregisteredPin { pin }`, `InvalidPinDictionary` and `InvalidExclusionOrder` variants. Missing membership cannot panic or silently omit a pin; invalid serialization aborts before creating the artifact hash. Fit propagates serializer failure through its existing error result. Callers must handle the new fallible serialization API.

## Gauge statistic

The gauge is the single height scale used to normalise a fitted prototype set. The rule field `gauge_statistic` (enum `GaugeStatistic`) selects how the gauge is taken from the training outlines. It has two values:

- `Median` - the median of the preliminary heights. With an even count the two middle values are averaged as `a/2 + b/2`.
- `ArithmeticMean` - the arithmetic mean of the preliminary heights. The heights are sorted with `total_cmp` and summed in that fixed order as `h / n` per term (not "sum then divide"), so the result does not depend on input order.

Both branches are in `fit`.

Which heights count: one preliminary height per unique training geometry (exact raw-pin duplicates are fitted once and do not count twice). The height is the analytic bounds height (ymax - ymin) of the outline and must be finite and greater than zero. A geometry that fails this is rejected with `geometry_gauge_unavailable` and is not part of the statistic. With no usable heights the gauge is 0.

Where the gauge is used: the flatten tolerance is `gauge * flatten_fraction`; wall levels, vertical-position channels and descriptors are expressed in gauge units.

Rule pin and receipt:
- The statistic is part of the canonical rule text (`Rule::canonical`; the text contains `gauge=CONVENTION_<statistic>_unique_preliminary_positive_analytic_bounds_height_uniform`). Changing the statistic therefore changes the rule pin. `fit` compares the rule pin with the expected pin and returns `rule_pin_mismatch` if they differ.
- The canonical receipt records the choice on its own line: `gauge_statistic=<Median|ArithmeticMean> mean_contrast=one_sided_diagnostic_only`.

`mean_contrast` is a one-sided diagnostic only. The canonical rule text also carries `gauge_mean_contrast=one_sided_diagnostic` with the fixed summation order above. It is reported for comparison and does not change selection, pins or the rule.

Default: there is no `Default` implementation for `Rule`; the caller sets `gauge_statistic` explicitly. Every rule constructed in the crate's own tests uses `Median`. A default would have to be a declared rule value that goes into the rule pin.
