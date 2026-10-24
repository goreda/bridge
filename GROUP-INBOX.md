# Group inbox

## to group: two-lab sharing of the research inbox and file bridge
- date: 2026-10-25
- from: 1nstinct owner, relayed by gdb (peer-attributed)
- note: faithful English translation of the supplied Turkish text, under the repo English rule.
- the group lab is now named 1nstinct; a second group lab, in2tinct, will join soon. before connecting, we want your proposal. decision: how should two group labs share the research inbox and the file bridge?

## re: in2tinct connection
- date: 2026-10-25
- by: goreda
- opinion and proposal only; no connection, policy, adoption or execution decided here.
- (a) channel: one shared repo, one inbox file per group (1nstinct keeps GROUP-INBOX.md, in2tinct gets its own inbox file), one shared guide; two groups writing one page with a "for:" line invites write races and ordering disputes (support: single-writer serialized-write practice on GROUP-INBOX.md).
- (b) division of work: one shared W- pool with an explicit claim line per entry; split by research area needs an adjudicator for overlap, and planned double execution doubles cost without adding a claim record (support: the shared W-0001..W-0033 pool).
- (c) claiming and double-work guard: claim before work, first claim wins, every entry carries a "by: <group>" field; two claim entries for the same W- id are the detectable failure signal (support: the "re: W-xxxx received" receipt practice).
- (d) open W- stock: one shared minimum of 15 across both groups, not 15 per group; the 2-hour card-consumption expectation binds the claiming group from its claim time, not from posting time (support: GROUP-GUIDE.md v4 open-stock and consumption rules).
- (e) guide and durable memory: in2tinct adopts the same GROUP-GUIDE.md contract and keeps its own durable ledger of claims, results and closures; each group records its own receipts and closures in its own inbox (support: GROUP-GUIDE.md v4).
- (f) privacy: with two reading groups every public entry must assume the wider readership: no group-private identifiers, internal locators or unvetted internals; lab names stay consistent once chosen (support: existing public-safe review practice on this bridge).
- (g) top 3 risks: (1) duplicate work from stale reads - early detection: two claim entries for the same W- id; (2) ledger divergence on open stock or closure - early detection: periodic reconciliation exchanges, count mismatch is the signal (support: the 2026-10-25 W-0005/6/7 reconciliation); (3) attribution disputes - early detection: any entry missing its "by:" field.
- recommendation: one shared guide, per-group inbox files, one shared W- pool with claim lines and "by:" fields; this extends proven single-lab practice with the smallest change.
- needed from the owner, one item: in2tinct's intended scope (which research areas it will cover); without it the division-of-work choice in (b) stays provisional.

common preamble (applies to all nine entries): every proposed count, threshold and sample size is a requester-side research-design proposal, not an owner decision; the pilot validates the design. every pilot delivers: the method, the actual data and tool list with license names and URLs (no unknown-license substitution, no unnamed sources), code that installs and runs from a fresh directory, and one sample table - then waits for the named "re: W-xxxx pilot ok" entry before any full run. a successful measurement means a finite full table: every planned cell present, each marked measured, excluded, failed or not run, with all denominators explicit and the result files hashed. no cell is silently dropped.

## W-0025 ranking OCR candidate segmentations with a small open language model
- date: 2026-10-25
- request: ranking OCR candidate segmentations with a small open language model.
- decision: whether a small open language model improves picking the correct segmentation among candidate splits of a printed text line, before the consuming segmentation work adopts a scorer.
- inputs: one open n-gram toolkit or tiny open model with a stated license; candidate segmentations produced locally from open-font rendered lines (proposal: about 200 lines with known correct segmentation); public-domain or CC0 English text as the scoring corpus. actual toolkit, corpus and license names are delivered in the pilot, not assumed now.
- unit: one text line with >=2 candidate segmentations.
- measure: top-1 correct-segmentation rate with the model versus a no-model length/geometry baseline, both on the same candidates. proposal: report the delta in points; no minimum claimed.
- priority: today; the consuming segmentation improvement can use a scorer once measured.
- depends on: none.
- pilot: method, actual toolkit + corpus names with licenses, install-and-run code, one sample table of about 20 lines; then wait for "re: W-0025 pilot ok".
- done when: full code plus the comparison table (model vs baseline, per line class) as text on a files page.
- out of scope: training a new language model; recognition accuracy of characters themselves; any non-public text.

## W-0026 binarization methods for degraded scanned text, measured
- date: 2026-10-25
- request: binarization methods for degraded scanned text, measured.
- decision: which open binarization method should preprocess degraded images before segmentation, chosen on measured downstream effect rather than appearance.
- inputs: open implementations of otsu, sauvola and niblack (or equivalent named open methods, actual names and licenses in the pilot); synthetic degradations (blur, noise, uneven illumination) applied to open-font renders (proposal: about 500 images). ground truth: per-character boxes from the same render, with the alignment definition between rendered glyphs and ground-truth boxes stated exactly; the segmentation baseline is a fixed, named held configuration, unchanged across methods. note: this measures synthetic degradation only; it does not prove the winner on real scans.
- unit: one degraded text image.
- measure: downstream character IoU and exact-split rate per method against the fixed baseline, plus runtime per image; every split-rate denominator explicit (characters expected, produced, matched, missed).
- priority: today; consuming capture and segmentation work preprocesses degraded images.
- depends on: none.
- pilot: method list with actual implementation names + licenses, the degradation recipe, the alignment definition, install-and-run code, one sample table of about 50 images; then wait for "re: W-0026 pilot ok".
- done when: full code plus the ranked table (per degradation type) as text on a files page.
- out of scope: new binarization algorithms; camera-capture hardware tests; any real-scan claim from synthetic data.

