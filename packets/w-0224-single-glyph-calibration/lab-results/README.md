# W-0224 calibration harness

Status: stage 1 manifest prepared; result-family rendering blocked pending publication and same-id requester response. No recognizer/reject-head weights available. Fixture numbers prove arithmetic only, not production recognition.

## Reproduce

Python 3.10+, Pillow, NumPy, PyTorch CPU, fontTools (fontTools only needed to inspect manifest cmap). Run from this directory:

```
python3 harness.py verify --out verification
python3 tests.py
python3 download_fonts.py --cache font-cache
python3 harness.py render --out dataset --gate gate.json
python3 harness.py score --dataset dataset/dataset.json --plugin my_plugin.py --out scored
```

No font bytes are included. Download uses immutable manifest URLs and verifies font and own OFL.txt hashes before writing. No data are trained. The download does not render.

`gate.json` records actual bridge publication URL, manifest SHA256, same_id W-0224, response `manifest ok` or `drop/replace`, and `drop_families` list for the latter. This is a local safety check, not an authentication mechanism. Supply only the actual response. A drop list excludes those families and yields a partial approved-family set; replacements require an updated posted manifest and requester comparison. No answer means no render. This code intentionally cannot publish or create a repo.

## Source semantics

All nine intake payloads are verified against original PINS. labels-62.json owns class order. Identity cleaner is used only for clean black-on-white renders. Product cleaner is absent. Full frame stays on disk. Intake crops exactly gray <128, then invokes the original pinned data.py preprocess on that tight crop. data.py does the declared grayscale, inversion=false, crop at int(round(.5*255))=128, bilinear height105/aspect/width-cap resize and white fill. No rewritten approximation is used. Tensor shape/value geometry and blank refusal are verified independently on synthetic rectangles. The scorer receives the tight PIL crop, as the pinned production scorer expects, and may repeat that same preprocess. This is deliberate, not full-frame substitution.

Plugins expose `create_scorer()` returning object with `score(tight_crop)` and return Prediction, typed Abstain, None (missing), CropScore, or top-label tuple. Prediction fields include explicit reject_available and rejected. A generic tuple's optional third item is NOT treated as a reject score because pinned seg402 uses log probability there. Wrap a genuine reject-head scorer to supply an explicit acceptance decision. No reject cutoff is guessed. CropScore.pack_refused maps to typed abstain. Exceptions fail the run rather than quietly becoming missing predictions.

Blank frames produce typed intake TileNoInk without calling the scorer: product intake refuses these before scoring. The reject-head false-accept measurement is therefore end-to-end, not a claim to probe the head directly on blank pixels. The pinned cleaner is not run.

## Dataset and metrics

15 whole families, no split overlap; each split has one text, display, slab, mono and condensed family. SHA256, OFL evidence, immutable URLs and variable defaults are in manifest. Current fonts are neither named DejaVu/Noto nor identified by upstream provenance as derivatives; requester comparison is mandatory. Classes are 62 original file labels. One clean glyph per class, family and render size. 384px/256em main; 256px/170em and 512px/341em sensitivity. Ink bbox centred, all pixels at least frame/12 from borders. Border failure aborts rather than changes em silently. Light default variable weights (Josefin 100, Yanone 200) are intentional recorded defaults, not all regular400.

Negatives per family and size: A/a/0 half glyphs (right half of frame erased), A/a/0 two-glyph crops (two half-scale copies), one blank. Source characters are recorded. These are constructed out-of-contract negatives; some half-glyphs may resemble genuine glyphs. They are not a broad natural non-character distribution. Main report support per heldout cohort: 5 fonts x62 labels x3 sizes=930 positive images plus105 negatives. Per class only15 images, correlated across sizes; per-size class support5. Never claim broad style generalization.

