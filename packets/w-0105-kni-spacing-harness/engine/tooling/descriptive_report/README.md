# Descriptive fit report

Turns a fit-output ledger into descriptive tables. It makes no inference and has no decision gate or winner column. Every report carries a DESCRIPTIVE ONLY mode, and an extra warning when the family-disjoint and independence prerequisites or their evidence pins are missing. Flags and pins in the context file are supplied provenance; the tool does not verify them.

Compatibility with the real fit output is not verified. All column names, types, boolean literals, the missing-error literal and the listed abstention codes are in schema.json, so a different header is handled by editing that one file. A different endpoint meaning needs a review, not a header mapping.

Run: python3 report.py --ledger LEDGER.tsv --context context.json --schema schema.json --out NEW_DIR (the output directory must not exist). Tests: python3 -m unittest test_report. fixture.py regenerates the synthetic ledger and context. Standard library only.

Outputs: pair_differences.tsv (candidate absolute error minus base absolute error per pair, UNAVAILABLE rows kept), family_differences.tsv (family mean difference, pair sign counts, attempted and availability counts), summary.json (family-equal mean, family sign counts, two descriptive p-values, context and warnings), REPORT.md. A negative difference means a lower candidate absolute error and is not a win.

Rules: a missing prediction stays blank and is never zero. Mixed namespace, unit or partition is refused. The mean sign-flip p-value is exact and is unavailable with a typed reason above 16 scored families; there is no sampling and no family subsample. The sign test excludes zero family means and uses the exact binomial tail. Holm is reported as NOT_APPLIED because a complete prelisted comparison family is not part of this input.
