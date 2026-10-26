# Descriptive real-fit JSON Schema

A strict JSON projection from public Rust structures and descriptive report headers.
The real-fit driver and sweep writer are not in the repository. Their output format
is not defined by repository code. Real output compatibility is UNVERIFIED.

## Fields and sources

Each field has x-source, x-unit and x-missing-rule annotations. PredictionRow,
HeldOutPartReceipt, HeldOutPartPrediction and Observation fields come from
engine/metrics/src/training_only_fit.rs. Point, Span and ReferenceRing come from
engine/core/src/reference_slice.rs. FitSpan and the four-element baseline capture
tuple come from engine/core/src/capture_fit.rs. The tuple preserves Rust order:
rings, span count, fallback flag, dropped count. Source mapping and economy
observations use source_provenance.rs and economy.rs types.

Enum variant tags are projection conventions, not an existing serde encoding.
Envelope metadata and descriptive ledger headers are separate adapter fields;
residual headers come from engine/tooling/descriptive_report/schema.json. The
source_commit field identifies a source revision with a 40-character hexadecimal
commit value. It does not fix the record to a particular repository revision.

Missing Option values map to JSON null, never zero. The ledger uses one complete
signed-residual form. A candidate residual is null when unavailable, with an explicit
reason; observed kern zero stays zero. The examples include a scored record and an
abstention. The invalid example fills an unavailable residual with zero.

Every record has DESCRIPTIVE ONLY mode. Sealed membership remains UNVERIFIED.
Family and independence flags are provenance claims, not verified evidence. No
winner, statistical decision, tolerance threshold or inference field is defined.

## Validate

Requires Python and jsonschema supporting Draft 2020-12.

    python3 validate.py --schema real-fit.schema.json --record valid.json
    python3 validate.py --schema real-fit.schema.json --record invalid.json
    python3 test_schema.py -v

The validator rejects NaN and Infinity before schema validation. The invalid
example must exit with a validation error at ledger_rows/1/resid_cand.

Structural validation does not check source identity, pair/family uniqueness or
binding, font/UPM/frame comparability, residual arithmetic, training exclusions,
ring closure, interval bounds or inventory count consistency. Those need separate
source-bound semantic checks. This schema covers baseline capture and optional
provenance/economy observations, not every public API or the full FitArtifacts graph.
When real output disagrees with the schema, stop and report the mismatch; do not
silently change the schema to fit it.

Strict intake is shared with the TSV adapter through strict_json.py. It rejects
all nonfinite floats, including overflow from 1e400, and duplicate object keys.
Integer fields require JSON integer tokens: 1.0 is rejected. i32 bounds follow
Rust; CONVENTION: usize projection uses 64-bit unsigned range, not target-derived
width. The source commit identity is lowercase 40-hex, with an absolute end match.
Predictions and ledger rows are nonempty; capture_outputs is optional and can be
empty. Absence/empty capture output is not a measured geometry result. Duplicate
ledger rows and duplicate pair identities are rejected by semantic intake checks.
Partition remains nonempty free text, with no invented enum or membership proof.
A true family-disjoint or independence flag requires a nonblank evidence reference;
that reference remains a claim, not independently validated proof.
Use validate.py rather than a generic JSON Schema validator to enforce integer
syntax and duplicate-record semantics as well as structural schema constraints.

The shared loader maps runtime RecursionError to JSON_TOO_DEEP and integer-digit
limit errors to JSON_INTEGER_TOO_LARGE; no new numeric parsing limit is invented.
Every string and key rejects lone Unicode surrogates with INVALID_UNICODE. Valid
non-BMP characters remain allowed. Empty capture outputs and free-text partition
are intentional documented choices and are unchanged.
