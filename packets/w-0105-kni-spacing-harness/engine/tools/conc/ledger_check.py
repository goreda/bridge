#!/usr/bin/env python3
"""Conformance checker for the unified typed ledger schema.

Schema (docs/conc/ledger-schema.md): one row per line, LF endings,
    stage <TAB> code <TAB> subject <TAB> reason
plus receipt summary equivalents:  <code>_total <TAB> N [ <TAB> note ]

Existing in-tree typed-warning formats are ACCEPTED as documented variants
(architect decision, docs/conc/ledger-schema.md): lines matching a variant
pattern are classified "variant" and reported separately from violations.
New emitters and new rows must use the canonical form. Blank lines are
tolerated and skipped. Stdlib only; no repo imports.

Usage:
    ledger_check.py FILE... [--json] [--strict-legacy|--strict-variants]
                            [--allow-unregistered]
    ledger_check.py --self-test
Exit 1 when any violation is found (variant lines count only with
--strict-legacy/--strict-variants). Exit 2 on usage/io errors.
"""
import json
import os
import re
import sys

SCHEMA = "conc/ledger-schema/9"

# Code registry (initial). Keep in sync with docs/conc/ledger-schema.md.
REGISTERED_CODES = {
    "guard_degrade",        # G2 ambiguity guard-degrade
    "stem_pair_overflow",   # G3 stem-pair root-cause
    "ring_exclusion",       # MARQ-DEGEN ring exclusion
    "cadence_unobserved",   # W3 (B) UnobservedPolicy
    "fallback_span",        # W17 per-glyph fallback ledger row
    "fallback_export_gate", # W6 ship gate decision row
}

STAGE_RE = re.compile(r"^[a-z][a-z0-9_]*$")
CODE_RE = re.compile(r"^[a-z][a-z0-9_]*$")
SUMMARY_RE = re.compile(r"^([a-z][a-z0-9_]*_total)\t(\d+)(\t[^\t]+)?$")

# Documented variant patterns (accepted; reported, never rewritten):
# 1. code-first 4-field warning (determinism_decide.rs)
VARIANT_CODE_FIRST = re.compile(r"^encode_nondeterministic\t(true|false)\t[^\t]+\t[^\t]+$")
# 2. three-field receipt rows observed in the export path
VARIANT_THREE_FIELD = re.compile(r"^(export_intent|fallback_ledger_total)\t[^\t]+\t[^\t]+$")
# 3. variant counter rows that predate the summary rule
VARIANT_COUNTER = re.compile(r"^(glyph_exclusions_[a-z_]+|glyph_skip_total)\t\d+(\t[^\t]+)?$")
# 4. pair ledger WITHOUT stage: only inside fallback-glyphs.tsv context -
#    the filename, or after its `glyph<TAB>spans` header. A bare name<TAB>N
#    row anywhere else is NOT a variant (it would swallow any 2-column
#    numeric table row).
PAIR_LEDGER_FILENAMES = {"fallback-glyphs.tsv"}
PAIR_LEDGER_HEADER = "glyph\tspans"
VARIANT_TSV_ROW = re.compile(r"^[^\t]+\t\d+$")

# Variant (d): receipt key-value rows of ANY field count N >= 2, bound to
# receipt files and to a REGISTERED kv head word. The head registry below is
# derived from the receipt emitter output (12 style receipts + Marq Standard
# receipt) plus the conditional-path emitters found by the static drift
# test (tools/conc/receipt_head_drift.py): degrade/partial, cache-replay,
# population-floor, proxy-notdef, and per-glyph capture rows that no
# successful-run fixture exercised. Every head is verified against its
# emitting code (pipeline/src/
# main.rs, pipeline/src/post_metrics.rs, pipeline/src/space_evidence.rs,
# metrics/src/self_anchored_spacing.rs et al. - field-name lists and emitter
# provenance in docs/conc/ledger-schema.md). No invented constants: a row
# whose head is not in this registry fails as UNREGISTERED_KV_HEAD until the
# diff that adds the emitter also extends the registry. Canonical rows in
# the same file still win (registered codes classify ok).
RECEIPT_FILE_RE = re.compile(r"^receipt-.*\.txt$")
RUN_FAILURE_RECEIPT_RE = re.compile(r"^run-failure-receipt\.txt$")
RECEIPT_KV_HEADS = frozenset("""
glyph glyph_segments fallback run_config name_readback glyph_skip classification
notdef_classification scale_status manifest_pin png_decode_limits
hard_fail_unresolved sub_grid_floor straight_sweep_converted export_intent
space_advance_source spacing space_status space_evidence_plumbing kern
kern_drop_total notdef assembly_space_glyph vertical_height_source vertical
export_guard otf iou_report partial_output warning glyph_skip_total
postscript_name_sanitized notdef_state post_pass_applied_unapproved_base
placeholder_class placeholder_class_found placeholder_class_none placeholder_form
placeholder_skip placeholder_decision speck_retained sub_pixel_speck_retained
sub_pixel_speck_retained_replay_unavailable sub_grid_floor_replay_unavailable
guard_stage guard_result approved_base_sha256 context_binding
run_config_sha256 postpass requested_lsb requested_rsb effective_lsb
effective_rsb scope final_font_sha256 final_overlap_rechecked
final_overlap_status guard_policy post_pass_policy xavgcharwidth
gap_monotonicity gap_min_pair_delta physical_overlap_postpass
baseline_overlap_note post_metrics rounding_ledger_basis
capture diagnostic_partial_kern diagnostic_partial_space excluded
fallback_ledger_total glyph_exclusions_total
glyph_exclusions_intentional_empty glyph_exclusions_failures guide
ink_containment ink_containment_skipped iou_config iou_translation_proof
kern_omitted notdef_decode_limits notdef_evidence_ignored
notdef_ink_exceeds_advance notdef_proxy notdef_proxy_final_gid0
outline_fit placeholder_extraction population_floor anchor
population_floor_glyphs run_mode scope_selection space_evidence
space_evidence_ignored stage1_cache tolerance
run_failure_receipt code detail
""".split())

