# JSON to descriptive TSV adapter

Converts only the real-fit JSON ledger_rows adapter fields to descriptive_report
input. Prediction/capture structures are not used to invent residuals. Rust code
and the sweep writer are unchanged. Real writer compatibility is UNVERIFIED.

Run with explicit schema/module paths:

    python3 adapter.py --record ../real_fit_schema/valid.json --json-schema ../real_fit_schema/real-fit.schema.json --report-schema ../descriptive_report/schema.json --report-module ../descriptive_report/report.py --out new-output
    python3 test_adapter.py -v

Requires jsonschema supporting Draft 2020-12. The output directory must not exist.
Input is parsed strictly: duplicate JSON keys, NaN and Infinity are refused. All
JSON content must satisfy the unchanged real-fit schema before any final output.
Schema mismatch stops the input; the adapter does not rewrite schemas or records.
Additional duplicate-pair, common namespace/unit/partition and coverage checks apply.

The descriptive header comes from schema.json. JSON null maps explicitly to its
configured missing-error literal. Numeric zero maps to 0, not absence. Boolean
values map to configured literals. Every text field written to TSV rejects Unicode control characters (including
tab, CR and LF), double quotes and a leading # with TSV_UNSAFE_TEXT:<field>.
This also closes the F-4 text-consumer ambiguity: no quoted TSV escape is emitted
for a consumer that reads unquoted fields. Case variants remain distinct; names
are not lowercased or merged.
Signed residuals are not converted to absolute errors here; descriptive_report
performs its documented absolute-error metric conversion.

Outputs: ledger.tsv, context.json and receipt.json. Context preserves the source
provenance flags and sealed_membership=UNVERIFIED, always DESCRIPTIVE ONLY. Receipt
binds source, schemas, adapter/report module and output hashes. Before publishing
these files, the adapter feeds the staged TSV/context through descriptive_report
in a temporary directory. A report intake mismatch leaves no final output.

The report module path is explicit trusted local executable code, not a path read
from JSON. Inputs should be known source files; metadata contains no executable
instructions. Output publication is not a transactional filesystem bundle: a copy
error removes the newly created folder. Existing folders are never overwritten.

No inference, threshold comparison, winner or statistical decision is emitted.
Actual source identity, font/frame binding, residual arithmetic and independence
still require source-grounded semantic checks. The adapter cannot prove them from
valid syntax. Structural validity never supplies execution or disclosure authority.

Strict JSON intake comes from ../real_fit_schema/strict_json.py via an explicit local
module path. It rejects duplicate keys and all nonfinite floats, including 1e400
overflow; validation uses JSON integer tokens and ledger duplicate checks. The
shared module hash is recorded in the receipt. Schema mismatch stops adaptation.

Residual -0.0 is refused with NEGATIVE_ZERO. Integer residual magnitudes above
2^53 are refused with UNREPRESENTABLE: 2^53 is the IEEE binary64 consecutive-integer
representation bound, not a fitted threshold. JSON null still stays missing.
Tests expect the descriptive_report directory in the repository layout.

TSV text fields also reject leading or trailing whitespace with TSV_UNSAFE_TEXT:<field>,
so a trimming consumer cannot interpret a different identity. The schema structurally
accepts -0.0 and integer magnitudes above 2^53 in residual fields; the adapter rejects
them with NEGATIVE_ZERO and UNREPRESENTABLE. These checks are not schema constraints.

TSV text rejects Unicode categories Cc, Cf, Cs, Co, Cn, Zl, Zp and every Zs except ASCII space anywhere in a value with TSV_UNSAFE_TEXT:<field>.

Identity is by code point sequence; no normalization, case folding or confusable detection.
