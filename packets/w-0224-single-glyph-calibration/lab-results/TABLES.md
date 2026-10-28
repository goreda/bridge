# W-0224 fixture tables

Arithmetic checks passed on the synthetic fixture scorer. No production scorer or reject-head weights were supplied. No approved-family result rendering has occurred. These values are known by construction, not measured recognition quality.

Each held-out synthetic cohort has 6,200 positive inputs and 40 non-glyph inputs from one synthetic fixture family. Calibration uses a separate synthetic calibration family with the same constructed error mechanism. Validation/test rows do not fit the map.

| Measure | Numerator | Denominator | Value |
|---|---:|---:|---:|
| All-input recall | 4,340 correct accepted | 6,200 positive inputs | 0.700000 |
| Positive-input coverage | 4,960 accepted | 6,200 positive inputs | 0.800000 |
| Accepted precision, negatives included | 4,340 correct | 4,970 all accepted | 0.873239 |
| Accepted-only recall (conditional, not end-to-end) | 4,340 correct | 4,960 accepted positive inputs | 0.875000 |
| Non-glyph false accept | 10 accepted negatives | 40 negatives | 0.250000 |
| Wrong-identity accept | 620 wrong accepted positives | 6,200 positive inputs | 0.100000 |
| Raw top-label ECE | 124 weighted absolute gap | 4,960 accepted positive predictions | 0.025000 |
| Raw top-label Brier | 545.6 squared error sum | 4,960 accepted positive predictions | 0.110000 |
| Calibration-fitted ECE | 0 weighted absolute gap | 4,960 accepted positive predictions | 0.000000 |

Outcome counts per held-out cohort: 5,600 predictions (including 630 head-rejected), 320 typed abstains, 320 missing. Total 6,240. Positive-only abstain and missing counts are310 each. Ten negative abstains and ten negative missing add to the totals. Rejections, abstains and missing never improve all-input recall.

Accepted-only recall here is correct accepted positives / accepted positive inputs whose truth is that class. It is conditional accuracy within the true class, not standard all-input recall. Both are supplied separately as the packet requests.

## Every class

All 62 class rows are in fixture-results.json, in exact labels-62.json order. Per class: correct accepted70/100 all inputs, coverage80/100, accepted-only recall70/80. Accepted precision70/80 for every class except A, which is70/90 because ten non-glyph false accepts predict A. A precision includes those negatives, while calibration intentionally considers only accepted positive glyph predictions. All other per-class counts, intervals, per-font breakdown and render-size breakdown are in JSON.

Confusion pairs: A->B, B->C, ..., 8->9, 9->A, each count10. These are next-label confusions in the pinned order including Z->a and z->0, not alphabetic assumptions.

## Reliability

Raw accepted-positive predictions all fall into [0.9,1.0]: count4,960, correct4,340, accuracy4,340/4,960=.875, mean confidence .9. All other fixed-decile buckets are empty and have null accuracy, not zero accuracy. After the calibration-family binned map, all fall into [0.8,0.9): same count/correct, mean confidence .875. Empty fit bins fall back to the original probability. This perfect fitted result on an identical artificial mechanism is not evidence of real-world transfer.

## Limits

Calibration is top-label, selective, not multiclass calibration. Separate all-input coverage/recall accounts for abstains and missing. Wilson95 intervals are descriptive binomial intervals; rows are not independent font populations. There is no selected identity or reject threshold. Real fonts, recognizer quality, reject quality, cleaner impact and calibration transfer remain unmeasured. The requester runs its frozen scorer and cleaner separately.