## W-0027 estimating stem width and contrast from glyph bitmaps
- date: 2026-10-25
- request: estimating stem width and contrast from glyph bitmaps.
- decision: whether stem width and contrast can be recovered from rendered glyph bitmaps accurately enough for letterform parameter fitting.
- inputs: TWO source kinds kept separate: (1) synthetic outlines generated with analytically KNOWN stem width and contrast (ground truth by construction), and (2) real open-licensed fonts (OFL) where outputs are estimates only - shipped font files do not publish stem width or contrast, so no real-font ground truth is claimed. actual font names + licenses in the pilot.
- unit: one glyph at one size.
- measure: on the synthetic set, estimation error against the known parameters; on the real set, estimate distributions per family labeled unverified estimates. proposal: about 40 synthetic glyphs and about 5 real families.
- priority: later; consuming letterform-fitting work follows higher-priority quality work.
- depends on: none.
- pilot: synthetic outline generator, method, install-and-run code, one sample table of about 5 glyphs; then wait for "re: W-0027 pilot ok".
- done when: full code plus the error table (synthetic) and the estimate table (real, labeled) as text on a files page.
- out of scope: hinting; non-latin scripts; claiming designer intent from estimates.

## W-0028 simple metrics for frame-exact hard-cut detection
- date: 2026-10-25
- request: simple metrics for frame-exact hard-cut detection.
- decision: which simple open metric (luma delta, histogram distance, SSIM) the video transition tooling should trust to localize hard cuts, measured against frame-exact ground truth.
- inputs: open-licensed films (for example Blender Foundation; actual titles and license URLs in the pilot). ground truth procedure: manually inspect adjacent decoded frames to label shot changes, and bind the first post-cut frame to its original PTS; an independent second pass adjudicates ambiguous ramp/flicker cases separately; the metric under test is never used to build the ground truth. clips are excerpts; every clip names its parent film (title and URL) and cuts from the same parent are listed as related, not counted as independent. the set covers constant-frame-rate and variable-frame-rate sources at native resolution and native frame timing - no upscaled, re-timed or re-encoded sources (CFR/VFR/native definitions stated in the method). include brightness-matched cut pairs and flash/motion sequences as negative controls. proposal: about 20 cuts plus negatives.
- unit: one labeled cut transition.
- measure: recall and landing latency in frames over the WHOLE labeled cut population - the worst case is reported explicitly, not only a median - per metric and threshold; false fires on the negative controls counted separately.
- priority: now; the consuming cut-synchronized transition work needs trustworthy frame-exact ground truth first.
- depends on: none.
- pilot: the manual-labeling + PTS-binding procedure, actual film titles + licenses, install-and-run code, one sample table of about 3 labeled cuts; then wait for "re: W-0028 pilot ok".
- done when: full code plus the recall/latency table (including negatives and the second-pass adjudication list) as text on a files page.
- out of scope: neural detectors; gradual transitions (dissolves, fades); player internals.

## W-0029 fitting film-grain parameters, measured
- date: 2026-10-25
- request: fitting film-grain parameters, measured.
- decision: which open fitting method recovers grain parameters (grain size, strength) well enough for a synthesis feature.
- inputs: open grain-synthesis models with stated licenses (actual names in the pilot); TWO evaluation kinds kept separate: (1) synthetic frames rendered with KNOWN grain parameters - one unit is a clean/grained pair with ground truth by construction; (2) real open-licensed film frames - one unit is ONE frame plus an explicitly stated estimated-grain or residual reference, NOT a true clean reference (a real clean reference is usually not held), so real-kind results are plausibility-only. proposal: about 10 units per kind.
- unit: one synthetic pair, or one real frame with its declared reference.
- measure: on the synthetic kind, parameter recovery error; on the real kind, a stated visual-difference metric labeled qualified. proposal: methods ranked on recovery error, no fixed bound claimed.
- priority: later; the consuming synthesis feature follows higher-priority transition work.
- depends on: the earlier grain-synthesis survey (done).
- pilot: fitting method, actual model names + licenses, install-and-run code, one sample table of 2 units; then wait for "re: W-0029 pilot ok".
- done when: full code plus both tables (synthetic recovery, real qualified) as text on a files page.
- out of scope: new synthesis models; scanner-profile estimation; claiming ground truth on real film.

## W-0030 sharpening methods ranked by a declared halo proxy
- date: 2026-10-25
- request: sharpening methods ranked by a declared halo proxy.
- decision: which open sharpening method the image pipeline should prefer when minimizing halo at a matched objective sharpness level.
- inputs: open implementations (unsharp mask variants, guided filter, bilateral or equivalent named methods; actual names + licenses in the pilot); open image sets with license URLs. sharpness matching uses a DECLARED OBJECTIVE PROXY (stated metric, for example mean edge gradient), NOT a perceptual claim - no human or perceived-sharpness claim is made. proposal: about 30 images.
- unit: one image at one matched proxy level.
- measure: the declared halo proxy near strong edges at matched objective sharpness, per method. proposal: methods ranked on the proxy pair, no perceptual statement.
- priority: later; the consuming sharpening feature follows higher-priority transition work.
- depends on: the earlier measured unsharp-mask limits result (done).
- pilot: method list with actual names + licenses, the two proxy definitions, install-and-run code, one sample table of 5 images; then wait for "re: W-0030 pilot ok".
- done when: full code plus the ranked table as text on a files page.
- out of scope: human perception studies; video temporal filtering; any "looks better" claim.

## W-0031 open rasterizer differences on identical outlines
- date: 2026-10-25
- request: open rasterizer differences on identical outlines.
- decision: how much rendering results differ between open rasterizers on identical outlines, so cross-platform font checks know their tolerance.
- inputs: freetype and at least one other open rasterizer (actual names, versions, licenses in the pilot); open-licensed fonts (OFL). controls: the SAME known outline on both sides, hinting OFF, matched pixel size, matched grid fitting and matched antialiasing mode - otherwise pixel differences mix causes; the control settings are stated in the method. proposal: about 100 glyphs at 3 sizes.
- unit: one glyph at one size on one rasterizer pair.
- measure: pixel-difference distribution per pair and size under the stated controls, systematic bias broken out by curve type. proposal: differences reported, no acceptable-bound claimed.
- priority: later; consuming cross-platform verification follows higher-priority kit work.
- depends on: none.
- pilot: actual rasterizer list with versions, the control settings, install-and-run code, one sample table of 10 glyphs at one size; then wait for "re: W-0031 pilot ok".
- done when: full code plus the difference tables with the environment pinned as text on a files page.
- out of scope: proprietary rasterizers; hinting bytecode execution; font content quality.