RECEIPT_KV_ARITY = {
    "approved_base_sha256": (2,),
    "assembly_space_glyph": (5,),
    "baseline_overlap_note": (2,),
    "capture": (9,),
    "classification": (14, 16, 22),
    "code": (2,),
    "context_binding": (2,),
    "detail": (2,),
    "diagnostic_partial_kern": (3,),
    "diagnostic_partial_space": (3,),
    "effective_lsb": (2,),
    "effective_rsb": (2,),
    "excluded": (7,),
    "export_guard": (13,),
    "export_intent": (3,),
    "fallback": (4,),
    "fallback_ledger_total": (3,),
    "final_font_sha256": (2,),
    "final_overlap_rechecked": (2,),
    "final_overlap_status": (2,),
    "gap_min_pair_delta": (2,),
    "gap_monotonicity": (2,),
    "glyph": (24,),
    "glyph_segments": (18,),
    "glyph_exclusions_failures": (2,),
    "glyph_exclusions_intentional_empty": (2,),
    "glyph_exclusions_total": (3,),
    "glyph_skip": (6, 8),
    "glyph_skip_total": (2, 3),
    "guard_policy": (2,),
    "guard_result": (2,),
    "guard_stage": (2,),
    "guide": (24,),
    "hard_fail_unresolved": (3,),
    "ink_containment": (14,),
    "ink_containment_skipped": (4,),
    "iou_config": (13,),
    "iou_report": (4,),
    "iou_translation_proof": (4,),
    "kern": (15,),
    "kern_drop_total": (11,),
    "kern_omitted": (6,),
    "manifest_pin": (2,),
    "name_readback": (5,),
    "notdef": (7,),
    "notdef_classification": (5,),
    "notdef_decode_limits": (15,),
    "notdef_evidence_ignored": (2,),
    "notdef_ink_exceeds_advance": (6,),
    "notdef_proxy": (41,),
    "notdef_proxy_final_gid0": (9,),
    "notdef_state": (2, 8, 10),
    "otf": (6,),
    "outline_fit": (12,),
    "partial_output": (4, 5, 6),
    "physical_overlap_postpass": (2,),
    "placeholder_extraction": (5,),
    "png_decode_limits": (9, 13),
    "population_floor": (2, 12),
    "population_floor_glyphs": (4,),
    "post_metrics": (11,),
    "post_pass_applied_unapproved_base": (10,),
    "post_pass_policy": (2,),
    "postpass": (2,),
    "postscript_name_sanitized": (3,),
    "requested_lsb": (2,),
    "requested_rsb": (2,),
    "rounding_ledger_basis": (2,),
    "run_config": (3, 5),
    "run_config_sha256": (2,),
    "run_failure_receipt": (3,),
    "run_mode": (8,),
    "scale_status": (14, 30),
    "scope": (2,),
    "scope_selection": (19,),
    "space_advance_source": (3, 7),
    "space_evidence": (4, 5, 7, 9, 16, 20),
    "space_evidence_ignored": (4,),
    "space_evidence_plumbing": (3,),
    "space_status": (4, 6),
    "spacing": (35,),
    "placeholder_class": (9,),
    "placeholder_class_found": (9,),
    "placeholder_class_none": (3,),
    "placeholder_decision": (10,),
    "placeholder_form": (10,),
    "placeholder_skip": (10,),
    "speck_retained": (5,),
    "sub_pixel_speck_retained": (10,),
    "sub_pixel_speck_retained_replay_unavailable": (3,),
    "sub_grid_floor_replay_unavailable": (3,),
    "stage1_cache": (4,),
    "straight_sweep_converted": (3,),
    "sub_grid_floor": (3,),
    "tolerance": (24,),
    "anchor": (14,),
    "vertical": (15,),
    "vertical_height_source": (9,),
    "warning": (3, 4, 5, 6, 7, 8, 9, 12, 14), "xavgcharwidth": (4,),
}

# Whole-value tokens that never legitimately appear in a receipt kv row.
# (Real receipts carry the word "infinity" in fit fields; the short forms
# below only ever come from corruption.)
KV_BAD_VALUES = frozenset({"nan", "inf", "-inf", "+inf"})