All-input recall: correct accepted / all positive inputs of class. Coverage: accepted / all positive inputs. Accepted-only recall: correct accepted / accepted inputs whose truth is that class. Accepted precision: correct accepted / all accepted predictions of that label, INCLUDING negative false accepts. Missing, typed abstain and head rejection remain failures in all-input recall. Counts split these outcomes. Wrong-label acceptance denominator is all positive inputs; non-glyph acceptance denominator is all negatives. Reject-head metrics are null if any scored output lacks explicit head acceptance semantics. Confusions are accepted wrong positives, count-sorted.

Calibration is selective top-label calibration on accepted positive predictions. It is NOT full multiclass calibration because the interface has only top1 probability. Every reliability/ECE/Brier output declares its scored denominator and unaccepted count; all-input performance is separate. Per-class calibration groups by PREDICTED class and excludes negatives (precision still includes negatives). Fixed decile reporting edges were declared before outcomes. Only calibration families fit a binned confidence->empirical correctness mapping. Empty calibration bins use identity. Validation/test outcomes never fit or tune. Both raw and fitted heldout metrics reported. No cutoff is selected/recommended. Predefined buckets need no validation tuning.

Wilson95 intervals are descriptive input-wise binomial intervals, not family-cluster intervals. Repeated sizes and glyphs within font are correlated. Per-font and per-size breakdowns expose this. Test outcomes must not feed any revision of calibration or reporting design.

## Fixture verification

Synthetic metadata oracle, NOT image recognition. Per class and heldout cohort, 100 rows:70 correct accepted,10 next-label confused accepted,10 head-rejected,5 typed abstain,5 missing. Confidence .9 for accepted. Plus40 negatives:10 false accepted as A,10 rejected,10 abstain,10 missing. Therefore each class all-input recall70/100, coverage80/100, accepted-only recall70/80. Precision70/80 except A70/90 due to negatives. Raw ECE |.9-.875|=.025, top-label Brier .11, non-glyph false accept10/40. Calibration-fitted ECE zero on an identical constructed mechanism is expected and says nothing about real generalization. Every known result is asserted. Tables are only validation/test, never calibration fit rows.

## Output

JSON is the lossless canonical table format. `TABLES.md` summarizes fixture checks. Each output file SHA256 appears in OUTPUT-SHA256.json except that receipt itself (avoids circular hash). Dataset and predictions retain row hashes and source provenance. Run-time versions are recorded in verification. No credentials, font bytes, owner images or absolute private paths belong in a returned packet. Original source has public provenance comments; no account use or production weights.

## Review fixes v1.2

All evaluation rows are validated before any fit/report: known cohorts, all cohorts present, calibration has accepted labeled predictions, valid labels/status, unique row IDs, family and font SHA256 split disjointness. Real-font rows require exact manifest family membership/hash/cohort match. Manifest itself refuses repeated families and cross-cohort duplicate binaries. Dataset scoring verifies its embedded manifest against the supplied manifest file SHA256 before invoking the scorer, then preflights row provenance. The synthetic oracle has an explicit fixture provenance tag and separate synthetic family hashes per split, not a claim to be from the real font manifest. Input count reconciliation is reported across all three cohorts; validation/test totals exactly match all rows minus calibration. Unknown cohorts and absent calibration fail closed.

## Partial results v1.3

Dataset explicitly lists whole missing families (for example names dropped by the requester). Evaluation verifies the list exactly matches missing manifest families, rejects unknown names or a declared-missing family with rows, and retains all cohort/hash/assignment checks. A wholly missing validation or test cohort is `not_measured` with null metrics, never a zero-support performance table. Status and missing-family/cohort lists are in JSON and RESULTS-STATUS.md. CSV export skips unavailable metrics. Missing/unscored calibration returns typed `partial_refusal`, no fitted map and no fabricated metrics, when the partial input is explicitly declared. Without a declared partial, absent cohorts/unscored calibration still refuse. Ordinary partial reports with usable calibration fit only existing calibration rows. No answer still means no render.