## W-0032 open font-validation tools against seeded errors
- date: 2026-10-25
- request: open font-validation tools against seeded errors.
- decision: which open font-validation tool a release check should run, chosen by measured detection of seeded faults.
- inputs: open validators (for example fontbakery, opentype-sanitizer; actual names, versions, licenses in the pilot); a seeded-error corpus built from open-licensed fonts with each seeded fault documented. proposal: about 50 faults across 5 classes.
- unit: one seeded fault (detection) or one clean font (false positive).
- measure: detection rate per fault class and false-positive rate on unmodified fonts. proposal: tools ranked, no fixed detection bound claimed.
- priority: later; the consuming release-check work follows higher-priority kit work.
- depends on: none.
- pilot: actual tool list with versions + licenses, seeding method, install-and-run code, one sample table of 10 faults; then wait for "re: W-0032 pilot ok".
- done when: full code plus the detection table and the corpus as text on a files page.
- out of scope: writing a new validator; commercial font QA services.

## W-0033 reproducible timing for small CLI benchmarks on shared machines
- date: 2026-10-25
- request: reproducible timing for small CLI benchmarks on shared machines.
- decision: a measurement recipe (warmup, repetitions, statistic) that makes small CLI benchmark numbers reproducible on shared, unpaid machines.
- inputs: a fixed toy workload with its code published; run location: local or shared unpaid CPU only, the actual machine class named in the report; public datasets only - no new CI account, no paid runner, no new public repo is created for this work.
- unit: one benchmark run.
- measure: run-to-run variance of the toy workload; the reported confidence quantity is defined exactly (half-width of the 95 percent confidence interval of the mean, as a percentage of the mean) and the recipe states how many repetitions keep that quantity small. proposal: about 30 repeated runs across at least 2 days; no fixed variance bound claimed.
- priority: later; consuming benchmark work adopts the recipe when measured.
- depends on: none.
- pilot: workload install-and-run code, the timing method, one sample table of 5 runs; then wait for "re: W-0033 pilot ok".
- done when: the recipe plus the measured variance numbers as text on a files page.
- out of scope: paid infrastructure; GPU timing; new hosted accounts.

## re: W-0008 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0009 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0013 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0014 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0015 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0016 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0017 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0018 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0020 received
- date: 2026-10-25
- pickup: 2026-10-25 00:30 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0002 received
- date: 2026-10-25
- pickup: 2026-10-25 00:03 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0004 received
- date: 2026-10-25
- pickup: 2026-10-25 00:03 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0011 received
- date: 2026-10-25
- pickup: 2026-10-25 00:03 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

## re: W-0019 received
- date: 2026-10-25
- pickup: 2026-10-25 00:03 Europe/Istanbul
- receipt only; not a pilot ok, not a consumed receipt.

Newest first. Entry IDs: W-0001 upward. Fields: date, subject, request.

## re: W-0021 correction
- date: 2026-10-25
- subject: synthetic-to-real transfer for character segmentation - source limits defined
- correction: requesting side, research-design proposal; not an owner threshold. The pilot validates the design.
- changed: inputs; old: at least 2 public scanned-document datasets with character-level ground truth (or line images with aligned text), open licenses; new: at least 2 public datasets of REAL scans - images produced by a physical scanner or camera from printed pages, with the capture documented; re-rendered, synthesized or OCR-generated images are NOT real scans and may be reported only separately, labeled as such. character-level ground truth means per-character boxes, or line images with aligned text plus a stated alignment method. every dataset carries license evidence (URL and license name). datasets that lack character-level ground truth are refused and listed with the reason (expected refusals), never silently substituted.
- changed: measure; old: exact, merged, over-split and lost-fragment rates per method on real scans, with the same definitions as the synthetic benchmark; the transfer gap (synthetic minus real exact rate) per method (requester proposal, not an owner decision; subject to pilot approval: flag if the gap exceeds 10 points for the synthetic winner); new: the same rates and gap, with a successful measurement meaning the full table over the whole dataset: every denominator explicit (characters measured, excluded, failed, not run), metric definitions and units stated, no cell silently dropped.
- decision, unit, priority, depends on, pilot, done when, out of scope: unchanged from the original entry.

## re: W-0023 correction
- date: 2026-10-25
- subject: frame-exact timestamp alignment across open video decoders - source limits defined
- correction: requesting side, research-design proposal; not an owner threshold. The pilot validates the design.
- changed: inputs; old: open-licensed clips (CC-BY or similar) including at least one variable-frame-rate clip; at least 2 open decode paths (for example two ffmpeg seek modes or two ffmpeg versions); new: a clip is one contiguous excerpt from one parent source; every clip names its parent source (title and URL) and license. the set covers at least one constant-frame-rate and one variable-frame-rate container, chosen to vary decoder/container/time-base seams; native source resolution and native frame timing as published - no upscaled, re-timed or re-encoded-to-CFR sources. at least 2 open decode paths.
- changed: measure; old: frame mismatch count at identical nominal timestamps (off-by-one rate in percent) and the presentation-timestamp disagreement distribution per decode path (requester proposal, not an owner decision; subject to pilot approval: 0 mismatches on constant-frame-rate clips; a documented bounded rule for variable-frame-rate clips); new: the same metrics, with the measurement-success reference stated before measuring: a documented sampling/seek rule per decode path (how a nominal timestamp maps to a frame). success means the mismatch and PTS-disagreement tables exist for every clip x decode-path cell, with every denominator explicit and every unreadable or undecodable cell listed as failed or not run, never silently dropped.
- decision, unit, priority, depends on, pilot, done when, out of scope: unchanged from the original entry.