# Field grammar for the most frequent receipt heads: the ordered
# field-name sequence plus a value type per position, derived from the
# emitter literals and verified against real receipts. Each shape is
# (field_count, specs) with specs covering fields[1:]. Spec kinds:
# ("lit", token) exact key/status token, ("type", name) value type from
# GRAMMAR_VALUE_TYPES, ("any",) free non-empty text. Heads without a
# grammar keep the registry-only checks.
GRAMMAR_VALUE_TYPES = {
    "bool": re.compile(r"^(true|false)$"),
    "int": re.compile(r"^-?[0-9]+$"),
    "float": re.compile(r"^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$"),
    "hex16": re.compile(r"^[0-9a-f]{16}$"),
    "hash64": re.compile(r"^[0-9a-f]{64}$"),
    "codepoint": re.compile(r"^(0x[0-9A-Fa-f]+|none)$"),
    "pxdim": re.compile(r"^[0-9]+x[0-9]+$"),
    "snake": re.compile(r"^[a-z][a-z0-9_]*$"),
    "camel": re.compile(r"^[A-Z][A-Za-z0-9]*$"),
    "shout": re.compile(r"^[A-Z][A-Z0-9_-]*$"),
}

RECEIPT_KV_GRAMMAR = {
    "glyph": [(24, (
        ("any",), ("lit", "cp"), ("type", "codepoint"),
        ("lit", "source_pin"), ("type", "hash64"),
        ("lit", "source_kind"), ("type", "camel"),
        ("lit", "source_px"), ("type", "pxdim"),
        ("lit", "scale"), ("type", "float"),
        ("lit", "route"), ("type", "snake"),
        ("lit", "rings"), ("type", "int"),
        ("lit", "nodes"), ("type", "int"),
        ("lit", "final_area"), ("type", "float"),
        ("lit", "final_missing_extrema"), ("type", "int"),
        ("lit", "refused"), ("type", "int"),
    ))],
    "scale_status": [(30, (
        ("lit", "DECLARED_CONVENTION"),
        ("lit", "calibrated"), ("type", "bool"),
        ("lit", "convention"), ("any",),
        ("lit", "k_bits"), ("type", "hex16"),
        ("lit", "h_ink_height_px"), ("type", "int"),
        ("lit", "h_ink_units"), ("type", "int"),
        ("lit", "em_px"), ("type", "int"),
        ("lit", "em_source"), ("type", "camel"),
        ("lit", "basis"), ("type", "camel"),
        ("lit", "cross_frame_reuse"), ("type", "bool"),
        ("lit", "h_source_pin"), ("type", "hash64"),
        ("lit", "scale_id"), ("any",),
        ("lit", "cohort"), ("any",),
        ("lit", "frame"), ("any",),
        ("lit", "context_basis"), ("any",),
    )), (14, (
        ("lit", "CONFIG_CONVENTION"),
        ("lit", "calibrated"), ("type", "bool"),
        ("lit", "convention"), ("any",),
        ("lit", "k_bits"), ("type", "hex16"),
        ("lit", "scale_id"), ("any",),
        ("lit", "cohort"), ("any",),
        ("lit", "frame"), ("any",),
    ))],
    "spacing": [(35, (
        ("lit", "complete"), ("type", "bool"),
        ("lit", "excluded_pairs"), ("type", "int"),
        ("lit", "excluded_self"), ("type", "int"),
        ("lit", "excluded_below_epsilon"), ("type", "int"),
        ("lit", "excluded_unmeasurable"), ("type", "int"),
        ("lit", "numeric_failed_pairs"), ("type", "int"),
        ("lit", "geometric_hold_pairs"), ("type", "int"),
        ("lit", "no_accepted_candidate_pairs"), ("type", "int"),
        ("lit", "fallback_natural_clear_pairs"), ("type", "int"),
        ("lit", "fallback_verified_pairs"), ("type", "int"),
        ("lit", "numeric_failed_nonfinite"), ("type", "int"),
        ("lit", "numeric_failed_malformed"), ("type", "int"),
        ("lit", "numeric_failed_natural_unverifiable"), ("type", "int"),
        ("lit", "numeric_failed_natural_frame_conflict"), ("type", "int"),
        ("lit", "accounting_residual"), ("type", "int"),
        ("lit", "accounting_closed"), ("type", "bool"),
        ("lit", "policy"), ("any",),
    ))],
    "kern": [(15, (
        ("lit", "ready"), ("type", "int"),
        ("lit", "overlap_held"), ("type", "int"),
        ("lit", "rejected"), ("type", "int"),
        ("lit", "dropped_zero"), ("type", "int"),
        ("lit", "clamps_refused"), ("type", "int"),
        ("lit", "solution_complete"), ("type", "bool"),
        ("lit", "fallback_guard_verified"), ("type", "int"),
    ))],
    # glyph_segments: emitter proposed, not yet landed
    # (docs/conc/receipt-segment-metrics-proposal.md); the grammar is
    # registered ahead of the emitter so the checker is ready when it
    # ships, and the drift test tracks the head as pending.
    "glyph_segments": [(18, (
        ("any",), ("lit", "line"), ("type", "int"),
        ("lit", "cubic"), ("type", "int"),
        ("lit", "cubic_pct"), ("type", "float"),
        ("lit", "g1"), ("type", "int"),
        ("lit", "corner"), ("type", "int"),
        ("lit", "corner_per_node"), ("type", "float"),
        ("lit", "chord_len"), ("type", "float"),
        ("lit", "len_per_node"), ("type", "float"),
    ))],
    "anchor": [(14, (
        ("any",), ("lit", "tile_px"), ("any",),
        ("lit", "origin_x"), ("any",),
        ("lit", "k_y_bits"), ("any",),
        ("lit", "y_shift_applied"), ("type", "int"),
        ("lit", "declared_top"), ("type", "int"),
        ("lit", "declared_bottom"), ("type", "int"),
    ))],
    "vertical": [(15, (
        ("lit", "baseline_in"), ("type", "int"),
        ("lit", "shift"), ("type", "int"),
        ("lit", "residual"), ("type", "int"),
        ("lit", "exported_baseline"), ("type", "int"),
        ("lit", "x_height"), ("type", "int"),
        ("lit", "cap_height"), ("type", "int"),
        ("lit", "convention"), ("type", "shout"),
    ))],
}


