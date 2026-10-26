#!/usr/bin/env python3
"""Mutation test for the ledger gate's negative scope.

Takes real receipt lines (and an embedded synthetic set covering canonical
and summary rows), applies single mutations a corrupted or hand-edited
receipt would show, and verifies the checker flags every one of them as a
violation. Any mutation that still classifies as ok/summary/variant is an
escape: the gate's blind spot.

Operators come in two classes:

- must-catch: head typos, deleted/duplicated/blanked fields, NaN/Inf
  values, whitespace damage, tab-to-space, CR injection, arity breaks.
  An escape here fails the test (exit 1).
- known-escape: mutations that are structurally indistinguishable from a
  valid row under the current schema (adjacent-field reorder inside a
  same-arity kv row, swapping the head for another registered head of the
  same arity, garbage appended to a free-text value). The field grammar
  (RECEIPT_KV_GRAMMAR) closes these for the heads it covers: a mutation
  landing on a grammar-shaped head and arity is a must-catch. Remaining
  known escapes are listed for the architect.

Usage:
    ledger_mutation_test.py [--receipt PATH]... [--json]
Exit 1 when any must-catch mutation escapes, exit 2 on usage/io errors.
"""
import json
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ledger_check import (check_file, RECEIPT_KV_HEADS, RECEIPT_KV_ARITY,  # noqa: E402
                          SUMMARY_RE, VARIANT_COUNTER, grammar_shape)

NUMERIC_RE = re.compile(r"^-?\d+(\.\d+)?([eE][+-]?\d+)?$")


def _swap_head_typo(head):
    for i in (len(head) - 2, 0, 1):
        if i + 1 < len(head):
            typo = head[:i] + head[i + 1] + head[i] + head[i + 2:]
            if typo != head and typo not in RECEIPT_KV_HEADS:
                return typo
    return None


def _first_numeric(fields):
    for i in range(1, len(fields)):
        if NUMERIC_RE.match(fields[i]):
            return i
    return None


# each operator: (name, must_catch, fn(fields) -> mutated fields | None)
def op_head_typo(f):
    t = _swap_head_typo(f[0])
    return [t] + f[1:] if t else None

def op_delete_last(f):
    return f[:-1] if len(f) >= 3 else None

def op_delete_middle(f):
    return f[:2] + f[3:] if len(f) >= 4 else None

def op_head_only(f):
    return f[:1]

def op_blank_middle(f):
    return f[:2] + [""] + f[3:] if len(f) >= 3 else None

def op_space_middle(f):
    return f[:2] + [" "] + f[3:] if len(f) >= 3 else None

def op_nan_numeric(f):
    i = _first_numeric(f)
    return f[:i] + ["NaN"] + f[i + 1:] if i else None

def op_inf_value(f):
    return f[:1] + ["inf"] + f[2:] if len(f) >= 2 else None

def op_duplicate_middle(f):
    return f[:2] + [f[2]] + f[2:] if len(f) >= 3 else None

def op_reorder_adjacent(f):  # escape only outside grammar heads
    return [f[0]] + [f[2], f[1]] + f[3:] if len(f) >= 3 else None

def op_head_swap_same_arity(f):  # escape only outside grammar heads
    want = RECEIPT_KV_ARITY.get(f[0])
    for h in sorted(RECEIPT_KV_HEADS):
        if h != f[0] and RECEIPT_KV_ARITY.get(h) == want and h != "warning":
            return [h] + f[1:]
    return None

def op_numeric_garbage(f):  # escape only outside grammar heads
    i = _first_numeric(f)
    return f[:i] + [f[i] + "x"] + f[i + 1:] if i else None

FIELD_OPS = [
    ("head_typo", True, op_head_typo),
    ("delete_last_field", True, op_delete_last),
    ("delete_middle_field", True, op_delete_middle),
    ("drop_to_head_only", True, op_head_only),
    ("blank_middle_field", True, op_blank_middle),
    ("space_middle_field", True, op_space_middle),
    ("nan_numeric_value", True, op_nan_numeric),
    ("inf_value", True, op_inf_value),
    ("duplicate_middle_field", True, op_duplicate_middle),
    ("reorder_adjacent_fields", False, op_reorder_adjacent),
    ("head_swap_same_arity", False, op_head_swap_same_arity),
    ("numeric_garbage", False, op_numeric_garbage),
]