## guide v4 effective 2026-10-25 00:19
- date: 2026-10-25
- GROUP-GUIDE.md is now v4, effective 2026-10-25 00:19 (Europe/Istanbul). Changes are in its "v4 changes" section: contract scope (new W- requests only), pilot estimate and 1-hour rule, install check, page cadence, receipts, questions, evidence.
- running requests continue as they are unless an entry "re: W-xxxx correction" gives the contract fields. v4 is not a pilot approval for any running request.

## W-0021 synthetic-to-real transfer for character segmentation
- date: 2026-10-25
- request: synthetic-to-real transfer for character segmentation.
- decision: whether the segmentation method ranking measured on synthetic data transfers to real scanned pages, before the consuming segmentation improvement adopts the synthetic winner.
- inputs: at least 2 public scanned-document datasets with character-level ground truth (or line images with aligned text), open licenses; the top methods from the earlier synthetic benchmark.
- unit: one scanned text line.
- measure: exact, merged, over-split and lost-fragment rates per method on real scans, with the same definitions as the synthetic benchmark; the transfer gap (synthetic minus real exact rate) per method. requester proposal, not an owner decision; subject to pilot approval: flag if the gap exceeds 10 points for the synthetic winner.
- priority: today; the consuming text-segmentation improvement waits for transfer evidence before adopting a method.
- depends on: the earlier synthetic benchmark (done).
- pilot: yes - dataset list with licenses, method, one sample table, then wait for "re: W-0021 pilot ok" before the full run.
- done when: full code plus the transfer table (per method, synthetic rate versus real rate) as text on a files page.
- out of scope: training new methods; recognition accuracy; non-public scans.

## W-0022 font metric extraction accuracy across open tools
- date: 2026-10-25
- request: font metric extraction accuracy across open tools.
- decision: which open tool the letterform research trusts for extracting sidebearings and kerning from font files, since every spacing comparison depends on those numbers being right.
- inputs: at least 20 open-licensed fonts (OFL); at least 2 independent open extractors (for example fontTools and a FreeType-based reader).
- unit: one glyph metric (left or right sidebearing) or one kerning pair.
- measure: extractor agreement rate in percent and value deltas in font units, per font, with discrepant cases listed by glyph. requester proposal, not an owner decision; subject to pilot approval: sidebearing agreement should exceed 99.9 percent of glyphs.
- priority: later; consuming spacing-comparison work follows higher-priority work.
- depends on: none.
- pilot: if the comparison grows beyond about 2 hours, deliver the method, the font list and one sample table first and wait for "re: W-0022 pilot ok".
- done when: full code plus the agreement tables (per font, per extractor pair) as text on a files page.
- out of scope: spacing or kerning algorithm quality; proprietary font tools.

## W-0023 frame-exact timestamp alignment across open video decoders
- date: 2026-10-25
- request: frame-exact timestamp alignment across open video decoders.
- decision: which decode and seek method the video verification tooling trusts for frame-exact before/after comparison, since ordinal frame matching breaks on variable-frame-rate content.
- inputs: open-licensed clips (CC-BY or similar) including at least one variable-frame-rate clip; at least 2 open decode paths (for example two ffmpeg seek modes or two ffmpeg versions).
- unit: one decoded frame at a requested timestamp.
- measure: frame mismatch count at identical nominal timestamps (off-by-one rate in percent) and the presentation-timestamp disagreement distribution per decode path. requester proposal, not an owner decision; subject to pilot approval: 0 mismatches on constant-frame-rate clips; a documented bounded rule for variable-frame-rate clips.
- priority: later; the verification tooling improvement follows higher-priority transition work.
- depends on: none; the earlier cpu-only decode-compare tool motivates this request.
- pilot: yes - method, clip list with licenses, one sample table, then wait for "re: W-0023 pilot ok" before the full run.
- done when: full code plus the mismatch tables per decode path and clip type as text on a files page.
- out of scope: filter verification itself; proprietary players or codecs.

## W-0024 open vector curve simplification for glyph outlines
- date: 2026-10-25
- request: open vector curve simplification for glyph outlines.
- decision: which open simplification method reduces glyph outline node count with the least shape loss, so the vectorization quality work can separate tracer noise from necessary detail.
- inputs: glyph outlines from at least 20 open-licensed fonts (OFL); at least 3 open simplification methods (for example Ramer-Douglas-Peucker variants, fitcurve-style bezier fitting, Visvalingam).
- unit: one glyph outline.
- measure: node count reduction in percent versus shape error (intersection-over-union against the original outline at a fixed raster size). requester proposal, not an owner decision; subject to pilot approval: report any method reaching at least 30 percent node reduction at IoU at least 0.995.
- priority: later; consuming vector-quality comparison follows higher-priority work.
- depends on: none.
- pilot: yes - method, font list with licenses, one sample table, then wait for "re: W-0024 pilot ok" before the full run.
- done when: full code plus the reduction-versus-error table per method and font as text on a files page.
- out of scope: bitmap tracer comparison; hinting or font-production advice.

## re: W-0020 correction
- date: 2026-10-24
- subject: public glyph-rendering benchmark - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: a reusable public benchmark the consuming open-source segmentation work can adopt as its standard input set.
- inputs: the full ASCII set from at least 50 open-licensed fonts (OFL) at 5 sizes with ground-truth character boxes and 4 degradation levels.
- unit: one rendered text-line image.
- measure: a manifest with per-font license and image counts, plus a baseline segmentation score (merged, over-split and lost-fragment rates in percent) from one simple baseline method, so later methods have a fixed comparison point.
- priority: today; the text-segmentation improvement adopts it when ready.
- depends on: none (W-0002 may migrate to this benchmark later).
- pilot: yes - method, font list with licenses, one sample page, then wait for "re: W-0020 pilot ok" before the full run.
- done when: the generation code, the dataset manifest with licenses and counts, and the baseline numbers as text on a files page.
- out of scope: non-ASCII scripts; recognition accuracy.

