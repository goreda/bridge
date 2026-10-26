# gposcheck

Independent acceptance checker for kerning (GPOS) output of a font writer. It never calls the writer.

Inputs: original font bytes, the writer's output font bytes, and the writer's declared pair list (JSON list of
`{left, right, requested, written (int or null), status, reason}`). Output: a text receipt and exit code 0 only on PASS.

Checks, all computed from the bytes:
- declared pairs are counted as written, rounded or rejected from the values themselves; the declared status must match, and every rejection needs a reason (no silent drops, no duplicates);
- the output GPOS is parsed with fontTools (kern feature reachable from a script, pair adjustment lookups, extension lookups, glyph and class subtables, first matching subtable wins) and every declared pair must read back equal; rejected pairs must read back as zero; any nonzero pair that was not declared is a finding; value fields other than the horizontal advance are findings;
- every table except GPOS must be byte-equal to the original (head checkSumAdjustment is masked), or be listed as a diff with both hashes; a diff fails unless its tag is allowed explicitly;
- HarfBuzz (uharfbuzz) shapes every declared written pair, every rejected pair and every explicit undeclared pair; the kern advance difference must equal the declared value and nothing else may move. A glyph without a cmap entry cannot be shaped and is a finding.

Additions in receipt v2:
- format 1 pair sets: coverage and second glyphs must be unique and in glyph id order, counts must agree (`pairset_second_glyph_not_ascending`, `pairset_duplicate_second_glyph`, `coverage_unsorted_or_unknown`, count mismatches); class counts are checked for format 2; the receipt prints subtable, pair set and record counts;
- enumeration limit (CONVENTION, default 600 glyphs, `--enumeration-limit`): above it the run fails with the typed finding `not_enumerated` instead of silently checking fewer pairs; the receipt prints the limit and whether the enumeration was complete;
- int16: `written` must be an integer inside -32768..32767 (`written_not_integer`, `written_out_of_int16`), and every value read from the font is range-checked (`value_out_of_int16`);
- a legacy `kern` table in the output is a finding, also when the original had one; the only exception is `--allow-legacy-kern REASON`, and the reason is printed;
- `--compare-original`: effective pairs of the original GPOS against the output, reported as preserved, changed, dropped, added and explicit zero; `--original-drop-is-finding` turns drops into findings; the receipt prints the mode (`report_only` or `dropped_is_finding`);
- `--sequences file.json`: strings or `{text, expected_kern}` are shaped as whole sequences and the per-position kern delta must equal the pair values read from the table (and the expected list when given); characters without a cmap entry are a finding.

Input and structure robustness:
- a declared `written` that is not a plain integer (NaN, infinity, text, bool, float, beyond float range) is the finding `declared_value_unusable` (plus `written_not_integer` where it applies); the pair is counted as `invalid` in the receipt and left out of every comparison, so it cannot crash the run or be compared as if valid;
- a declared `requested` that is not a finite number is also `declared_value_unusable`; the pair stays in the comparison, is counted as rounded (it can never equal `written`), and a declared status of written is a `status_mismatch`;
- the raw GPOS bytes get their own structure checks (`class_count_mismatch`, `pairset_count_mismatch`, `gpos_raw_structure_unreadable`): record arrays must fit in the table and must not run into the offsets that follow them, because the fontTools objects trust the counts they read;
- an unknown pair adjustment format is the finding `unsupported_pairpos_format`; a GPOS table fontTools cannot parse is `parse_failure`.

The receipt carries the font hashes, the GPOS table hash, per-table hashes, the counts, one line per rejection with its reason, one line per shaped pair and the verdict.

STAND-IN: `gposcheck/synth.py` builds synthetic fonts in memory and a reference GPOS writer made with the fontTools feature compiler. It exists only to exercise the checker and makes no claim about any real writer. No source font or font-derived data is used or stored.

Run: `python -m gposcheck --original a.ttf --output b.ttf --declared pairs.json [--allow-diff-tag TAG] [--receipt r.txt]`
Tests: `python -m unittest discover -s tests`
Pins: see `requirements-gposcheck.txt` (fonttools 4.65.0, uharfbuzz 0.56.3). CI target Python 3.12; the local run used Python 3.10.

## Input errors, exit codes and added structure checks

- A malformed declared list, a row that is not an object, a missing key or non-string glyph names are typed findings (`declared_input_unusable`, `declared_row_unusable`); the row is left out of the comparisons. An integer too large for a float is an unusable declared value, not an exception.
- A damaged original is `original_parse_failure`, a damaged output or output GPOS is `parse_failure`, an unreadable original GPOS under `--compare-original` is `original_parse_failure`. HarfBuzz refusing the output is `harfbuzz_unusable`. Malformed sequence entries are `sequence_input_unusable`. Any other exception inside the checks is `check_aborted` in the receipt.
- Exit codes: 0 PASS, 1 at least one finding, 2 an input or file error (unreadable file, JSON that does not parse, top level not a list). Exit 2 prints and writes a receipt with the typed finding and `verdict=INPUT_ERROR`.
- Output contract, read from the raw bytes of every PairPos subtable: ValueFormat1 must be exactly 0x0004 (`value_format1_not_x_advance_only`), ValueFormat2 must be 0 (`value_format2_not_zero`); bits 8-15 are reported separately (`value_format_reserved_bits`). With `--compare-original`, an original that uses another ValueFormat is not a finding: the receipt gets an `original_value_format info=...` line and the comparison runs on effective x-advance values. A nonzero LookupFlag or a ReqFeatureIndex in the original is likewise an `original_info` line.
- `lookup_flag_nonstandard` (nonzero LookupFlag on a kern lookup), `req_feature_index_set` (ReqFeatureIndex other than 0xFFFF), `feature_params_present` (kern feature with FeatureParams, read from the raw bytes), `feature_index_out_of_range`, `lookup_index_out_of_range`.
- `classdef_class_out_of_range`: a ClassDef class index at or above Class1Count / Class2Count. Pairs that map to such a class are not compared with HarfBuzz; the receipt line says `skipped_class_index_out_of_range` and gives the table value.
- Receipts for inputs without these conditions are byte-identical to the previous version.
- The receipt has a `gpos_structure` line: lookup count, feature count, kern feature count, language system count and the number of distinct kern lookup sets. With `--compare-original` the original gets an `original_gpos_structure` line and no finding.
- `output_lookup_count_not_one`: the output GPOS has more than one lookup (output only).
- `language_system_mismatch`: a language system whose kern x-advance differs from the first language system on an enumerated pair. One finding per differing language system, with the pair count and the first pair.
