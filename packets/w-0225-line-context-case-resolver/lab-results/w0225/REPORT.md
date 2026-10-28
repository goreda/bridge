# W-0225 geometric relative-height hints v1

Start commit e7c61a2da4f44fd01c711ff57b81aaa0c68b9a5a. Pure module `resolve_line_case(regions,line=None)` returns lower_like, upper_like or unresolved, a measured ratio, and a reason. It never returns identity/Unicode, never changes classifier inputs/outputs, and is not a case classifier. No weights/network. Standard library only in module; synthetic harness uses NumPy and Pillow.

## Frozen design and limits

Design and rendering checks used only the5 original calibration fonts. Module/harness hashes were frozen before W0225 validation/test access, in freeze.json. Validation5 was judged once; no tuning followed. Test29 was then opened for one final descriptive run, never selection or acceptance tuning. Prior W0224 fixture outputs are not W0225 case/height evaluation and were not used to tune. There was no network training.

At least6 regions and2 per group; maximal supported sorted-height gap must be at least.15 of upper-group median; each group range at most.10 of that median. Ink-bottom spread greater than.06 of maximum height gives unresolved. These deliberately conservative bounds were selected before heldout runs, not optimized for coverage. A positional line reference is validated but is not used as semantic x-height/cap-height. Ratio on valid-but-unresolved lines is ink_h/max ink_h; resolved ratio is ink_h/upper-group median. Invalid geometry ratio is null. Labels are only relative size groups. A lower-case ascender can be upper_like. A larger capital is not implied.

Boxes/ink heights cannot identify whether a common-bottom set of two height groups came from mixed case, mixed em, ascenders, symbols or arbitrary shapes. Tiny baseline variation below tolerance can pass, including very slight rotation not identifiable at this resolution. We detect inconsistent ink-bottom geometry, not prove unrotated text. We abstain on substantial tilt/unevenness and natural descender variation. The full-line cluster split is global, with no glyph identity. It is intentionally low coverage and should remain advisory only.

The harness renders each glyph on its original common page baseline before making tight ink boxes, with black ink on white. A line canvas is horizontally extended, with minimum vertical frame256/384/512 and em170/256/341. These are lines, not squeezed into square frames. Fixed sequences cover mixed scale pairs, ascenders, x-height-only lowercase, all uppercase, single/two glyphs, descender-heavy, rotated, uneven and all62. Rotated scenario combines5-degree glyph rotation and a sloped baseline; uneven scenario has ±.1em vertical offsets. Regions preserve source page dimensions. No cleaner or recognizer runs.

## Results

All8 supplied safety tests and5 added pure-geometry tests passed. No recognizer/case accuracy is measured. Geometric hint coverage and abstention denominators count every region, including unresolved. Descriptive render-case association is separately conditional on hinted alphabetic regions, not overall correctness.

| Stage | Families | Hinted/all regions | Unresolved/all regions | Descriptive case-label association among hinted alphabetic regions |
|---|---:|---|---|---|
| Calibration |5|240/2790=.086022|2550/2790=.913978|240/240=1.000000|
| Validation once |5|240/2790=.086022|2550/2790=.913978|240/240=1.000000|
| Test descriptive once |29|1230/16182=.076010|14952/16182=.923990|1225/1230=.995935|

The five descriptive mismatches were lowercase b,d,h,l,k in EB Garamond mixed-ascender scenario at384 frame/256em, grouped upper_like because their ink height is in the taller group. This is expected ambiguity, not a license to turn the hint into semantic case. No fix/tuning after this observation.

All-upper, all-lower x-height-only, single, two, descender-heavy, rotated and uneven scenarios produced unresolved for every region in every heldout font. Test mixed scale pairs hinted1216 regions; mixed ascenders14. Some display fonts abstained even on scale-pair strings. Per-family/scenario counts and exact region outputs are in results.json/rows.json.

Whole-family bootstrap:3000 draws, seed2252026, all glyphs/sizes/scenarios travel with their font. Test geometric coverage percentile95 .065011-.084909. Conditional descriptive association .987091-1.0, valid3000 replicates. Calibration/validation intervals degenerate at their observed values because every family has the same counts on this deliberately narrow suite. These are suite-level descriptive intervals, not real-world semantic confidence or glyph-independent intervals. Family count29, not repeated-region count16182, drives independence.

## Reproduce

```
python3 -m unittest -v
python3 line_harness.py --assets /path/to/w0224 --stage calibration --out new-calibration
python3 line_harness.py --assets /path/to/w0224 --stage validation --out new-validation --freeze freeze.json
python3 line_harness.py --assets /path/to/w0224 --stage test --out new-test --freeze freeze.json
```

The scripts refuse existing output directories and require exact frozen module/harness hashes for heldout stages. This records intended discipline, not tamper-proof access control. Reproduction does not authorize a new design iteration using heldout labels. No module change is allowed from these descriptive test results without a new holdout policy. Font asset folders and immutable manifests are the previously delivered W0224 set; each font SHA is checked. Excluded Saira Extra Condensed never loaded. Font binaries are not returned.

Patch compares original stub to module only. Original intake files/PINS and source commit are preserved. Module output rows stay in original order, same cardinality; invalid input, unsupported separation and insufficient neighbours abstain with reasons. No owner images/fonts, credentials or weight files included. Secret scan receipt is supplied over final bytes.

## Blind review and delivery representation

Reviewer failure-list bytes were received after module/harness freeze and both heldout runs, and before any solver fix disclosure. Verified reviewer SHA2566caa284dadf38d8dba114f7a00cebbfc8327a5002265e83f0315a3c83fe58571, publication receipt19:27:19UTC. No code/harness retuning followed reading it. Exploratory stress cases are not new gates. Invalid geometry policy is documented above; output order preserved; positional anchors cannot imply semantics. Supplied8 safety tests plus5 added tests pass.

Delivery is a single compact archive with code/patch/run/test output, all stage rows and tables, frozen hash/access receipts, selected visual contact sheets and SHA256 manifests for all generated line PNGs. Full1170 line PNGs are reproducible by the harness and not included to avoid a40MB transfer; their exact names/hashes remain in per-stage output manifests. The receipt distinguishes included payload files from reproducible image outputs. Selected calibration/heldout pixels were inspected for expected baseline/tilt/size geometry; that is sampled visual verification, not visual inspection of every line. No font bytes, weights or owner data. Original start commit and version above; targetlab/w-0225-results via existing requester writer after review, no account/repo writes by solver.