## re: W-0019 correction
- date: 2026-10-24
- subject: augmentation effect on character recognition - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: whether degradation augmentation improves a small recognizer's accuracy on degraded printed text.
- inputs: a public printed-text dataset; the W-0018 degradation pipeline if validated, otherwise an own simulation; a small open character recognizer.
- unit: one training run.
- measure: accuracy delta on clean and degraded test sets in percent, with at least 3 training runs per arm so variance is reported, not a single lucky run.
- priority: today; a character-recognition training comparison waits for it.
- depends on: W-0018 (uses its pipeline if ready).
- pilot: yes - method, dataset list with licenses, one sample run table, then wait for "re: W-0019 pilot ok" before the full runs.
- done when: full code, the accuracy table with run variance, and the augmentation parameter list as text on a files page.
- out of scope: production OCR systems; large models.

## re: W-0018 correction
- date: 2026-10-24
- subject: degraded-scan simulation - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: whether a synthetic scan-degradation pipeline is realistic enough to train and test character recognition against.
- inputs: a degradation pipeline (blur, noise, ink bleed, broken strokes, rotation); at least 2 public scanned-text datasets for comparison.
- unit: one image.
- measure: degradation statistics on real versus synthetic images (for example stroke-width and noise-histogram distances); the statistics and acceptance thresholds are requester proposals in the pilot, not owner decisions, subject to pilot approval.
- priority: today; a character-recognition training comparison waits for it.
- depends on: none.
- pilot: yes - method, dataset list with licenses, one sample comparison, then wait for "re: W-0018 pilot ok" before the full run.
- done when: the full pipeline code, the realism comparison numbers, and example image grids as text on a files page.
- out of scope: recognition training itself (W-0019); non-public datasets.

## re: W-0017 correction
- date: 2026-10-24
- subject: automatic kerning pair generation - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: whether outline-derived kerning proposals agree with the kerning pairs fonts already ship, as a comparison baseline for consuming spacing research.
- inputs: at least 20 open-licensed fonts that ship designer kerning pairs; a python prototype of an open outline-based kerning method.
- unit: one kerning pair.
- measure: agreement rate in percent, overshoot in font units, and missed-pair rate in percent, per font; designer pairs are a reference, not a universal truth.
- priority: today; consuming letterform-spacing research waits for it.
- depends on: none.
- pilot: yes - method, font list with licenses, one sample table, then wait for "re: W-0017 pilot ok" before the full run.
- done when: full code, the evaluation table, and a list of pair classes where the method disagrees most, as text on a files page.
- out of scope: treating designer pairs as ground truth for scoring the method as wrong.

## re: W-0016 correction
- date: 2026-10-24
- subject: automatic letter spacing - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: how closely an open letter-spacing method reproduces each font's designed spacing per glyph class, as a comparison baseline for consuming spacing research.
- inputs: at least 20 open-licensed fonts; a python prototype of an open spacing method (for example the HT LetterSpacer approach).
- unit: one glyph in one font.
- measure: deviation of computed sidebearings from the font's designed spacing per glyph class, in font units and in percent of em; the designed spacing is one designer's reference, not a universal truth - deviation is reported as comparison, not error.
- priority: today; consuming letterform-spacing research waits for it.
- depends on: none.
- pilot: yes - method, font list with licenses, one sample table, then wait for "re: W-0016 pilot ok" before the full run.
- done when: full code, the deviation table per font and glyph class, and known failure shapes as text on a files page.
- out of scope: claims that the designer spacing is wrong; hinting or rendering.

## re: W-0015 correction
- date: 2026-10-24
- subject: tracer quality vs render resolution - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: the cheapest render resolution that reaches 99% of a tracer's IoU plateau, so consuming vectorization research does not over-render.
- inputs: the 2 best open tracers from W-0014 (or chosen independently if W-0014 is not finished); at least 8 render sizes per glyph.
- unit: one glyph at one render size.
- measure: IoU versus resolution curve and node-count growth curve; the plateau point is the smallest resolution reaching 99% of the maximum measured IoU.
- priority: today; a glyph vectorization quality comparison waits for it.
- depends on: W-0014 (optional).
- pilot: yes - method, font list with licenses, one sample curve, then wait for "re: W-0015 pilot ok" before the full run.
- done when: full code, the resolution curves, and the plateau table as text on a files page.
- out of scope: non-open tracers; runtime performance claims beyond node count.

## re: W-0014 correction
- date: 2026-10-24
- subject: open image tracers compared - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: which open bitmap tracer is the reference baseline for glyph vectorization quality.
- inputs: rendered glyphs from at least 20 open-licensed fonts (OFL) at several sizes; at least 3 open-source tracers (for example potrace, autotrace, vtracer).
- unit: one glyph at one render size.
- measure: intersection-over-union against the vector original (0-1), node count per glyph, and corner-handling failure examples; no fixed ranking threshold - the full table decides.
- priority: today; a glyph vectorization quality comparison waits for it.
- depends on: none.
- pilot: yes - method, font list with licenses, one sample table, then wait for "re: W-0014 pilot ok" before the full run.
- done when: full code, the per-font result table, and failing-case examples as text on a files page.
- out of scope: proprietary tracers; hinting or font-production advice.

## re: W-0013 correction
- date: 2026-10-24
- subject: sharpening parameter study - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: the strongest sharpening setting with no measurable halo per resolution, for consuming video-filter research.
- inputs: open-licensed frames at 480p, 1080p and 2160p - native-resolution sources, not upscaled (any generated downscale is labeled as such) - and scaling ratios from 1x to 4x; at least 100 unsharp-mask parameter combinations.
- unit: one parameter combination on one frame.
- measure: an open halo/ringing metric defined in the pilot; the strongest setting whose halo metric stays within the noise floor per resolution (noise floor defined in the pilot as a requester proposal, not an owner decision, subject to pilot approval).
- priority: later; consuming grain/sharpening comparison follows higher-priority transition work.
- depends on: none.
- pilot: yes - method, metric definition, data and license list, one sample table, then wait for "re: W-0013 pilot ok" before the full run.
- done when: the metric definition, the full sweep code, and the result table as text on a files page.
- out of scope: subjective sharpness preference; proprietary filters.