def grammar_shape(head, nfields):
    """Grammar shape for head at nfields, or None."""
    for n, specs in RECEIPT_KV_GRAMMAR.get(head, ()):
        if n == nfields:
            return specs
    return None


# Gate scope (architect decision): the schema applies to typed-flag ledger
# files and receipts. Columnar data tables and other run artifacts are OUT
# OF SCOPE: the checker skips them (reported, not counted).
IN_SCOPE_FILE_RES = [
    re.compile(r"^fallback-glyphs\.tsv$"),
    re.compile(r"^.*drop-ledger.*$"),
    re.compile(r"^ring_skip.*$"),
    RECEIPT_FILE_RE,
]
OUT_OF_SCOPE_BASENAMES = {
    "kern-ledger.tsv", "kern-diagnostic.tsv", "spacing-pair-ledger.tsv",
    "mapping.tsv", "profile-metadata.tsv", "spacing.tsv",
    "post_metrics_ledger.tsv", "rounding-ledger.txt", "run-provenance.tsv",
    "report.txt", "spacing-hold-reasons.txt", "stage1-cache.txt",
}


def scope_of(path):
    """Return "in" (check), "out" (skip), or "unknown" (check by default)."""
    base = os.path.basename(path)
    if RUN_FAILURE_RECEIPT_RE.match(base):
        return "in"
    if any(r.match(base) for r in IN_SCOPE_FILE_RES):
        return "in"
    if base.lower() in OUT_OF_SCOPE_BASENAMES:
        return "out"
    return "unknown"


def classify(line, allow_unregistered, pair_ledger=False, receipt_kv=False):
    """Return (class, detail). class in ok|summary|variant|violation.

    pair_ledger: True only when the pair-ledger variant context holds for
    this line (pair-ledger filename, or its header already seen).
    receipt_kv: True only inside receipt files, where four-field key-value
    rows are the accepted variant (d).
    """
    if line != line.rstrip(" "):
        return ("violation", "TRAILING_WHITESPACE")
    if not line:
        return ("blank", "blank line tolerated")
    if receipt_kv and any(v.lower() in KV_BAD_VALUES
                          for v in line.split("\t")):
        return ("violation", "KV_BAD_VALUE")
    m = SUMMARY_RE.match(line)
    if m:
        return ("summary", m.group(1))
    if (VARIANT_CODE_FIRST.match(line) or VARIANT_THREE_FIELD.match(line)
            or VARIANT_COUNTER.match(line)):
        return ("variant", "documented variant typed-warning format")
    if pair_ledger and VARIANT_TSV_ROW.match(line):
        return ("variant", "pair ledger without stage (fallback-glyphs)")
    fields = line.split("\t")
    if len(fields) == 4:
        stage, code, subject, reason = fields
        if (STAGE_RE.match(stage) and CODE_RE.match(code)
                and (code in REGISTERED_CODES or allow_unregistered)
                and subject and subject == subject.strip() and reason):
            return ("ok", code)
    if receipt_kv and len(fields) >= 2 and all(fields):
        head = fields[0]
        if head not in RECEIPT_KV_HEADS:
            return ("violation", "UNREGISTERED_KV_HEAD:%s" % head)
        for v in fields[1:]:
            if v != v.strip():
                return ("violation", "KV_BLANK_FIELD:%s" % head)
            if v.lower() in KV_BAD_VALUES:
                return ("violation", "KV_BAD_VALUE:%s" % head)
        arity = RECEIPT_KV_ARITY.get(head)
        if arity is not None and len(fields) not in arity:
            return ("violation", "KV_ARITY:%s:%d" % (head, len(fields)))
        specs = grammar_shape(head, len(fields))
        if specs is not None:
            for pos, spec in enumerate(specs, 1):
                kind = spec[0]
                if kind == "any":
                    continue
                value = fields[pos]
                if kind == "lit":
                    if value != spec[1]:
                        return ("violation", "KV_GRAMMAR:%s:%d:key:%s"
                                % (head, pos, spec[1]))
                elif not GRAMMAR_VALUE_TYPES[spec[1]].match(value):
                    return ("violation", "KV_GRAMMAR:%s:%d:type:%s"
                            % (head, pos, spec[1]))
        return ("variant", "receipt kv row (variant d, %d fields)" % len(fields))
    if len(fields) != 4:
        return ("violation", "FIELD_COUNT:%d" % len(fields))
    stage, code, subject, reason = fields
    if not STAGE_RE.match(stage):
        return ("violation", "BAD_STAGE")
    if not CODE_RE.match(code):
        return ("violation", "BAD_CODE")
    if code not in REGISTERED_CODES and not allow_unregistered:
        return ("violation", "UNREGISTERED_CODE:%s" % code)
    if not subject or subject != subject.strip():
        return ("violation", "BAD_SUBJECT")
    if not reason:
        return ("violation", "EMPTY_REASON")
    return ("ok", code)


