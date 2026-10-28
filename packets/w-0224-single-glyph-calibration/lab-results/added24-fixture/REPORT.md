# W-0224 approved24 test extension

IMAGE-PIPELINE FIXTURE METADATA ORACLE ONLY. Not recognizer accuracy/calibration, no production weights, no cutoff or acceptance.

Exact stage1b manifest SHA b31335dd2c7093625fa28da4b068212c0d5922baf9d8ca15531032b82b2597c6 approved24/25 by same-ID response commit90014b6e789136d759de25b765dea3f5625afa9d. Dropped Saira Extra Condensed (slug sairaextracondensed), no replacement and no pixels generated for that family. Original proposal bytes unchanged. All24 remaining files rendered at identical256/384/512 frame and170/256/341 em sizes using frozen v1.3 harness. Original baseline15 files/results untouched.

## Coverage

Added24:4968 PNGs=4464 glyphs+216 half+216 two+72 blanks. Combined test29:5394 positive inputs+609 negatives=6003 rows. Per class87 pooled size images but only29 independent fonts; main384 per-class support29. Original calibration5/validation5 unchanged. Combined all cohorts8073 rows. Missing from proposed extension:Saira Extra Condensed only, explicitly dropped. No silent replacement.

Exact pinned preprocess ran on each added nonblank tight crop;72 blanks are typed intake abstains. Known fixture outcomes independently checked row-by-row; all image hashes/order checked. No network trained. Added families use a documented deterministic oracle schedule independent of original15; their score differences are artificial, not style-recognition evidence. Baseline calibration map and full validation results asserted exactly equal by value. No test-label fitting or threshold changes.

| Scope | Recall correct/all positive | Coverage accepted/all positive | Precision correct/all accepted including negatives |
|---|---|---|---|
| baseline_test5 | 661/930=0.710753 | 754/930=0.810753 | 661/772=0.856218 |
| added_test24 | 3112/4464=0.697133 | 3561/4464=0.797715 | 3112/3669=0.848188 |
| combined_test29 | 3773/5394=0.699481 | 4315/5394=0.799963 | 3773/4441=0.849583 |

## Added per-family tables

Each family186 positives+21 negatives across three sizes. Oracle outcomes only.

| Family | Recall | Coverage | Precision |
|---|---|---|---|
| Alfa Slab One | 128/186=0.688172 | 148/186=0.795699 | 128/154=0.831169 |
| Anton | 126/186=0.677419 | 146/186=0.784946 | 126/150=0.840000 |
| Baloo 2 | 125/186=0.672043 | 146/186=0.784946 | 125/148=0.844595 |
| Berkshire Swash | 126/186=0.677419 | 146/186=0.784946 | 126/152=0.828947 |
| Changa One | 128/186=0.688172 | 146/186=0.784946 | 128/152=0.842105 |
| Copse | 127/186=0.682796 | 146/186=0.784946 | 127/150=0.846667 |
| Cormorant Garamond | 132/186=0.709677 | 149/186=0.801075 | 132/151=0.874172 |
| Crete Round | 130/186=0.698925 | 149/186=0.801075 | 130/155=0.838710 |
| Crimson Text | 134/186=0.720430 | 149/186=0.801075 | 134/155=0.864516 |
| EB Garamond | 136/186=0.731183 | 153/186=0.822581 | 136/157=0.866242 |
| Economica | 134/186=0.720430 | 151/186=0.811828 | 134/153=0.875817 |
| Faustina | 136/186=0.731183 | 155/186=0.833333 | 136/161=0.844720 |
| Fjalla One | 131/186=0.704301 | 150/186=0.806452 | 131/156=0.839744 |
| Libre Baskerville | 130/186=0.698925 | 151/186=0.811828 | 130/155=0.838710 |
| Lobster | 127/186=0.682796 | 146/186=0.784946 | 127/148=0.858108 |
| Martian Mono | 128/186=0.688172 | 149/186=0.801075 | 128/155=0.825806 |
| Merriweather | 124/186=0.666667 | 145/186=0.779570 | 124/151=0.821192 |
| Overpass Mono | 127/186=0.682796 | 145/186=0.779570 | 127/149=0.852349 |
| Oxygen Mono | 127/186=0.682796 | 147/186=0.790323 | 127/149=0.852349 |
| PT Mono | 127/186=0.682796 | 146/186=0.784946 | 127/152=0.835526 |
| Pathway Gothic One | 131/186=0.704301 | 149/186=0.801075 | 131/155=0.845161 |
| Patua One | 129/186=0.693548 | 148/186=0.795699 | 129/152=0.848684 |
| Rokkitt | 134/186=0.720430 | 149/186=0.801075 | 134/151=0.887417 |
| Share Tech Mono | 135/186=0.725806 | 152/186=0.817204 | 135/158=0.854430 |

## Family-cluster intervals

5000 whole-family bootstrap draws, seed2242026. All sizes/glyphs/negatives stay with the family. Fixed calibration map never refit. Combined test29 percentile95 intervals are separate from original baseline5; variation is oracle mechanism only. Validation still only5 fonts, intervals exploratory. Per-class CI valid replicate counts are in JSON. No claim of production or real population validity.

| Combined test measure | Point | Family clustered percentile95 |
|---|---|---|
| all_input_recall | 0.699481 | 0.692621 to 0.706711 |
| coverage | 0.799963 | 0.794401 to 0.805525 |
| accepted_precision | 0.849583 | 0.843925 to 0.855441 |
| non_glyph_acceptance | 0.206897 | 0.177340 to 0.236453 |
| raw_top_label_ece | 0.025608 | 0.021310 to 0.030131 |

Full canonical results contain per-class, per-family, per-size confusion/reliability/raw+fitted top-label calibration tables with numerators/denominators and Wilson caveats. Separate-baseline-added-combined.json preserves cohort distinctions. Family-clustered intervals preferred for independent-font uncertainty. Production scorer/head/cleaner effects remain unmeasured.

Dataset plus fixture files are intended for existing requester writer on lab/w-0224-results; bridge upload alone is not branch delivery. No font bytes or weights included. Original source pins and manifest receipts remain in delivered baseline. This incremental archive carries added PNGs, original extension manifest, drop gate, derived combined manifest, scripts and hashes.