## re: W-0012 correction
- date: 2026-10-24
- subject: film grain parameter study - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- changed: inputs: at least 20 open-licensed film clips -> inputs: at least 20 open-licensed film clips, each from a different source film
- decision: whether fitted grain parameters are stable enough per resolution to be reused by consuming video-filter research.
- inputs: at least 20 open-licensed film clips, each from a different source film, at 480p, 1080p and 2160p - native-resolution sources, not upscaled; an open estimator (for example AV1-style AR fitting).
- unit: one clip at one resolution.
- measure: fitted grain strength and cutoff per resolution, plus fit stability across scenes (per-clip coefficient of variation; the stability threshold is a requester proposal in the pilot, not an owner decision, subject to pilot approval).
- priority: later; consuming grain/sharpening comparison follows higher-priority transition work.
- depends on: W-0011 for method choice (or an independently chosen open estimator).
- pilot: yes - method, data and license list, one sample table, then wait for "re: W-0012 pilot ok" before the full run.
- done when: full code, the per-clip parameter table, and a note on which resolutions break the model, as text on a files page.
- out of scope: designing a new estimator; upscaled sources counted as native.

## re: W-0011 correction
- date: 2026-10-24
- subject: film grain models survey - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: which grain representation consuming video-filter research should adopt for synthesis and measurement.
- inputs: open literature and specifications (for example the AV1 film grain synthesis model and AR-coefficient fitting), with citations.
- unit: one surveyed method.
- measure: a comparison table of at least 3 methods: how grain size and strength are represented per resolution and codec format, with citations for each claim.
- priority: later; consuming grain/sharpening comparison follows higher-priority transition work.
- depends on: none.
- pilot: if the survey grows beyond about 2 hours, deliver the method and source list with one sample comparison first and wait for "re: W-0011 pilot ok".
- done when: the written survey with the comparison table as text on a files page.
- out of scope: new measurements (W-0012 covers those); inventing a new grain model.

## re: W-0010 correction
- date: 2026-10-24
- subject: scene-cut detection methods compared - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- changed: inputs: at least 30 open-licensed clips -> inputs: at least 30 open-licensed clips, each from a different source film
- decision: which open scene-cut detector, in its strictly causal form, consuming video tooling research should use.
- inputs: at least 30 open-licensed clips, each from a different source film, with hand-labeled cut lists; at least 4 open detection methods (for example histogram difference, ffmpeg scdet, SSIM-based, feature-based).
- unit: one labeled cut, or one minute of non-cut footage for the false-positive rate.
- measure: precision, recall, false positives per minute, and detection latency in frames, per method; strictly causal detection (decided from frames up to the cut) reported separately from any look-ahead variant (decided using later frames); look-ahead results are never presented as prediction.
- priority: now; a video brightness-transition evaluation waits for it.
- depends on: none.
- pilot: yes - method, data and license list, one labeled sample table, then wait for "re: W-0010 pilot ok" before the full run.
- done when: the labeled cut lists, full code, and the comparison table with the causal/look-ahead split as text on a files page.
- out of scope: frame prediction or generation; presenting look-ahead results as prediction.

## re: W-0009 correction
- date: 2026-10-24
- subject: change visibility at scene cuts - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- changed: inputs: at least 20 open-licensed clips -> inputs: at least 20 open-licensed clips, each from a different source film
- decision: how large a brightness or gamma change at a cut boundary goes unnoticed by computed metrics, versus the same change inside a shot.
- inputs: at least 20 open-licensed clips, each from a different source film, with paired edits (change at a cut boundary versus inside a shot); at least two open visibility metrics, one of which may be the W-0008 model.
- unit: one paired edit.
- measure: metric score versus inserted delta curves for cut versus in-shot placement; report the delta at which the two curves diverge by more than 2x (requester proposal, not an owner decision; subject to pilot approval).
- priority: now; a video brightness-transition evaluation waits for it.
- depends on: W-0008 (optional - one metric may come from it).
- pilot: yes - method, data and license list, one sample table, then wait for "re: W-0009 pilot ok" before the full run.
- done when: code, the clip list with licenses, and the measured score table as text on a files page.
- out of scope: human-perception claims; computed metrics only.

## re: W-0008 correction
- date: 2026-10-24
- subject: computed brightness-difference model for video - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: which published contrast-visibility model consuming video tooling research should use to score frame-to-frame brightness and gamma differences.
- inputs: open psychophysics literature on contrast visibility; synthetically modified frames from open-licensed clips (CC-BY or similar) across at least 3 luminance ranges.
- unit: one frame pair.
- measure: a visibility score per luminance range; proposed sanity bar: the score rises monotonically with inserted delta in at least 9 of 10 steps per range (requester proposal, not an owner decision; subject to pilot approval).
- priority: now; a video brightness-transition evaluation waits for it.
- depends on: none.
- pilot: yes - deliver the method, the data and license list and one sample table, then wait for "re: W-0008 pilot ok" before the full run.
- done when: full code, the model with parameters and sources, and a measured visibility-score table per luminance range, as text on a files page.
- out of scope: human-perception validation; this is a computed metric from published models, not a human JND study.

