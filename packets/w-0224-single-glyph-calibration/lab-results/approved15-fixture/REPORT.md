# W-0224 approved15 image-pipeline fixture results

FIXTURE METADATA ORACLE ONLY. These are not recognizer accuracy or calibration measurements. No production weights or cleaner available. Exact15 manifest approved by requester commit bc62791dd2dae5a7dccf5df4c27136e22ec3f00b; bridge alternative accepted, named branch landing still requester-owned/pending.

## Coverage

Missing families: none. 15 fonts x62 labels x3 sizes=2790 positives. 315 negatives:135 half-glyph,135 two-glyph,45 blank. Per cohort1035 frames=930 positives+105 negatives, five families. Per class15 positive images across three sizes; only5 independent fonts. Main-size per-class support5. All frames hashed and retained. Rendering fixed em and all margins passed. No new fonts. Identity cleaner only.

The metadata oracle checks exact crop bytes/order, then uses the declared truth and fixed draw schedule. This deliberately tests plumbing and arithmetic, not classification. All3105 row hashes and expected outcome/label/rejection independently rechecked. Blank45 rows typed intake abstain without scorer call. Reject false-accept values below are artificial oracle outcomes.

| Cohort | Correct accepted/all positive | Accepted positives/all positive | Correct/all accepted incl negatives | Raw ECE sum/accepted positives |
|---|---|---|---|---|
| validation | 651/930 = 0.700000 | 742/930 = 0.797849 | 651/762 = 0.854331 | 16.800000/742 = 0.022642 |
| test | 661/930 = 0.710753 | 754/930 = 0.810753 | 661/772 = 0.856218 | 17.600000/754 = 0.023342 |

## Per-family image-fixture results

All sizes pooled; 186 positives+21 negatives per family. Values are oracle schedule behavior, not style-recognition differences.

| Cohort | Family | Recall correct/all positive | Coverage accepted/all positive | Precision correct/all accepted |
|---|---|---|---|---|
| validation | Anonymous Pro | 125/186=0.672043 | 146/186=0.784946 | 125/148=0.844595 |
| validation | Bree Serif | 127/186=0.682796 | 146/186=0.784946 | 127/150=0.846667 |
| validation | Josefin Slab | 134/186=0.720430 | 149/186=0.801075 | 134/155=0.864516 |
| validation | Oswald | 134/186=0.720430 | 151/186=0.811828 | 134/153=0.875817 |
| validation | Vollkorn | 131/186=0.704301 | 150/186=0.806452 | 131/156=0.839744 |
| test | Cutive Mono | 132/186=0.709677 | 149/186=0.801075 | 132/151=0.874172 |
| test | Lora | 136/186=0.731183 | 153/186=0.822581 | 136/157=0.866242 |
| test | Righteous | 136/186=0.731183 | 155/186=0.833333 | 136/161=0.844720 |
| test | Yanone Kaffeesatz | 130/186=0.698925 | 151/186=0.811828 | 130/155=0.838710 |
| test | Zilla Slab | 127/186=0.682796 | 146/186=0.784946 | 127/148=0.858108 |

## Family-clustered intervals

5000 whole-family bootstrap resamples, seed2242026, all repeated sizes/glyphs/negatives travel with their family. Percentile95 is exploratory with just5 families. It cannot validate the production recognizer or population coverage. Calibration map is fixed; never refitted from heldout samples. Per-class recall/coverage/precision/conditional accepted-only intervals are in JSON. Empty bootstrap denominators are counted as invalid replicates, not0. Top-label ECE formula here exploits the fixture constant confidence .9 only.

| Cohort | Measure | Point | Family-clustered percentile95 |
|---|---|---|---|
| validation | all_input_recall | 0.700000 | 0.682796 to 0.717204 |
| validation | coverage | 0.797849 | 0.788172 to 0.807527 |
| validation | accepted_precision | 0.854331 | 0.843008 to 0.867454 |
| validation | non_glyph_acceptance | 0.190476 | 0.114286 to 0.266667 |
| validation | raw_top_label_ece | 0.022642 | 0.010667 to 0.034877 |
| test | all_input_recall | 0.710753 | 0.693548 to 0.726882 |
| test | coverage | 0.810753 | 0.795699 to 0.824731 |
| test | accepted_precision | 0.856218 | 0.844872 to 0.867801 |
| test | non_glyph_acceptance | 0.171429 | 0.114286 to 0.228571 |
| test | raw_top_label_ece | 0.023342 | 0.014625 to 0.032353 |

## Files and limits

Canonical results.json contains explicit numerators/denominators, raw/fitted reliability, per-class/per-font/per-size tables and Wilson intervals. CSVs flatten class rates, reliability and confusions. Family-clustered intervals are separate and preferred for font independence. Known100-draw synthetic fixture is retained separately under verification; do not conflate it with this small image-backed fixture schedule. No threshold selected. No training. All source pins checked. Results support only a runnable open-font image set and arithmetic verification; production correctness/reject/calibration/cleaner effects remain not measured.

Future requester scorer: run harness.py score with your score(image) plugin over this dataset. The output retains end-to-end failures and typed abstains. No font binaries included. Download original files with download_fonts.py; immutable URLs and SHA/OFL receipts in manifest.

Optional stage1b: not attempted in this baseline. Expanding test from5 to30 fonts adds25 families, 25x207=5175 frames (~17MB uncompressed at baseline scale), plus licence/cmap/provenance checks, requester comparison, and a new manifest-hash-bound render gate. No added family is approved by the current receipt.
