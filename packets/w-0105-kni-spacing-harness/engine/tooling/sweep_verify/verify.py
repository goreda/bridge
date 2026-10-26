"""One command: sweep integrity (sweepaudit) and schema validation of its record.

python3 verify.py --root DIR --expected keys.txt --config cfg.json --schema sweep-record.schema.json --out NEW_DIR [--strict]

Runs sweepaudit, writes receipt.txt and record.json into NEW_DIR (which must not exist), validates record.json
against the schema (strict JSON, Draft 2020-12) and checks that receipt_sha256 is the hash of receipt.txt.
Exit code 0: the record is schema-valid and bound to the receipt. 1: schema or binding failure, or --strict with
complete=false. 2: input or file error. Schema validity says nothing about the sweep content; completeness is
in the record as a descriptive flag. Requires jsonschema (pinned in requirements-ci.txt).
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "sweepaudit"))
from sweepaudit.core import audit, config_from_dict, load_json_strict, RECEIPT_VERSION, _esc  # noqa: E402

LIST_KEYS = ("missing", "doubled", "conflict", "unclassified", "unexpected", "unkeyed", "empty", "unreadable",
             "changed", "required_missing", "pair_differ", "pair_b_missing", "pair_b_without_a",
             "unexpected_files", "symlinks", "truncated", "tsv_anomalies", "unmatched_exceptions", "pattern_timeout", "sweep_level")


def build_record(receipt_text, summary):
    return {
        "mode": "DESCRIPTIVE ONLY",
        "threshold_policy": "NONE; no decision gate",
        "sweep_compatibility": "UNVERIFIED; adapter over the listing and examples supplied for the sweep",
        "receipt_version": RECEIPT_VERSION,
        "receipt_sha256": hashlib.sha256(receipt_text.encode()).hexdigest(),
        "expected_list_sha256": summary["expected_list_sha256"],
        "config_sha256": summary["config_sha256"],
        "counts": {"expected_keys": summary["expected_keys"], "files_total": summary["files_total"],
                   "one_result": int(summary["one_result"]), "one_refusal": int(summary["one_refusal"]),
                   "tsv_skipped_hash_lines": int(summary["tsv_skipped_hash_lines"]),
                   "keyed": int(summary["keyed"]), "unkeyed": len(summary["unkeyed"]), "symlinks": len(summary["symlinks"]),
                   "sweep_level": len(summary["sweep_level"]), "unreadable_files": int(summary["unreadable_files"]),
                   "tsv_anomalies": len(summary["tsv_anomalies"]), "pattern_timeouts": len(summary["pattern_timeout"]),
                   "unmatched_exceptions": len(summary["unmatched_exceptions"])},
        "lists": {k: sorted(str(x) for x in summary[k]) for k in LIST_KEYS},
        "complete": bool(summary["complete"]),
    }


def validate(record, schema):
    from jsonschema import Draft202012Validator
    Draft202012Validator.check_schema(schema)
    errs = [("/" + "/".join(map(str, e.path)) + ": " + e.message) for e in Draft202012Validator(schema).iter_errors(record)]
    c, lists = record.get("counts", {}), record.get("lists", {})
    if isinstance(c, dict) and isinstance(lists, dict):
        for ck, lk in (("unkeyed", "unkeyed"), ("symlinks", "symlinks"), ("sweep_level", "sweep_level"), ("tsv_anomalies", "tsv_anomalies"),
                       ("pattern_timeouts", "pattern_timeout"), ("unmatched_exceptions", "unmatched_exceptions")):
            if ck in c and isinstance(lists.get(lk), list) and c[ck] != len(lists[lk]):
                errs.append("/counts/%s: %s does not equal the length of lists/%s (%d)" % (ck, c[ck], lk, len(lists[lk])))
        cls = ("keyed", "unkeyed", "sweep_level", "unreadable_files", "symlinks")
        if all(isinstance(c.get(k), int) for k in cls + ("files_total",)) and sum(c[k] for k in cls) != c["files_total"]:
            errs.append("/counts: keyed + unkeyed + sweep_level + unreadable_files + symlinks does not equal files_total")
        if isinstance(c.get("unreadable_files"), int) and isinstance(lists.get("unreadable"), list) and c["unreadable_files"] > len(lists["unreadable"]):
            errs.append("/counts/unreadable_files: exceeds the length of lists/unreadable")
    return sorted(errs)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--expected", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--schema", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args(argv)
    out = Path(a.out)
    if out.exists():
        sys.stderr.write("INPUT_ERROR: --out already exists\n")
        return 2
    if not out.parent.is_dir():
        sys.stderr.write("INPUT_ERROR: parent directory of --out does not exist\n")
        return 2
    try:
        schema = load_json_strict(Path(a.schema).read_bytes())
        c = load_json_strict(Path(a.config).read_bytes())
        expected_text = Path(a.expected).read_bytes().decode("utf-8")
        cfg = config_from_dict(c)
        receipt, summary = audit(a.root, expected_text, cfg)
    except (OSError, ValueError, KeyError, TypeError, re.error) as e:
        sys.stderr.write("INPUT_ERROR: %s\n" % _esc(str(e)))
        return 2
    record = build_record(receipt, summary)
    errors = validate(record, schema)
    try:
        out.mkdir(parents=False)
        (out / "receipt.txt").write_text(receipt, encoding="utf-8")
        (out / "record.json").write_text(json.dumps(record, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    except OSError as e:
        sys.stderr.write("INPUT_ERROR: %s\n" % _esc(str(e)))
        return 2
    bound = hashlib.sha256((out / "receipt.txt").read_bytes()).hexdigest() == record["receipt_sha256"]
    if errors or not bound:
        for e in errors:
            print(e)
        if not bound:
            print("/receipt_sha256: does not match receipt.txt")
        return 1
    print("SCHEMA_VALID_DESCRIPTIVE_ONLY; complete=%s is a descriptive flag, sweep content and real writer compatibility unverified" % str(record["complete"]).lower())
    return 1 if (a.strict and not record["complete"]) else 0


if __name__ == "__main__":
    sys.exit(main())