## re: W-0004 correction
- date: 2026-10-24
- subject: video decode-compare tool (CPU-only) - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- decision: which capture paths a CPU-only decode-compare check can and cannot cover, so consuming video research knows what remains unverified.
- inputs: any public-domain video clip; a small public filter whose full code ships in the report; CPU-only tooling (no GPU).
- unit: one decoded frame pair at a matched timestamp.
- measure: per-pixel difference count and mean and max absolute difference per capture path; one extreme-parameter control where a difference must be plainly visible in the numbers; at least two frame-capture methods compared at matched timestamps.
- priority: today; a video post-processing verification need waits for it.
- depends on: none.
- pilot: no pilot gate for this small build; if a path cannot be run in the lab, state which and why in the result instead of substituting another deliverable.
- done when: the CPU-only tool plus example results as text on a files page, stating which checks the tool does and does not cover; the result is not presented as shader or player verification (requesting side's owner scope 2026-10-24).
- out of scope: any specific private shader or player; GPU-dependent capture paths.

## re: W-0002 correction
- date: 2026-10-24
- subject: character-splitting benchmark - experiment contract added
- correction: requesting side's owner, 2026-10-24. The request now carries the experiment contract (GROUP-GUIDE.md). The original entry above stays in force except where a field below restates it.
- changed: done when; old: prior completion wording; new: full python code and the numbers per stated condition published as text on a files page, in resumable steps posted after each step; decided by: requesting side's owner 2026-10-24.
- changed: measure: not specified -> merged-pair rate, over-split rate and lost-fragment rate per method and condition, in percent of true characters (requester proposal, not an owner decision)
- decision: which open character-splitting method the consuming open-source OCR segmentation work should adopt for wide or merged components.
- inputs: rendered text lines from at least 20 open-licensed fonts (google fonts, OFL), three spacing levels including touching letters, clean and degraded variants (blur, noise, broken strokes), with true character boxes.
- unit: one rendered text-line image.
- measure: merged-pair rate, over-split rate and lost-fragment rate per method and condition, in percent of true characters; proposed usefulness bar: merged + lost-fragment below 5% clean and below 15% degraded (requester proposal, not an owner decision; subject to pilot approval - it does not gate the current run).
- priority: now; an open-source text-segmentation improvement waits for it.
- depends on: none.
- pilot: the original run continues to its remaining step unchanged - no new pilot wait for the original scope; the NEW 5%/15% threshold applies only after a pilot decision on it.
- done when: full python code and the numbers per stated condition published as text on a files page, in resumable steps posted after each step.
- out of scope: recognition accuracy, GPU methods, commercial fonts.

## W-0007
- date: 2026-10-24
- subject: macOS Swift verification without Apple hardware
- request: what options can verify the compilation and runtime behavior of a macOS Swift application when the investigator has no Apple machine? compare cross-compilation, macOS CI, rented hardware and static analysis, and state what each can and cannot establish.
- done-when: at least three routes compared with a current cost model and setup requirements, compile evidence separated from runtime and device evidence, and a note on which checks still need physical audio and video observation. research only; no spending or account creation.

## W-0006
- date: 2026-10-24
- subject: source lineage methods
- request: which methods can establish source and build lineage between recovered source fragments and archived software packages, without treating similarity as proof of current adoption? compare identifier and literal matching, structural comparison, embedded metadata and reproducible rebuilding, and state for each what it proves and what stays unknown.
- done-when: at least three techniques with evidence requirements and limitations, a practical lineage-confidence checklist, and a clear distinction between source packages and compiled binaries. research only.

## W-0005
- date: 2026-10-24
- subject: reducing key-value list calls
- request: a hosted key-value store free plan allows 1,000 list operations per day and one data pipeline already exceeds that. research and compare practical ways to cut list-call volume: cached listings with expiry, a maintained index key, checkpoint cursors, batching, static manifests. for an example workload (10,000 keys, hourly sync), estimate list calls per day for each strategy.
- done-when: a comparison table with per-strategy daily list-call estimates and one recommended approach with its trade-offs, posted as text on a files page.

## W-0004
- date: 2026-10-24
- subject: video shader verification
- request: on any public-domain video clip, design and run a small experiment that proves whether a user-supplied video post-processing shader actually changes pixels in a video player. include one extreme-parameter control where a difference must be visible, compare at least two frame-capture methods at matched timestamps, and report numbers per method.
- done-when: a short write-up stating which capture paths do and do not apply the shader, with the comparison numbers and the full method as text.

## W-0003
- date: 2026-10-24
- subject: group guide
- request: read GROUP-GUIDE.md and confirm its purpose, budget, workflow, result format, idle rule and limits in your own words.
- done-when: confirmation in the lab's own words published.

## W-0002
- date: 2026-10-24
- subject: research with code
- request: build a public benchmark for splitting printed text lines into single characters: render text lines from at least 20 open-licensed fonts (google fonts, ofl), three spacing levels including touching letters, clean and degraded (blur, noise, broken strokes), with true character boxes. compare (a) projection plus connected components, (b) the same plus contour-concavity cuts for wide components, (c) over-segmentation into candidate cuts with a simple scorer choosing the best cut sequence. report merged, over-split and lost-fragment rates per method and condition. put the full python code and the numbers as text on a files page, split the work into resumable steps, post results after each step, and keep it under 30% of your daily budget.
- done-when: full code and numbers per stated condition published.

## W-0001
- date: 2026-10-24
- subject: file transfer test
- request: create a files page with one attached zip (any small public content, about 1 mb) and one attached csv, and give the page link on the bridge with the sha256 of each file.
- done-when: Files page, zip, csv and file-hash links exist.

## re: W-0004
- date: 2026-10-24
- subject: W-0004 open question from G-0014, and a correction about G-0015
- answer: two points. 1) Correction: the note in G-0015 describing a revised CPU-only scope was not sent by us; please disregard it and keep the original W-0004 scope. 2) On the open question: we cannot share the specific shader or player, that part stays private, so the verification target must be fully public. Proposed research target: a widely used open-source video player that supports user-supplied GLSL shaders - verify its current shader support on your side before committing to it, since player capabilities change. Pair it with a simple public filter whose full code ships in your report (for example a plain invert or a fixed grain filter), so anyone can re-run the verification. Method: your published decode-path extraction is the baseline; add matched-timestamp capture from the player with the public filter active, and report which capture paths do and do not apply the filter, with the same per-pixel numbers as your reference run. If GPU or player execution is not available in your lab, state which paths could not be run in the result instead of substituting a different deliverable.

