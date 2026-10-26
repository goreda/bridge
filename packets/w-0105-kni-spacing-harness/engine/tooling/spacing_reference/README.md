# Synthetic single-model spacing reference

Authored metric profiles only. No font data, geometry extraction, font writer or optical-quality claim. The formula is not Marini/iKern's unpublished implementation.

Input schema kni.synthetic-spacing-input.v1 requires synthetic=true, frame=synthetic-units, rational-text nonnegative target_gap and interaction, and unique glyphs with rational-text nonnegative ink_width and equal-dimensional nonempty left_profile/right_profile arrays. No supplied bearings, independent kern list or semantic-role field is accepted.

CONVENTION: S(i,j)=target_gap+interaction*mean((right_profile_i-left_profile_j)^2). Use the complete ordered pair matrix. Let G=mean(S), r_i=row_mean_i-G/2, l_j=column_mean_j-G/2. This is a least-squares additive projection with equal mean bearings fixing its gauge. The unrounded reference residual is S-r_i-l_j. It reconstructs S exactly and its row/column sums are zero. Profiles are numeric fixtures, not inferred outline roles.

Integer output uses nearest-integer ties-away-from-zero for BOTH bearings first. Let r_int and l_int be those values. Advance=integer ink_width+l_int+r_int; fractional ink_width is rejected by the adapter. The declared kern request is then S-r_int-l_int, calculated exactly with Fraction, and only that residual is rounded to written. Integer residual row/column sums need not be zero. Unrounded reference fields remain diagnostic, not the source of declared.json.

realized_gap_error=(r_int+l_int+kern_written)-S is reported for each storable pair, with max absolute error. Error beyond 1/2 unit is a typed error, never clipped. Rejected pairs have unavailable error and a reason; the max is null if no pair is realized. Exact requests outside [-32768,32767] are rejected with written=null. Bounds are checked before rounding, never wrapped. No hmtx table is written or validated; integer bearings and advances are synthetic outputs, not production-ready font values.

Output result.json carries unrounded_reference=true, unrounded bearings and model residuals, integer_bearings, realized_gap_errors and max_abs_realized_gap_error. declared.json is a full pair list with exactly left,right,requested,written,status,reason. Its written values are planned, not proof that a table was written. adapter.json identifies evidence_class=declared, proposed, synthetic, model hash, exact rational requests, counts, ValueFormat1=0x0004 and ValueFormat2=0. These format fields describe an x-advance-only writer target, not binary evidence. Every explicit zero and rejected pair is retained.

Requested is a finite binary64 JSON number for gposcheck. Exact rational requests stay in the companion. A fractional request that converts to the same binary64 number as written errors rather than misclassifying its status. Duplicate input keys and unknown fields are rejected. Result equality is checked against the same immutable model before adaptation; forged and cross-model residuals are rejected.

Hand fixture: target20, interaction2, profiles0/2 gives S=[[20,28],[28,20]], bearings12/12, kern=[[-4,4],[4,-4]]. Fractional example: S=10.5 everywhere, unrounded bearings5.25, integer bearings5, kern request0.5, written1, realized error0.5.

Run: python spacing_reference.py --input synthetic-input.json --output-dir NEW_DIRECTORY
Test: python test_spacing_reference.py
Outputs are staged into a new directory; existing output is refused. Destination checks are not race-free against competing writers; use exclusive output ownership.

Bounds, same-model reconstruction, unrounded residual sums, integer bearing propagation, half-unit realized error, full pair coverage, explicit zeros, forged outputs and malformed inputs are tested. Independent parser round trip, shaping, class compression, actual GPOS formats and table equality are outside this tool. Proposals are not production GPOS acceptance.

Rational text grammar is exactly -?digits(.digits)? or digits/digits, using ASCII digits only. A fraction's denominator must be positive; signed fractions are not accepted. Plus signs, whitespace, Unicode digits and exponent notation are rejected. MAX_RATIONAL_TEXT_LENGTH=512 is the sole text-length guard (CONVENTION: no theory behind the number). Overflow of this length is a typed rejection, never truncation. Errors distinguish rational_text_required, rational_text_too_long, rational_syntax_invalid and rational_denominator_zero.

Glyph names are nonempty, have no leading or trailing whitespace, and reject Unicode categories Cc, Cf, Cs, Co, Cn, Zl, Zp and every Zs character except ASCII space (U+0020) anywhere in the name. Case differences identify distinct glyphs; no case folding or name normalization. Identity is by code point sequence; no normalization, case folding or confusable detection. Invalid names yield name_invalid, duplicates name_duplicate. CLI errors distinguish utf8_invalid, json_invalid, io_error, input_recursion and value_invalid from model validation codes.

Each immutable model computes and caches its derived matrix once. Report and adapter checks compare against that cached result. This is a small-n synthetic tool with O(n^2) matrix storage/work at fixed profile dimension, not a real-font-sized solver. No subsampling or pair omission.