def line_cases(line):
    """Whole-line mutations plus the per-field operators."""
    fields = line.split("\t")
    for name, must, fn in FIELD_OPS:
        mutated = fn(fields)
        if mutated is not None and mutated != fields:
            yield name, must, "\t".join(mutated)
    yield "tab_to_space", True, " ".join(fields)
    yield "trailing_space", True, line + " "
    yield "cr_embedded", True, fields[0] + "\r\t" + "\t".join(fields[1:])


SYNTHETIC_LINES = [
    # canonical 4-field rows
    "stage1_fit\tfallback_span\tg0041\t3 spans in bowl region",
    # summary rows
    "glyph_skip_total\t4",
    "glyph_skip_total\t4\tstrict run",
    # kv rows of several arities
    "otf\tout.otf\tbytes\t1234\tsha256\tabc123",
    "population_floor\ttrue",
    "notdef_evidence_ignored\tShaMismatch",
    "warning\tkern_gate_degraded\tnote text",
    # grammared kv row (pending emitter head)
    "glyph_segments\tg0041\tline\t12\tcubic\t36\tcubic_pct\t75.000000\tg1\t30\tcorner\t6\tcorner_per_node\t0.125000\tchord_len\t4123.456789\tlen_per_node\t85.905349",
]


def is_known_escape(op, orig_fields, mutated_line):
    """Schema-level blind spots, decided from the schema data itself (never
    from the checker's verdict, or the test could not fail).

    - head typo on a canonical 4-field row: the stage vocabulary is open
      by design, so a stage typo is undetectable;
    - delete/duplicate/reorder that lands on a shape the schema accepts
      anyway (a legal summary/counter form, or a legal arity for the
      head): structurally indistinguishable from a valid row.
    """
    if op == "head_typo":
        return len(orig_fields) == 4 and orig_fields[0] not in RECEIPT_KV_HEADS
    if op in ("delete_last_field", "delete_middle_field",
              "duplicate_middle_field", "reorder_adjacent_fields"):
        if SUMMARY_RE.match(mutated_line) or VARIANT_COUNTER.match(mutated_line):
            return True
        mf = mutated_line.split("\t")
        arity = RECEIPT_KV_ARITY.get(mf[0])
        return (arity is not None and len(mf) in arity
                and grammar_shape(mf[0], len(mf)) is None)
    return False


def check_line(line, workdir):
    """Run check_file on a one-line receipt; return (violations, classes)."""
    path = os.path.join(workdir, "receipt-mutation.txt")
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(line + "\n")
    r = check_file(path, allow_unregistered=False)
    return [v["class"] for v in r["violations"]]


def run(lines, json_out):
    workdir = tempfile.mkdtemp(prefix="ledger-mutation-")
    caught = escaped = known = 0
    escapes, known_escapes = [], []
    for lineno, line in enumerate(lines, 1):
        if not line or line != line.rstrip(" "):
            continue
        fields0 = line.split("\t")
        for op, must, mutated in line_cases(line):
            if mutated == line:
                continue
            if must and is_known_escape(op, fields0, mutated):
                must = False
            classes = check_line(mutated, workdir)
            mf = mutated.split("\t")
            if classes:
                caught += 1
            elif must or grammar_shape(mf[0], len(mf)) is not None:
                escaped += 1
                escapes.append({"line": lineno, "op": op,
                                "mutated": mutated[:120]})
            else:
                known += 1
                known_escapes.append({"line": lineno, "op": op,
                                      "mutated": mutated[:120]})
    report = {
        "cases": caught + escaped + known,
        "caught": caught,
        "escaped_must_catch": escapes,
        "known_escapes": known_escapes,
    }
    if json_out:
        print(json.dumps(report, indent=1))
    else:
        print("mutation test: %d cases - %d caught, %d escaped must-catch, "
              "%d known escapes" % (report["cases"], caught,
                                    len(escapes), len(known_escapes)))
        for e in escapes[:20]:
            print("  ESCAPE line %d %s: %s" % (e["line"], e["op"], e["mutated"]))
        if len(escapes) > 20:
            print("  ... %d more escapes" % (len(escapes) - 20))
        ops = sorted({e["op"] for e in known_escapes})
        print("  known-escape operators (schema limitation, listed for the "
              "architect): %s" % ", ".join(ops))
    return 1 if escapes else 0


def main(argv):
    args = argv[1:]
    json_out = "--json" in args
    receipts = []
    i = 0
    while i < len(args):
        if args[i] == "--receipt":
            receipts.append(args[i + 1])
            i += 2
        else:
            i += 1
    lines = list(SYNTHETIC_LINES)
    for path in receipts:
        with open(path, "r", encoding="utf-8") as fh:
            lines.extend(l.rstrip("\n") for l in fh)
    return run(lines, json_out)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