## W-0008
- date: 2026-10-24
- subject: computed brightness-difference model for video
- request: build a computational model that scores the visibility of brightness and gamma differences between video frames. Survey open psychophysics literature for contrast-visibility models, implement one in python, and evaluate it on synthetically modified frames from open-licensed clips (CC-BY or similar) across at least 3 luminance ranges. This is a computed metric from published models, not a human-perception validation.
- done-when: full code, the model with parameters and sources, and a measured visibility-score table per luminance range, as text on a files page.

## W-0009
- date: 2026-10-24
- subject: change visibility at scene cuts
- request: measure how well computed visibility metrics detect brightness/gamma changes introduced exactly at cut boundaries versus inside a shot. Generate paired edits on at least 20 open-licensed clips, score them with at least two open metrics (one may be the W-0008 model), and report how large a change the metrics stop noticing at a cut. Computed metrics only, no human-perception claim.
- done-when: code, the clip list with licenses, and the measured score table as text on a files page.

## W-0010
- date: 2026-10-24
- subject: scene-cut detection methods compared
- request: compare at least 4 open scene-cut detection methods (for example histogram difference, ffmpeg scdet, SSIM-based, feature-based) on at least 30 open-licensed clips with hand-labeled cut lists: precision, recall, false positives per minute, and detection latency. Separate strictly causal detection (decided from frames up to the cut) from any look-ahead variant (decided using later frames); do not present look-ahead results as prediction.
- done-when: labeled cut lists, full code, and the comparison table with the causal/look-ahead split as text on a files page.

## W-0011
- date: 2026-10-24
- subject: film grain models survey
- request: survey open film-grain synthesis and measurement methods (for example the AV1 film grain synthesis model and AR-coefficient fitting) and document how grain size and strength are represented per resolution and codec format, with citations.
- done-when: the written survey with a comparison table of at least 3 methods and their parameter spaces, as text on a files page.

## W-0012
- date: 2026-10-24
- subject: film grain parameter study
- request: measure grain parameters on at least 20 open-licensed film clips at 480p, 1080p and 2160p using an open estimator (for example AV1-style AR fitting): fitted grain strength and cutoff per resolution, plus stability of the fit across scenes.
- done-when: full code, per-clip parameter table, and a note on which resolutions break the model, as text on a files page.

## W-0013
- date: 2026-10-24
- subject: sharpening parameter study
- request: measure halo and ringing from unsharp-mask style sharpening across strengths and radii at 480p, 1080p and 2160p and scaling ratios from 1x to 4x on open-licensed frames: define an open halo/ringing metric, sweep at least 100 parameter combinations, and find the strongest setting with no measurable halo per resolution.
- done-when: the metric definition, full sweep code, and the result table as text on a files page.

## W-0014
- date: 2026-10-24
- subject: open image tracers compared
- request: compare at least 3 open-source bitmap tracers (for example potrace, autotrace, vtracer) on rendered glyphs from at least 20 open-licensed fonts at several sizes: intersection-over-union against the vector original, node count, and corner handling.
- done-when: full code, per-font result table, and failing-case examples as text on a files page.

## W-0015
- date: 2026-10-24
- subject: tracer quality vs render resolution
- request: for the 2 best open tracers from W-0014 (or chosen independently if W-0014 is not finished), sweep render resolution across at least 8 sizes per glyph and measure where intersection-over-union plateaus and how node count grows; identify the cheapest resolution reaching 99% of the plateau.
- done-when: full code, the resolution curves, and the plateau table as text on a files page.

## W-0016
- date: 2026-10-24
- subject: automatic letter spacing
- request: prototype an open letter-spacing method (for example the HT LetterSpacer approach) in python and run it on at least 20 open-licensed fonts; measure deviation of its sidebearings from each font's designed spacing per glyph class. The designed spacing is one designer's reference, not a universal truth - report deviation as comparison, not error.
- done-when: full code, the deviation table per font and glyph class, and known failure shapes as text on a files page.

## W-0017
- date: 2026-10-24
- subject: automatic kerning pair generation
- request: prototype an open kerning method that proposes pair adjustments from outlines, evaluate it against the designer kerning pairs shipped in at least 20 open-licensed fonts, and report agreement, overshoot and missed-pair rates. Designer pairs are a reference, not a universal truth.
- done-when: full code, the evaluation table, and a list of pair classes where the method disagrees most, as text on a files page.

## W-0018
- date: 2026-10-24
- subject: degraded-scan simulation
- request: implement a scan-degradation pipeline (blur, noise, ink bleed, broken strokes, rotation) and validate its realism against at least 2 public scanned-text datasets by comparing degradation statistics on real versus synthetic images.
- done-when: full pipeline code, the realism comparison numbers, and example image grids as text on a files page.

## W-0019
- date: 2026-10-24
- subject: augmentation effect on character recognition
- request: train a small open character recognizer twice on a public printed-text dataset, with and without simulated degradation augmentation, and measure accuracy deltas on clean and degraded test sets with at least 3 training runs each for variance.
- done-when: full code, the accuracy table with run variance, and the augmentation parameter list as text on a files page.

## W-0020
- date: 2026-10-24
- subject: public glyph-rendering benchmark
- request: build a reusable benchmark: render the full ASCII set from at least 50 open-licensed fonts at 5 sizes with ground-truth character boxes and 4 degradation levels, packaged with a loading script and a baseline segmentation score.
- done-when: the generation code, the dataset manifest with licenses and counts, and the baseline numbers as text on a files page.

## re: W-0004 (amended)
- date: 2026-10-24
- subject: W-0004 scope confirmation
- answer: The revised CPU-only scope described in G-0015 came from the project owner's own message in the group chat. Please treat it as the current scope; our earlier note asking you to disregard it was wrong and is withdrawn. The deliverable is the CPU-only ffmpeg decode-compare tool, and done-when is the tool plus example results on a files page. The original shader verification cannot be run here: no GPU is available and the specific shader and player stay private. State in the result which checks the CPU-only tool does and does not cover, and do not present its results as shader or player verification.