def check_file(path, allow_unregistered):
    """Streaming line pass: O(n) in file size."""
    scope = scope_of(path)
    if scope == "out":
        return {"file": path, "skipped": "out of scope (columnar table or run artifact)"}
    result = {"file": path, "total": 0, "ok": 0, "summary": 0,
              "variant": 0, "blank": 0, "violations": []}
    pair_ledger = os.path.basename(path) in PAIR_LEDGER_FILENAMES
    receipt_kv = bool(RECEIPT_FILE_RE.match(os.path.basename(path))
                      or RUN_FAILURE_RECEIPT_RE.match(os.path.basename(path)))
    saw_cr = False
    with open(path, "r", encoding="utf-8", newline="") as fh:
        try:
            lines = enumerate(fh, 1)
            for lineno, raw_line in lines:
                line = raw_line.rstrip("\n")
                if "\r" in line:
                    saw_cr = True
                    line = line.replace("\r", "")
                if line == PAIR_LEDGER_HEADER and (lineno == 1 or pair_ledger):
                    pair_ledger = True
                    result["total"] += 1
                    result["variant"] += 1
                    continue
                result["total"] += 1
                cls, detail = classify(line, allow_unregistered,
                                       pair_ledger=pair_ledger,
                                       receipt_kv=receipt_kv)
                if cls == "ok":
                    result["ok"] += 1
                elif cls == "summary":
                    result["summary"] += 1
                elif cls == "variant":
                    result["variant"] += 1
                elif cls == "blank":
                    result["blank"] += 1
                else:
                    result["violations"].append(
                        {"line": lineno, "class": detail,
                         "content": line[:120]})
        except UnicodeDecodeError as e:
            result["violations"].insert(0, {"line": None,
                                            "class": "BAD_UTF8",
                                            "content": str(e)[:100]})
    if saw_cr:
        result["violations"].insert(0, {"line": None,
                                        "class": "CR_LINE_ENDINGS",
                                        "content": ""})
    return result


