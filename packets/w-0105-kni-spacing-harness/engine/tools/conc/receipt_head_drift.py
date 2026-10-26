#!/usr/bin/env python3
"""Receipt kv-head drift test: bind the code registry to the emitters.

ledger_check.py accepts receipt key-value rows (variant d) only when the
row head is in RECEIPT_KV_HEADS. That registry is maintained by hand, so it
can drift from the emitter source in both directions:

- a new emitter writes a receipt row whose head nobody registered
  (the checker would then fail real receipts as UNREGISTERED_KV_HEAD), or
- an emitter is removed or renamed and the registry keeps a dead head.

This test extracts candidate receipt-row heads directly from the Rust
source (string literals containing tab-separated rows pushed into the
receipt) and compares them against RECEIPT_KV_HEADS imported from
ledger_check.py. Any mismatch fails the test:

- UNREGISTERED_RECEIPT_HEAD: emitted head missing from the registry.
  Fix: register the head (schema diff) or, when the row is not a receipt
  row, move it into KNOWN_NON_RECEIPT_HEADS with its provenance.
- STALE_NON_RECEIPT_HEAD: a KNOWN_NON_RECEIPT_HEADS entry is no longer
  emitted anywhere. Fix: delete the entry (the list is self-cleaning).
- MISSING_EMITTER: a registered head is no longer found in the source.
  Fix: remove the head from the registry (schema diff) or, when the
  emitter builds the row in a shape this extractor cannot see, adjust the
  extraction. Today extraction covers every registered head, so a miss
  is a real event, not a known blind spot. Heads whose emitter is
  proposed but not yet landed sit in PENDING_EMITTER_HEADS instead.
- LANDED_PENDING_HEAD: a PENDING_EMITTER_HEADS entry now appears in the
  source. Fix: delete the entry so the head is drift-checked normally.
- UNREGISTERED_PENDING_HEAD: a PENDING_EMITTER_HEADS entry is missing
  from RECEIPT_KV_HEADS. Fix: register it (schema diff) or drop the
  pending entry.

Extraction rules (deliberately simple, errs toward more candidates):
- scan pipeline/src, core/src, metrics/src for *.rs, skipping test files
  and #[cfg(test)] / #[test] item spans;
- take every string literal containing a tab (raw or \\t escape), skipping
  literals on lines that call assert*;
- split the literal into embedded lines (\\n escapes and raw newlines),
  strip one leading format placeholder ("{}..."), and read the first
  tab-separated token as the head when it is a snake_case word of
  length >= 3.

Usage:
    receipt_head_drift.py [--engine-root PATH] [--json]
    receipt_head_drift.py --self-test
Exit 1 on any drift, exit 2 on usage/io errors.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ledger_check import RECEIPT_KV_HEADS  # noqa: E402

SCHEMA = "conc/ledger-schema/9"

SRC_ROOTS = ("pipeline/src", "core/src", "metrics/src")

SNAKE_HEAD_RE = re.compile(r"^[a-z][a-z0-9_]{2,}$")
STRING_LIT_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
TEST_ATTR_RE = re.compile(r"#\[cfg\(test\)\]|#\[test\]")
STRING_OR_CHAR_RE = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)\'')
LEADING_PLACEHOLDER_RE = re.compile(r"^\{[^}]*\}")

# Emitted tab-row heads that are NOT receipt rows, with the destination
# that keeps them out of the receipt registry. Provenance verified against
# the emitting source; the stale-entry check keeps the list exact.
KNOWN_NON_RECEIPT_HEADS = {
    # kni-stage1-cache.txt rows (stage1 cache writer/replay in main.rs)
    "engine_exe_sha256": "stage1-cache row",
    "policy": "stage1-cache row",
    "stage1_identity": "stage1-cache row",
    "scale_binding": "stage1-cache row",
    "receipt_lines": "stage1-cache row",
    "ring": "stage1-cache row",
    "mring": "stage1-cache row",
    # kni-pixel-notdef-evidence files (notdef_producer.rs, validator fixture)
    "kind": "notdef-evidence row",
    "style": "notdef-evidence row / iou manifest header",
    "frame": "notdef-evidence row",
    "scale": "notdef-evidence row",
    "ink_model": "notdef-evidence row",
    "capture_sha256": "notdef-evidence row",
    "pixel_form_sha256": "notdef-evidence row",
    "pixel_source": "notdef-evidence row",
    "selected": "notdef-evidence row",
    # fit_bench report rows (fit_bench.rs render)
    "created_unix": "fit_bench report row",
    "glyph_cpu_sum_s": "fit_bench report row",
    "glyphs": "fit_bench report row",
    "outcome": "fit_bench report row",
    "phase": "fit_bench report row",
    "phases_interrupted": "fit_bench report row",
    "total_s": "fit_bench report row",
    # metrics training_only_fit canonical receipt (metrics tooling output)
    "cell": "metrics training_only_fit row",
    "class": "metrics training_only_fit row",
    "existing": "metrics training_only_fit row",
    "global": "metrics training_only_fit row",
    "outline": "metrics training_only_fit row",
    "prototype": "metrics training_only_fit row",
    "row": "metrics training_only_fit row",
    "stratum": "metrics training_only_fit row",
    "support": "metrics training_only_fit row",
    "wall": "metrics training_only_fit row",
    # metrics gen_production tsv
    "left_gid": "metrics gen_production header",
    # metrics space_measurement ledger
    "module": "metrics space_measurement header",
    "slope_interval": "metrics space_measurement row",
    "slope_interval_px": "metrics space_measurement row",
    # columnar table headers (architect scope ruling: tables out of scope)
    "bucket": "columnar table header",
    "codepoint": "columnar table header",
    "glyph_id": "columnar table header",
    "left": "columnar table header",
    # kern-drop-ledger rows (typed-flag ledger scope, not receipt kv)
    "kern_drop": "kern-drop-ledger row",
    # run-provenance.tsv (out-of-scope artifact)
    "run_out": "run-provenance.tsv row",
    "emitter": "run-provenance.tsv row",
    "profiles": "run-provenance.tsv row",
    # hashed or tsv-escaped into run_config/scale rows, never emitted
    "canonical_scale": "embedded in canonical_record hash input",
    "canonical_scale_member": "population_record audit rows (test-only)",
    "canonical_scale_shared_pin": "shared_content_audit rows (test-only)",
    "reference_calibration": "embedded in canonical_record hash input",
    "reference_calibration_match": "canonical_record match rows (hash input)",
    "reference_calibration_threshold_sensitivity": "diagnostic rows (test-only)",
    "scale_binding_change": "binding_change_row (test-only helper)",
    "scale_context": "tsv-escaped inside run_config row",
    # stderr event, no file row (main.rs eprint)
    "manifest_row_excluded": "stderr event line",
}


def sanitize_source(src):
    """Blank string/char literal contents, preserving length and offsets."""
    return STRING_OR_CHAR_RE.sub(
        lambda m: m.group(0)[0] + " " * (len(m.group(0)) - 2) + m.group(0)[-1],
        src)


def test_item_spans(clean):
    """Spans covered by #[cfg(test)] / #[test] items in sanitized source.

    The item after the attribute ends at the first ';' (brace-less items
    such as statics) or at the matching close brace of the first '{'.
    """
    spans = []
    for m in TEST_ATTR_RE.finditer(clean):
        i = m.end()
        while i < len(clean):
            ch = clean[i]
            if ch == ";":
                spans.append((m.start(), i))
                break
            if ch == "{":
                depth = 0
                for j in range(i, len(clean)):
                    if clean[j] == "{":
                        depth += 1
                    elif clean[j] == "}":
                        depth -= 1
                        if depth == 0:
                            spans.append((m.start(), j))
                            break
                break
            i += 1
    return spans


def extract_candidate_heads(engine_root):
    """Return {head: [file:line, ...]} for every emitted tab-row head."""
    candidates = {}
    for root in SRC_ROOTS:
        base = os.path.join(engine_root, root)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d != "tests"]
            for name in sorted(filenames):
                if not name.endswith(".rs") or "_test" in name:
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, engine_root)
                with open(path, "r", encoding="utf-8") as fh:
                    src = fh.read()
                spans = test_item_spans(sanitize_source(src))
                for m in STRING_LIT_RE.finditer(src):
                    if any(a <= m.start() <= b for a, b in spans):
                        continue
                    lit = m.group(1)
                    if "\\t" not in lit and "\t" not in lit:
                        continue
                    line_start = src.rfind("\n", 0, m.start()) + 1
                    line_end = src.find("\n", m.end())
                    if line_end == -1:
                        line_end = len(src)
                    if "assert" in src[line_start:line_end]:
                        continue
                    lineno = src.count("\n", 0, m.start()) + 1
                    norm = lit.replace("\t", "\\t")
                    for embedded in re.split(r"\\n|\n", norm):
                        embedded = embedded.lstrip(" ")
                        embedded = LEADING_PLACEHOLDER_RE.sub("", embedded)
                        if "\\t" not in embedded:
                            continue
                        head = embedded.split("\\t")[0]
                        if SNAKE_HEAD_RE.match(head):
                            candidates.setdefault(head, [])
                            ref = "%s:%d" % (rel, lineno)
                            if ref not in candidates[head]:
                                candidates[head].append(ref)
    return candidates


# Registered heads whose emitter is proposed but has not landed yet,
# with the proposal that carries the emitter draft. Drift tolerates the
# absence; once the emitter lands the entry must leave this set.
PENDING_EMITTER_HEADS = {
    "glyph_segments": "docs/conc/receipt-segment-metrics-proposal.md",
}


def compare(candidates, registry, exceptions, pending=()):
    """Return a list of (kind, head, detail) drift issues."""
    issues = []
    for head in sorted(set(candidates) - set(registry) - set(exceptions)):
        refs = ", ".join(candidates[head][:3])
        issues.append(("UNREGISTERED_RECEIPT_HEAD", head,
                       "emitted but not in RECEIPT_KV_HEADS (%s)" % refs))
    for head in sorted(set(exceptions) - set(candidates)):
        issues.append(("STALE_NON_RECEIPT_HEAD", head,
                       "no longer emitted; remove from KNOWN_NON_RECEIPT_HEADS (%s)"
                       % exceptions[head]))
    for head in sorted(set(registry) - set(candidates) - set(pending)):
        issues.append(("MISSING_EMITTER", head,
                       "registered head not found in emitter source"))
    for head in sorted(set(pending) & set(candidates)):
        issues.append(("LANDED_PENDING_HEAD", head,
                       "emitter landed; remove from PENDING_EMITTER_HEADS (%s)"
                       % pending[head]))
    for head in sorted(set(pending) - set(registry)):
        issues.append(("UNREGISTERED_PENDING_HEAD", head,
                       "pending head missing from RECEIPT_KV_HEADS"))
    return issues


def self_test():
    failed = 0

    def check(name, cond):
        nonlocal failed
        if not cond:
            failed += 1
            print("SELF-TEST FAIL: %s" % name)

    reg = {"alpha_row", "beta_row"}
    exc = {"gamma_row": "unit test"}
    check("clean sets pass",
          compare({"alpha_row": ["x.rs:1"], "beta_row": ["x.rs:2"],
                   "gamma_row": ["x.rs:3"]}, reg, exc) == [])
    kinds = {k for k, _, _ in compare(
        {"alpha_row": ["x.rs:1"], "delta_row": ["x.rs:9"]}, reg, exc)}
    check("unregistered + missing + stale detected",
          kinds == {"UNREGISTERED_RECEIPT_HEAD", "MISSING_EMITTER",
                    "STALE_NON_RECEIPT_HEAD"})
    # pending heads: absence tolerated, landing flagged, unregistered flagged
    base = {"alpha_row": ["x.rs:1"], "beta_row": ["x.rs:2"],
            "gamma_row": ["x.rs:3"]}
    check("pending absence tolerated",
          compare(base, reg | {"eta_row"}, exc,
                  {"eta_row": "proposal"}) == [])
    kinds = {k for k, _, _ in compare(
        dict(base, eta_row=["x.rs:7"]), reg | {"eta_row"}, exc,
        {"eta_row": "proposal"})}
    check("landed pending flagged", kinds == {"LANDED_PENDING_HEAD"})
    kinds = {k for k, _, _ in compare(base, reg, exc,
                                      {"eta_row": "proposal"})}
    check("unregistered pending flagged",
          kinds == {"UNREGISTERED_PENDING_HEAD"})

    # end-to-end extraction over a synthetic tree
    import tempfile
    tree = tempfile.mkdtemp(prefix="receipt-head-drift-selftest-")
    srcdir = os.path.join(tree, "pipeline", "src")
    os.makedirs(srcdir)
    with open(os.path.join(srcdir, "demo.rs"), "w", encoding="utf-8") as fh:
        fh.write(
            'fn emit(receipt: &mut String) {\n'
            '    receipt.push_str(&format!("alpha_row\\t{}\\tkey\\t{}\\n", a, b));\n'
            '    receipt.push_str("beta_row\traw_tab\\tkey\tvalue\\n");\n'
            '    receipt.push_str(&format!("{}gamma_row\\tcomposed\\t{}\\n", p, q));\n'
            '}\n'
            '#[cfg(test)]\n'
            'mod tests {\n'
            '    fn t() { assert_eq!("delta_row\\thidden\\tx", "x"); }\n'
            '}\n'
            '#[cfg(test)]\n'
            'static FLAG: bool = true;\n'
            'fn after(receipt: &mut String) {\n'
            '    receipt.push_str("epsilon_row\\tafter_static\\tx\\n");\n'
            '}\n')
    found = extract_candidate_heads(tree)
    check("escaped-tab literal head", "alpha_row" in found)
    check("raw-tab literal head", "beta_row" in found)
    check("placeholder-prefixed head", "gamma_row" in found)
    check("test-module literal excluded", "delta_row" not in found)
    check("production literal after cfg(test) static kept",
          "epsilon_row" in found)

    if failed:
        print("self-test: %d failure(s)" % failed)
        return 1
    print("self-test: all cases pass")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    engine_root = os.path.normpath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    args = argv[1:]
    if "--engine-root" in args:
        i = args.index("--engine-root")
        engine_root = args[i + 1]
        del args[i:i + 2]
    use_json = "--json" in args
    candidates = extract_candidate_heads(engine_root)
    issues = compare(candidates, RECEIPT_KV_HEADS, KNOWN_NON_RECEIPT_HEADS,
                     PENDING_EMITTER_HEADS)
    report = {
        "schema": SCHEMA,
        "engine_root": engine_root,
        "candidates": len(candidates),
        "registry_heads": len(RECEIPT_KV_HEADS),
        "non_receipt_heads": len(KNOWN_NON_RECEIPT_HEADS),
        "pending_emitter_heads": len(PENDING_EMITTER_HEADS),
        "issues": [{"kind": k, "head": h, "detail": d} for k, h, d in issues],
    }
    if use_json:
        print(json.dumps(report, indent=1))
    else:
        print("receipt head drift: %d candidate heads, %d registered, %d known non-receipt"
              % (report["candidates"], report["registry_heads"],
                 report["non_receipt_heads"]))
        for kind, head, detail in issues:
            print("%s: %s: %s" % (kind, head, detail))
        print("DRIFT %s" % ("FAIL" if issues else "PASS"))
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