def self_test():
    cases = [
        # (line, pair_ledger, receipt_kv, expected class with registry enforced)
        ("stage1_fit\tfallback_span\tg0041\t3 spans in bowl region", False, False, "ok"),
        ("export\tfallback_export_gate\trun\tship refused: 12 spans", False, False, "ok"),
        ("spacing\tcadence_unobserved\tHN\tno observation, policy fallback", False, False, "ok"),
        ("kern\tguard_degrade\tAV\tambiguity unresolved, excluded", False, False, "ok"),
        ("profiles\tstem_pair_overflow\tpair-17\tmeasurement overflow", False, False, "ok"),
        ("stage1_fit\tring_exclusion\tring2\tdegenerate ring", False, False, "ok"),
        ("fallback_span_total\t12", False, False, "summary"),
        ("fallback_span_total\t12\tstrict run", False, False, "summary"),
        ("encode_nondeterministic\ttrue\tpolicy\tship_first_encode", False, False, "variant"),
        ("export_intent\tfallback_export_warn\tsome text", False, False, "variant"),
        ("glyph_exclusions_total\t4\t(run partial)", False, False, "summary"),
        ("glyph_exclusions_intentional_empty\t2", False, False, "variant"),
        ("glyph_skip_total\t4", False, False, "summary"),
        # pair-ledger rows: variant ONLY in pair-ledger context
        ("g0041\t3", True, False, "variant"),
        ("g0041\t3", False, False, "violation"),
        ("profiles\t199", False, False, "violation"),  # 2-col numeric row elsewhere
        # variant (d): receipt kv four-field rows, ONLY in receipt context
        ("fallback\texclam\tline_spans\t96", False, True, "variant"),
        ("fallback\texclam\tline_spans\t96", False, False, "violation"),
        ("scale_status\tDECLARED_CONVENTION\tcalibrated\tfalse", False, True, "violation"),  # 4 fields, arity 14/30
        # canonical rows still win inside receipts
        ("stage1_fit\tfallback_span\tg0041\t3 spans", False, True, "ok"),
        # variant (d) v7: registered head + N fields inside receipts
        ("run_config\tfit_max_refits\t8\tCOUNT\t-", False, True, "variant"),
        ("otf\tout.otf\tbytes\t1234\tsha256\tabc123", False, True, "variant"),
        ("scale_status\tDECLARED_CONVENTION\tcalibrated\tfalse", False, True, "violation"),  # 4 fields, arity 14/30
        ("manifest_pin\t180f43eac7aca22190a704e88e0bea112e3b34ab63d8c7500", False, True, "variant"),
        ("warning\tspacing_solution_incomplete\texcluded_pairs\t0", False, True, "variant"),
        # conditional-path heads registered from the emitter source
        ("capture\tg0041\tframe_band_measured_px\tt0\tb0\tl0\tr0\tcells\t12", False, True, "variant"),
        ("diagnostic_partial_kern\ttrue\tdegraded default", False, True, "variant"),
        ("population_floor\ttrue", False, True, "variant"),
        # run-failure receipt rows (run_failure.rs writer)
        ("run_failure_receipt\tversion\t1", False, True, "variant"),
        ("code\tSCALE_WIRING_REFUSED", False, True, "variant"),
        ("detail\tbad scale row", False, True, "variant"),
        # variant (d) tightening: arity, bad value, blank/whitespace field
        ("glyph\texclam\tcp\t0x21\tsource_pin\tabc", False, True, "violation"),  # 7 fields, arity 24
        ("glyph_skip_total\tNaN", False, True, "violation"),  # nan count
        ("population_floor\tinf", False, True, "violation"),  # inf value
        ("fallback\texclam\tline_spans\tinfinity", False, True, "variant"),  # "infinity" is a real value
        ("capture\tg0041\tframe_band_measured_px\tt0 b0\tcells\t12", False, True, "violation"),  # arity 9, got 6
        ("scale_status\tDECLARED_CONVENTION\tcalibrated\tfalse\tconvention\tk1\tk_bits\t00\th_ink_height_px\t1\th_ink_units\t2\tem_px\t3\tem_source\ts\tbasis\tb\tscale_id\tx\tcohort\tc", False, True, "violation"),  # arity 14/30, got 16
        ("notdef_evidence_ignored\tShaMismatch", False, True, "variant"),
        ("warning\tkern_gate_degraded\tnote text here", False, True, "variant"),
        ("warning\tkern_gate_degraded", False, True, "violation"),  # 2 fields, warning arity 3+
        ("glyph_skip_total\t4\t", False, True, "violation"),  # empty summary note
        ("export_intent\tinf\tsome warning text", False, True, "violation"),  # bad value before variant b
        ("export_intent\tfallback_export_warn\tsome warning text", False, True, "variant"),
        ("fallback\texclam\tline_spans\t 9", False, True, "violation"),  # whitespace-padded field
        # unknown head in a receipt is a violation, not a variant
        ("mystery_head\ta\tb\tc", False, True, "violation"),
        # field grammar: valid rows of the five grammared heads
        ("glyph\texclam\tcp\t0x21\tsource_pin\t57587a741f3b0879e86b4a9bdf134a8a0bf719a2977e9fb70561d88d796c8624\tsource_kind\tPngConvertedGrayWhiteAlpha\tsource_px\t1485x1050\tscale\t1.9651741293532339\troute\tplain\trings\t148\tnodes\t452\tfinal_area\t3931.544731\tfinal_missing_extrema\t0\trefused\t0", False, True, "variant"),
        ("glyph\texclam\tcp\t0x21\tsource_pin\t57587a741f3b0879e86b4a9bdf134a8a0bf719a2977e9fb70561d88d796c8624\tsource_kind\tPngConvertedGrayWhiteAlpha\tsource_px\t1485x1050\tscale\tfast\troute\tplain\trings\t148\tnodes\t452\tfinal_area\t3931.544731\tfinal_missing_extrema\t0\trefused\t0", False, True, "violation"),  # scale not a float
        ("glyph\tcp\texclam\t0x21\tsource_pin\t57587a741f3b0879e86b4a9bdf134a8a0bf719a2977e9fb70561d88d796c8624\tsource_kind\tPngConvertedGrayWhiteAlpha\tsource_px\t1485x1050\tscale\t1.9651741293532339\troute\tplain\trings\t148\tnodes\t452\tfinal_area\t3931.544731\tfinal_missing_extrema\t0\trefused\t0", False, True, "violation"),  # key order broken
        ("glyph\texclam\tcp\t0x21\tsource_pin\t57587a741f3b0879e86b4a9bdf134a8a0bf719a2977e9fb70561d88d796c8624\tsource_kind\tPngConvertedGrayWhiteAlpha\tsource_px\t1485x1050\tscale\t1.9651741293532339\troute\tplain\trings\t148\tnodes\t452\tfinal_area\t3931.544731\tfinal_missing_extrema\t0\trefused\t0x", False, True, "violation"),  # int position, garbage
        ("kern\tready\t32519\toverlap_held\t0\trejected\t0\tdropped_zero\t0\tclamps_refused\t0\tsolution_complete\ttrue\tfallback_guard_verified\t3", False, True, "variant"),
        ("kern\tready\ttrue\toverlap_held\t0\trejected\t0\tdropped_zero\t0\tclamps_refused\t0\tsolution_complete\ttrue\tfallback_guard_verified\t3", False, True, "violation"),  # ready is a count
        ("vertical\tbaseline_in\t-1478\tshift\t1478\tresidual\t0\texported_baseline\t0\tx_height\t535\tcap_height\t792\tconvention\tFRAME-EXTREMA-TRUE-INK", False, True, "variant"),
        ("vertical\tbaseline_in\t-1478\tshift\t1478\tresidual\t0\texported_baseline\t0\tx_height\t535\tcap_height\t792\tconvention\tframe-extrema-true-ink", False, True, "violation"),  # convention casing
        ("scale_status\tDECLARED_CONVENTION\tcalibrated\tfalse\tconvention\tOwnerDeclaredScaleSet-v2\tk_bits\t3fff715a6d884753\th_ink_height_px\t402\th_ink_units\t790\tem_px\t509\tem_source\tEstimated\tbasis\tFamily\tcross_frame_reuse\tfalse\th_source_pin\t208b0f2f465839d51b815714f86939826ee0762b22580b8101ea8c38dfc3e28d\tscale_id\tMarq/Standard\tcohort\tMarq/Standard\tframe\tMarq-Standard:1485x1050\tcontext_basis\tConvention struct", False, True, "variant"),
        ("scale_status\tDECLARED_CONVENTION\tcalibrated\t0\tconvention\tOwnerDeclaredScaleSet-v2\tk_bits\t3fff715a6d884753\th_ink_height_px\t402\th_ink_units\t790\tem_px\t509\tem_source\tEstimated\tbasis\tFamily\tcross_frame_reuse\tfalse\th_source_pin\t208b0f2f465839d51b815714f86939826ee0762b22580b8101ea8c38dfc3e28d\tscale_id\tMarq/Standard\tcohort\tMarq/Standard\tframe\tMarq-Standard:1485x1050\tcontext_basis\tConvention struct", False, True, "violation"),  # bool position
        ("scale_status\tCONFIG_CONVENTION\tcalibrated\tfalse\tconvention\tOwnerDeclaredScaleSet-v2\tk_bits\t3fff715a6d884753\tscale_id\tMarq/Standard\tcohort\tMarq/Standard\tframe\tMarq-Standard:1485x1050", False, True, "variant"),
        ("spacing\tcomplete\ttrue\texcluded_pairs\t0\texcluded_self\t199\texcluded_below_epsilon\t2856\texcluded_unmeasurable\t4022\tnumeric_failed_pairs\t0\tgeometric_hold_pairs\t2\tno_accepted_candidate_pairs\t0\tfallback_natural_clear_pairs\t0\tfallback_verified_pairs\t3\tnumeric_failed_nonfinite\t0\tnumeric_failed_malformed\t0\tnumeric_failed_natural_unverifiable\t0\tnumeric_failed_natural_frame_conflict\t0\taccounting_residual\t0\taccounting_closed\ttrue\tpolicy\tfree text here", False, True, "variant"),
        ("spacing\tcomplete\ttrue\texcluded_pairs\t0\texcluded_self\t199\texcluded_below_epsilon\t2856\texcluded_unmeasurable\t4022\tnumeric_failed_pairs\t0\tgeometric_hold_pairs\t2\tno_accepted_candidate_pairs\t0\tfallback_natural_clear_pairs\t0\tfallback_verified_pairs\t3\tnumeric_failed_nonfinite\t0\tnumeric_failed_malformed\t0\tnumeric_failed_natural_unverifiable\t0\tnumeric_failed_natural_frame_conflict\t0\taccounting_residual\t0\taccounting_closed\ttrue\tcomplete\tagain", False, True, "violation"),  # policy key clobbered
        # glyph_segments grammar (pending emitter)
        ("glyph_segments\texclam\tline\t12\tcubic\t36\tcubic_pct\t75.000000\tg1\t30\tcorner\t6\tcorner_per_node\t0.125000\tchord_len\t4123.456789\tlen_per_node\t85.905349", False, True, "variant"),
        ("glyph_segments\texclam\tline\t12\tcubic\t36\tcubic_pct\tmany\tg1\t30\tcorner\t6\tcorner_per_node\t0.125000\tchord_len\t4123.456789\tlen_per_node\t85.905349", False, True, "violation"),  # pct not a float
        ("glyph_segments\texclam\tcubic\t12\tline\t36\tcubic_pct\t75.000000\tg1\t30\tcorner\t6\tcorner_per_node\t0.125000\tchord_len\t4123.456789\tlen_per_node\t85.905349", False, True, "violation"),  # key order
        ("glyph_segments\texclam\tline\t12\tcubic\t36\tcubic_pct\t75.000000\tg1\t30\tcorner\t6\tcorner_per_node\t0.125000\tchord_len\t4123.456789", False, True, "violation"),  # arity 17
        # registered head but an empty field blocks variant (d)
        ("fallback\texclam\tline_spans\t", False, True, "violation"),
        ("stage1_fit\tfallback_span\tg0041", False, False, "violation"),      # 3 fields
        ("stage1_fit\tfallback_span\tg0041\tx\ty", False, False, "violation"),# 5 fields
        ("Stage1\tfallback_span\tg0041\treason", False, False, "violation"),  # bad stage
        ("stage1_fit\tFallback-Span\tg0041\treason", False, False, "violation"),
        ("stage1_fit\tunknown_code\tg0041\treason", False, False, "violation"),
        ("stage1_fit\tfallback_span\t g0041\treason", False, False, "violation"),
        ("stage1_fit\tfallback_span\tg0041\t", False, True, "violation"),  # empty field blocks (d) too
        ("stage1_fit\tfallback_span\tg0041\treason ", False, False, "violation"),
        ("", False, False, "blank"),  # blank lines tolerated, not violations
    ]
    failed = 0
    for line, pl, rc, want in cases:
        got, _ = classify(line, allow_unregistered=False, pair_ledger=pl,
                          receipt_kv=rc)
        if got != want:
            failed += 1
            print("SELF-TEST FAIL: %r (pair_ledger=%s receipt_kv=%s) want %s got %s"
                  % (line, pl, rc, want, got))
    # unregistered code passes with the escape hatch
    got, _ = classify("stage1_fit\tunknown_code\tg0041\treason",
                      allow_unregistered=True)
    if got != "ok":
        failed += 1
        print("SELF-TEST FAIL: --allow-unregistered escape hatch")
    # scope classification
    for path, want in [
        ("out/x/fallback-glyphs.tsv", "in"),
        ("out/x/kern-drop-ledger.tsv", "in"),
        ("out/x/ring_skip-Marq.tsv", "in"),
        ("out/x/receipt-Marq-Standard.txt", "in"),
        ("out/x/run-failure-receipt.txt", "in"),
        ("out/x/kern-ledger.tsv", "out"),
        ("out/x/spacing-pair-ledger.tsv", "out"),
        ("out/x/kern-diagnostic.tsv", "out"),
        ("out/x/mapping.tsv", "out"),
        ("out/x/profile-metadata.tsv", "out"),
        ("out/x/spacing.tsv", "out"),
        ("out/x/new-lane-ledger.tsv", "unknown"),
    ]:
        got = scope_of(path)
        if got != want:
            failed += 1
            print("SELF-TEST FAIL: scope_of(%r) want %s got %s" % (path, want, got))
    # grammar shapes: spec counts match their field count, and every
    # grammared arity is a registered arity for that head
    for ghead, gshapes in RECEIPT_KV_GRAMMAR.items():
        for gn, gspecs in gshapes:
            if len(gspecs) != gn - 1:
                failed += 1
                print("SELF-TEST FAIL: grammar %s arity %d has %d specs"
                      % (ghead, gn, len(gspecs)))
            if gn not in RECEIPT_KV_ARITY.get(ghead, ()):
                failed += 1
                print("SELF-TEST FAIL: grammar %s arity %d not registered"
                      % (ghead, gn))
    # the arity registry covers exactly the head registry
    if set(RECEIPT_KV_ARITY) != set(RECEIPT_KV_HEADS):
        failed += 1
        print("SELF-TEST FAIL: RECEIPT_KV_ARITY/RECEIPT_KV_HEADS out of sync: %r"
              % (set(RECEIPT_KV_ARITY) ^ set(RECEIPT_KV_HEADS),))
    # a non-UTF-8 file is a violation, never a crash
    import tempfile
    bin_path = os.path.join(tempfile.mkdtemp(prefix="ledger-check-selftest-"),
                            "receipt-bin.txt")
    with open(bin_path, "wb") as fh:
        fh.write(b"glyph\ta\tb\xab\xfe\n")
    r = check_file(bin_path, allow_unregistered=False)
    if not any(v["class"] == "BAD_UTF8" for v in r["violations"]):
        failed += 1
        print("SELF-TEST FAIL: non-UTF-8 file must yield BAD_UTF8, got %r"
              % r["violations"])
    if failed:
        print("self-test: %d failure(s)" % failed)
        return 1
    print("self-test: %d cases, all pass" % (len(cases) + 14 + 2 * sum(len(s) for s in RECEIPT_KV_GRAMMAR.values())))
    return 0


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    as_json = "--json" in argv
    strict_legacy = "--strict-legacy" in argv or "--strict-variants" in argv
    allow_unregistered = "--allow-unregistered" in argv
    if "--self-test" in argv:
        return self_test()
    if not args:
        print(__doc__.strip())
        return 2
    results = []
    for path in args:
        try:
            results.append(check_file(path, allow_unregistered))
        except OSError as e:
            print("ledger_check: %s: %s" % (path, e), file=sys.stderr)
            return 2
    if as_json:
        print(json.dumps({"schema": SCHEMA, "strict_legacy": strict_legacy,
                          "results": results}, indent=2))
    else:
        for r in results:
            if "skipped" in r:
                print("%s: SKIPPED (%s)" % (r["file"], r["skipped"]))
                continue
            print("%s: %d lines - %d ok, %d summary, %d variant, %d blank, %d violation(s)"
                  % (r["file"], r["total"], r["ok"], r["summary"],
                     r["variant"], r["blank"], len(r["violations"])))
            for v in r["violations"]:
                print("  line %s: %s%s" % (
                    v["line"] if v["line"] is not None else "-",
                    v["class"],
                    (": " + v["content"]) if v["content"] else ""))
    bad = sum(len(r.get("violations", [])) for r in results)
    if strict_legacy:
        bad += sum(r.get("variant", 0) for r in results)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
